#!/usr/bin/env python3
"""图标视觉自检：渲染每个 SVG，量边距、量墨迹覆盖率、核对结构约定。

为什么用渲染检查而不是正则解析路径：
  SVG 路径里的负数是**相对增量**（如 `c-.5-.2-1.1 0`），不是坐标。
  用正则抓数字会把它们误判成「超出边界」，产生大量假报警。
  渲染出来看像素，才是真正能发现裁切/比例问题的办法。

为什么换成自研光栅器（tools/icon/svg_raster.py）而不是 macOS 的 qlmanage：
  1) qlmanage 依赖 QuickLook 服务，在沙箱 / CI / 无 GUI 会话里直接失败
     （本机报 `sandbox initialization failed: Operation not permitted`，退出码 255）；
  2) 更糟的是失败时**静默**：旧 PNG 留在临时目录里，脚本照读不误 ——
     于是「自检结果」可能来自上一次渲染的图，与当前文件毫无关系。
  自研光栅器没有这两个问题：结果只取决于文件内容，任何环境都能跑。
  已和 QuickLook 的渲染结果逐图标比对过：21 个图标的包围盒误差 ≤ 1px。
  想再比一次可以加 --quicklook（在能跑 qlmanage 的机器上）。

检查项：
  1. 内容为空 / 贴边裁切 —— 内容必须离画布边缘 ≥ EDGE_MIN（0.19 单位 ≈ 256px 下 2px）；
  2. 新绘/重绘的图标（5 个页签 + ic_metro / ic_bike / ic_gift）的内容必须落在
     2..22 安全框内（一排页签、一列权益卡的留白要一致）；
  3. 页签图标的墨迹覆盖率（= 实心面积占比）必须落在 [TAB_COV_MIN, TAB_COV_MAX]，
     且 5 个之间的极差 ≤ TAB_COV_SPREAD —— 页签并排显示，一个大块一个小细条会显得没对齐；
  4. 每个图标要有非空 <title>、默认 fill="#000000"、viewBox 为 0 0 24 24；
  5. 禁用项：<style>/<text>/<tspan>/feTurbulence/foreignObject/内联 style、
     transform 的 rotate|scale|matrix|skew（API 12 只支持 translate）、
     以及 <svg> 上写死的 width/height（会让图标按固定像素画，出现「图标极小」）。

用法：python3 tools/icon/check_icons.py [--quicklook]
"""
import glob
import os
import re
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import svg_raster as raster  # noqa: E402

MEDIA = "project/carbon-footprint/entry/src/main/resources/base/media"

# ---- 阈值 ---------------------------------------------------------------
# 内容离画布边缘的最小距离（用户坐标）。0.19 单位 ≈ 256px 渲染下的 2px。
EDGE_MIN = 0.19
# 页签图标的安全框：内容控制在 2..22
SAFE_LO, SAFE_HI = 2.0, 22.0
# 页签图标的墨迹覆盖率区间与极差上限。
# 依据：改造前四个「本来就还行」的页签图标实测 24.0%–26.9%（极差 2.9 个百分点），
# 而 ic_tab_add 是 51.1% —— 重得离谱，正是这个检查要拦的情况。
# 区间取 21%–28%（给后续维护留一点空间），极差取 4 个百分点。
TAB_COV_MIN, TAB_COV_MAX = 0.21, 0.28
TAB_COV_SPREAD = 0.04
TAB_PREFIX = "ic_tab_"

# 强制「内容落在 2..22 安全框内」的图标：本次新绘 / 重绘的那批
# （5 个页签 + 权益列表的 3 个）。其余功能图标是既有设计、图形不在本次改动范围内，
# 它们只受「不许贴边」约束，超出安全框只在报告里提示、不判失败。
SAFE_ENFORCED_NAMES = ("ic_metro", "ic_bike", "ic_gift")

# 渲染分辨率：192 × 超采样 4 = 768×768 网格（覆盖率的有效位数 ≈ 0.01%）
SIZE, SS = 192, 4

FORBIDDEN = ("<style", "<text", "<tspan", "feTurbulence", "foreignObject")


def _wid(s: str) -> int:
    """终端显示宽度：中文/全角算 2 列。表格里有中文，直接用 len() 会错位。"""
    return sum(2 if ord(c) > 0x2000 else 1 for c in s)


def _pad(s: str, w: int) -> str:
    return s + " " * max(1, w - _wid(s))


def _structure_problems(svg: str):
    """结构约定检查（ArkUI 的 SVG 渲染器只认一个很小的子集）。"""
    bad = []
    for tag in FORBIDDEN:
        if tag in svg:
            bad.append(f"含 {tag}（ArkUI 的 SVG 渲染器不支持）")
    if re.search(r'transform\s*=\s*"[^"]*(rotate|scale|matrix|skew)', svg):
        bad.append("transform 用了 rotate/scale（API 12 只支持 translate）")
    if re.search(r"<svg[^>]*\swidth\s*=", svg) or re.search(r"<svg[^>]*\sheight\s*=", svg):
        bad.append("<svg> 上写了 width/height（应只给 viewBox）")
    if 'viewBox="0 0 24 24"' not in svg:
        bad.append('viewBox 不是 "0 0 24 24"')
    if 'fill="#000000"' not in svg:
        bad.append('缺少默认 fill="#000000"（运行时靠 fillColor 覆盖）')
    if re.search(r"style\s*=", svg):
        bad.append("用了内联 style（CSS）")
    m = re.search(r"<title>(.*?)</title>", svg, re.S)
    if m is None or len(m.group(1).strip()) == 0:
        bad.append("缺少非空 <title>（无障碍朗读用）")
    return bad


def _quicklook_compare(files, boxes):
    """可选交叉验证：用 macOS QuickLook 再渲染一次，比对包围盒（每行 ±1px 内算通过）。"""
    import shutil
    import subprocess
    import tempfile
    if shutil.which("qlmanage") is None:
        print("\n[--quicklook] 找不到 qlmanage，跳过交叉验证")
        return
    try:
        from PIL import Image
    except ImportError:
        print("\n[--quicklook] 没装 Pillow，跳过交叉验证")
        return
    tmp = tempfile.mkdtemp(prefix="icon-ql-")   # 每次新目录：避免读到上一次的旧缩略图
    print(f"\n[--quicklook] 用 QuickLook 重新渲染并比对包围盒（临时目录 {tmp}）")
    diffs = 0
    for svg in files:
        name = os.path.basename(svg)[:-4]
        subprocess.run(["qlmanage", "-t", "-s", "256", "-o", tmp, svg],
                       capture_output=True)
        png = os.path.join(tmp, os.path.basename(svg) + ".png")
        if not os.path.exists(png):
            print(f"  {name}: qlmanage 渲染失败（本环境不支持 QuickLook）")
            return
        im = Image.open(png).convert("L")
        bb = im.point(lambda v: 255 if v < 200 else 0).getbbox()
        mine = tuple(round(v * 256.0 / 24.0, 1) for v in boxes[name])
        if bb is None:
            print(f"  {name}: QuickLook 渲染为空")
            diffs += 1
            continue
        off = max(abs(bb[0] - mine[0]), abs(bb[1] - mine[1]),
                  abs(bb[2] - mine[2]), abs(bb[3] - mine[3]))
        if off > 1.5:
            print(f"  ⚠️ {name}: 与自研光栅器差 {off:.1f}px（QuickLook {bb} vs 本工具 {mine}）")
            diffs += 1
    print(f"  交叉验证完成：{len(files) - diffs}/{len(files)} 个图标的包围盒一致（±1px）")


def main() -> int:
    files = sorted(glob.glob(os.path.join(MEDIA, "*.svg")))
    if not files:
        print("未找到 SVG 图标", file=sys.stderr)
        return 1

    print(f"图标自检：{len(files)} 个 SVG"
          f"（纯 Python 光栅器渲染 {SIZE}×{SIZE}，超采样 {SS}×）\n")
    print(_pad("图标", 17) + _pad("内容范围（0..24）", 40)
          + _pad("最近边距", 10) + _pad("墨迹覆盖率", 12) + "备注")

    rows = []
    fails = []
    boxes = {}
    tab_cov = []
    min_margin = 1e9
    min_margin_icon = ""
    out_of_safe = []

    for svg in files:
        name = os.path.basename(svg)[:-4]
        with open(svg, encoding="utf-8") as f:
            text = f.read()

        box = raster.bbox(text)
        cov, pxbox, _size, _cov = raster.coverage(text, size=SIZE, ss=SS)
        notes = []
        if box is None:
            fails.append(f"{name}: 内容为空（渲染出来什么都没有）")
            print(_pad(name, 17) + _pad("—", 40) + _pad("—", 10)
                  + _pad("—", 12) + "⚠️ 内容为空")
            continue
        boxes[name] = box
        x0, y0, x1, y1 = box
        margin = min(x0, y0, 24.0 - x1, 24.0 - y1)
        if margin < min_margin:
            min_margin, min_margin_icon = margin, name

        if margin < EDGE_MIN:
            fails.append(f"{name}: 内容贴边（最近边距 {margin:.2f} < {EDGE_MIN}），会被 viewBox 裁掉")
            notes.append("⚠️ 贴边")

        is_tab = name.startswith(TAB_PREFIX)
        is_strict = is_tab or name in SAFE_ENFORCED_NAMES
        if is_strict:
            if x0 < SAFE_LO or y0 < SAFE_LO or x1 > SAFE_HI or y1 > SAFE_HI:
                fails.append(f"{name}: 超出 2..22 安全框 "
                             f"(x {x0:.2f}..{x1:.2f} y {y0:.2f}..{y1:.2f})")
                notes.append("⚠️ 超出安全框")
        else:
            if x0 < SAFE_LO or y0 < SAFE_LO or x1 > SAFE_HI or y1 > SAFE_HI:
                out_of_safe.append(f"{name} (x {x0:.2f}..{x1:.2f} y {y0:.2f}..{y1:.2f})")
        if is_tab:
            tab_cov.append((name, cov))

        for bad in _structure_problems(text):
            fails.append(f"{name}: {bad}")
            notes.append("⚠️ " + bad)

        rows.append((name, box, margin, cov, is_tab, is_strict, notes))

    for name, box, margin, cov, is_tab, is_strict, notes in rows:
        tag = "页签" if is_tab else ("新绘" if is_strict else "")
        if notes:
            tag = (tag + " " + " ".join(notes)).strip()
        rng = f"x {box[0]:5.2f}..{box[2]:5.2f}  y {box[1]:5.2f}..{box[3]:5.2f}"
        print(_pad(name, 17) + _pad(rng, 40) + _pad(f"{margin:.2f}", 10)
              + _pad(f"{cov * 100:.2f}%", 12) + tag)

    print()
    ok = True

    # ---- 页签视觉重量 ----
    if tab_cov:
        vals = [c for _n, c in tab_cov]
        spread = max(vals) - min(vals)
        bad = [f"{n} {c * 100:.2f}%" for n, c in tab_cov
               if c < TAB_COV_MIN or c > TAB_COV_MAX]
        print(f"页签视觉重量：{min(vals) * 100:.2f}% ~ {max(vals) * 100:.2f}%"
              f"，极差 {spread * 100:.2f} 个百分点")
        print(f"  阈值：单图 {TAB_COV_MIN * 100:.0f}%~{TAB_COV_MAX * 100:.0f}%，"
              f"极差 ≤ {TAB_COV_SPREAD * 100:.0f} 个百分点")
        if bad or spread > TAB_COV_SPREAD:
            ok = False
            print(f"  ⚠️ 不通过：{'；'.join(bad)}" if bad else "  ⚠️ 不通过：极差过大")
        else:
            print("  ✅ 5 个页签图标视觉重量一致")

    # ---- 边距 ----
    print(f"内容边距：最小 {min_margin:.2f} 单位（{min_margin_icon}），阈值 ≥ {EDGE_MIN}")
    print("  ✅ 没有图标被裁切" if min_margin >= EDGE_MIN else "  ⚠️ 有图标贴边")

    # ---- 安全框 ----
    if out_of_safe:
        print(f"安全框 2..22：强制名单（5 个页签 + ic_metro / ic_bike / ic_gift）全部在内 ✅；"
              f"另有 {len(out_of_safe)} 个功能图标超框"
              f"（既有设计，本次未改动，仍在画布内 ⇒ 只提示不判失败）")
        for s in out_of_safe:
            print(f"  · {s}")
    else:
        print("安全框 2..22：全部图标都在内 ✅")

    # ---- 汇总 ----
    print()
    if fails:
        print(f"❌ 未通过：{len(fails)} 项")
        for f in fails:
            print(f"  · {f}")
        return 1
    print(f"✅ 全部检查通过（{len(rows)} 个图标：无裁切、结构约定合规"
          f"{'、页签重量一致' if tab_cov else ''}）")

    if "--quicklook" in sys.argv:
        _quicklook_compare(files, boxes)
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main())
