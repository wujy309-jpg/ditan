#!/usr/bin/env python3
"""碳迹 —— 演示数据填充（UI 自动化，走应用自己的录入表单）。

为什么用 Python 而不是 bash：
    这个任务需要**看着屏幕做决定** —— 输入框和保存按钮的位置会随内容变化
    （每多一条记录、多一行校验提示，整页就往下挪几十到几百像素），
    bash 里写死坐标必然错位。Python 可以直接读截图、找元素、再点击。

三个已经踩过的坑（都在代码里做了防护）：
    1. **KEYCODE_BACK 不能随便按** —— 键盘已经收起时再按一次会直接退出应用。
       所以只在用 uiLayout 确认"窗口高度被压缩 = 键盘弹出了"时才按。
    2. **坐标会漂移** —— 保存按钮实测在 y=1100 到 y=1430 之间移动过。
       所以每次点击前都从截图里现找。
    3. **-fill 是追加不是替换** —— 日期框预填了今天，直接 fill 会拼成
       "2026-09-302026-09-24"。所以先退格清空，再用 uinput -K -t 输入。

用法：
    python3 tools/seed-demo-data.py            # 填充演示数据
    python3 tools/seed-demo-data.py --clean 1  # 先删掉最近记录里最新的 1 条
"""

import argparse
import re
import subprocess
import sys
import time
from datetime import date, timedelta

from PIL import Image

EMU = "/Applications/DevEco-Studio.app/Contents/tools/emulator/Emulator"
HDC = "/Applications/DevEco-Studio.app/Contents/sdk/default/openharmony/toolchains/hdc"
INSTANCE = "carbon"
LAYOUT = f"/Users/{__import__('os').environ.get('USER', 'user')}/.Huawei/Emulator/deployed/{INSTANCE}/uiLayout/analysis.md"
SHOT = "/tmp/_seed.jpeg"

KEY_DEL, KEY_BACK = 2055, 2
GREEN = (31, 154, 78)
SUNKEN = (240, 242, 245)
DANGER = (251, 234, 232)  # Semantic.WARNING_SOFT，删除按钮的底色
FULL_HEIGHT = 1979  # 键盘收起时 Swiper 的高度；小于它说明键盘弹出了


def sh(cmd: str) -> str:
    return subprocess.run(cmd, shell=True, capture_output=True, text=True).stdout


def shot() -> Image.Image:
    sh(f"{HDC} shell snapshot_display -f /data/local/tmp/_s.jpeg")
    sh(f"{HDC} file recv /data/local/tmp/_s.jpeg {SHOT}")
    return Image.open(SHOT).convert("RGB")


def tap(x: int, y: int, wait: float = 0.7) -> None:
    sh(f"{HDC} shell uinput -T -c {x} {y}")
    time.sleep(wait)


def swipe(x1: int, y1: int, x2: int, y2: int, ms: int = 400) -> None:
    sh(f"{HDC} shell uinput -T -m {x1} {y1} {x2} {y2} {ms}")
    time.sleep(0.35)


def scroll_top() -> None:
    for _ in range(6):
        swipe(660, 500, 660, 1800)
    time.sleep(0.4)


def scroll_bottom(tries: int = 3) -> None:
    """滚到底部。滚完自检一次：还找不到「保存」按钮就再滚一轮
    （键盘弹着时滑动会被输入法吃掉，这一层重试是必要的兜底）。"""
    for _ in range(tries):
        for _ in range(6):
            swipe(660, 1700, 660, 500)
        time.sleep(0.4)
        if find_save_y(shot()) is not None:
            return


def key(code: int) -> None:
    sh(f"{HDC} shell uinput -K -d {code} -u {code}")


def backspace(n: int) -> None:
    # 必须逐个发且有间隔：连发 22 次实测只删掉 16 个字符
    for _ in range(n):
        key(KEY_DEL)
        time.sleep(0.11)
    time.sleep(0.3)


def type_text(s: str) -> None:
    sh(f'{HDC} shell uinput -K -t "{s}"')
    time.sleep(0.5)


def ime_height() -> int:
    """从 uiLayout 拿窗口高度：键盘弹出时窗口会被压缩。"""
    sh(f"{EMU} -instance {INSTANCE} -uiLayout")
    try:
        txt = open(LAYOUT, encoding="utf-8").read()
    except OSError:
        return FULL_HEIGHT
    m = re.search(r"Swiper \[top: 0, left: 0, width: \d+, height: (\d+)\]", txt)
    return int(m.group(1)) if m else FULL_HEIGHT


def tab_visible(img: Image.Image) -> bool:
    """页签栏是否露在外面。
    为什么要用这个而不是窗口高度：输入法除了键盘还有**表情包面板**，
    后者是浮层、不会压缩窗口高度（实测 Swiper 仍是 1979），
    但照样把页签栏盖住、把滑动全部吃掉。看页签栏才是可靠判据。
    """
    for x in range(96, 180, 8):
        for y in (2060, 2075, 2090):
            r, g, b = img.getpixel((x, y))
            if g > 120 and g - r > 40 and g - b > 30:
                return True
    return False


def hide_ime() -> bool:
    """只在确认"底部被盖住"时才按 back —— 否则会把应用顶到桌面（实测踩过）。"""
    for _ in range(4):
        if tab_visible(shot()):
            return True
        key(KEY_BACK)
        time.sleep(1.1)
    return tab_visible(shot())


def runs_of(img: Image.Image, color, tol: int, y0: int, y1: int,
            x0: int = 110, x1: int = 1150, step: int = 18, frac: float = 0.7):
    """找出"整行都是某个颜色"的连续行段 —— 用来定位输入框和主按钮。"""
    need = int((x1 - x0) / step * frac)
    hits = []
    for y in range(y0, y1):
        c = 0
        for x in range(x0, x1, step):
            p = img.getpixel((x, y))
            if abs(p[0] - color[0]) <= tol and abs(p[1] - color[1]) <= tol and abs(p[2] - color[2]) <= tol:
                c += 1
        hits.append(c >= need)
    out, start = [], None
    for i, h in enumerate(hits):
        if h and start is None:
            start = i
        elif not h and start is not None:
            out.append((y0 + start, y0 + i - 1))
            start = None
    if start is not None:
        out.append((y0 + start, y0 + len(hits) - 1))
    return [r for r in out if r[1] - r[0] >= 40]


def find_save_y(img: Image.Image):
    """定位「保存」按钮。
    ⚠️ 必须从 y≥850 往下找、并且取**最后一个**绿色带：
       「拍照 / 选图识别」也是一条全宽绿色按钮（y≈482），
       取第一个会把它当成保存按钮，把整条记录填错位置。
    """
    rs = runs_of(img, GREEN, 70, 850, 1900, frac=0.75)
    return (rs[-1][0] + rs[-1][1]) // 2 if rs else None


def find_inputs(img: Image.Image, save_y: int):
    """定位两个输入框。
    ⚠️ 只在 x∈[620,1000] 这一段采样：输入框左侧有「数量」占位符或已填的日期文字，
       深色字形会把整行判定拉低（实测日期框因此被从中间断开成两段）。
       右半边永远没有字，是稳定的判据。
    """
    rs = runs_of(img, SUNKEN, 6, 200, max(300, save_y - 40),
                 x0=620, x1=1000, step=10, frac=0.85)
    return [((a + b) // 2, b - a) for a, b in rs if b - a >= 80]


def bring_form_into_view(tries: int = 7):
    """把「数量 / 日期 / 保存」整块挪进视野。
    ⚠️ 不能只滚到最底：记录变多之后页面变长，滚到底时**数量输入框会被顶出屏幕**，
       只剩日期框可见（实测"输入框=1"）。所以滚到底之后再往回收一点，
       直到两个输入框都出现为止。
    """
    for _ in range(tries):
        img = shot()
        save_y = find_save_y(img)
        ins = find_inputs(img, save_y) if save_y else []
        if save_y is not None and len(ins) >= 2:
            return img, save_y, ins
        swipe(660, 700, 660, 1150)      # 往回滚一点
        time.sleep(0.4)
    return None, None, None


def cat_xy(cat: str):
    return {
        "travel": (365, 1338), "energy": (954, 1338),
        "recycle": (365, 1614), "food": (954, 1614),
    }[cat]


def ensure_foreground() -> None:
    sh(f"{EMU} -instance {INSTANCE} -uiLayout")
    try:
        txt = open(LAYOUT, encoding="utf-8").read()
    except OSError:
        txt = ""
    if "记一笔" not in txt:
        print("     （应用不在前台，重新拉起）")
        sh(f"{HDC} shell aa start -a EntryAbility -b com.henan.carbonfootprint")
        time.sleep(6)


def delete_first_record() -> bool:
    """删掉「最近记录」里的第一条（用于清掉手工调试时留下的异常数据）。"""
    scroll_bottom()
    img = shot()
    rs = runs_of(img, DANGER, 14, 200, 1900, x0=1080, x1=1200, step=10, frac=0.8)
    if not rs:
        return False
    y = (rs[0][0] + rs[0][1]) // 2
    tap(1130, y, 1.5)
    return True


def seed_one(cat: str, amount: str, ds: str) -> bool:
    ensure_foreground()
    # 上一条结束时键盘可能还弹着 —— 键盘弹着时滑动会被键盘吃掉，
    # scroll_top / scroll_bottom 全部失效。所以先确认键盘收起再开始。
    hide_ime()
    scroll_top()
    tap(*cat_xy(cat))
    tap(186, 2031)          # 各列目的第一个行为
    scroll_bottom()

    _, save_y, ins = bring_form_into_view()
    if save_y is None:
        print("     ⚠️ 找不到表单，跳过")
        return False

    # ⚠️ 必须用 ins[-2] / ins[-1]（离保存按钮最近的两个），不能按 y 从小到大取前两个。
    #    踩过的坑：记录变多后「数量」框会被顶出屏幕，此时扫描到的第 1 个输入框其实是
    #    「日期」框 —— 结果把日期 "2026-09-30" 填进了数量框（数字框会自动去掉横杠，
    #    变成 20260930），一条记录直接算成 2000 万度电、累计减排 6370 万 kg。
    #    从下往上数才是稳定的：紧挨保存按钮的一定是日期框，再往上是数量框。
    amount_y = ins[-2][0]
    date_y = ins[-1][0]

    # 数量
    tap(580, amount_y)
    backspace(8)
    type_text(amount)
    # 刚 type_text 过，键盘必然弹着 —— 这是安全的按 back 时机。
    # 不收键盘的话，下面重新定位时会因为屏幕被输入法占掉一半而找不齐两个输入框。
    hide_ime()

    # 日期：重新定位一次，因为「本次减排 X kg」出现后整块会往下挪
    _, save_y, ins = bring_form_into_view()
    if save_y is None:
        print("     ⚠️ 输入日期前定位失败，跳过")
        return False
    tap(580, date_y)
    backspace(14)
    type_text(ds)

    # 保存前先把键盘收掉。
    # ⚠️ 这里是**唯一安全**的按 back 时机：刚刚 type_text 过，键盘必然是弹着的；
    #    不收的话「保存」按钮会被输入法盖住，find_save_y 找不到（实测踩过）。
    hide_ime()

    _, save_y, _ = bring_form_into_view()
    if save_y is None:
        print("     ⚠️ 找不到保存按钮，跳过")
        return False
    tap(660, save_y, 1.8)
    hide_ime()              # 为下一条做准备（这里底部确实被盖住，按 back 是安全的）
    return True


RECORDS = [
    # (类目, 数量, N 天前)
    ("energy", "6", 17),
    ("recycle", "4", 15),
    ("food", "3", 12),
    ("travel", "15", 9),
    ("energy", "9", 6),
    ("travel", "5", 3),
]


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--clean", type=int, default=0,
                    help="先删掉最近记录里最新的 N 条（清掉调试残留）")
    a = ap.parse_args()

    for i in range(a.clean):
        ok = delete_first_record()
        print(f"清理第 {i + 1} 条：{'成功' if ok else '没找到删除按钮'}")

    print(f"开始填充演示数据（共 {len(RECORDS)} 条）…")
    ok = 0
    for cat, amount, back in RECORDS:
        ds = (date.today() - timedelta(days=back)).isoformat()
        print(f"  → {cat:8s} {amount:>3s}  {ds}")
        if seed_one(cat, amount, ds):
            ok += 1
    print(f"完成：成功录入 {ok} / {len(RECORDS)} 条")
    sys.exit(0 if ok == len(RECORDS) else 1)


if __name__ == "__main__":
    main()
