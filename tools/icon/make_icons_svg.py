#!/usr/bin/env python3
"""生成「碳迹」的图标集（SVG）。

设计约定：
  · viewBox 统一 0 0 24 24
  · **填充式**（fill）而不是描边式 —— 因为 ArkUI 的 Image.fillColor 只能给 fill 上色，
    描边图标没法通过它统一换色。填充图标配 fillColor 可以一套图标走遍所有配色。
  · 默认 fill="#000000"，运行时用 fillColor 覆盖成主题色
  · 所有转角/端点是圆的：能用 rx 就用 rx，斜放的形状用二次曲线倒圆或圆头端点，
    不出现尖角矩形
  · 不用 <style>/<text>/<tspan>（ArkUI 的 SVG 渲染器不支持），
    不用 transform 的 rotate/scale（API 12 只支持 translate）——
    需要旋转的形状（铅笔、叶脉）全部在 Python 里把坐标算出来

用法：python3 tools/icon/make_icons_svg.py
输出：project/carbon-footprint/entry/src/main/resources/base/media/*.svg
自检：python3 tools/icon/check_icons.py（渲染量边距 + 墨迹覆盖率 + 约定项）
"""
import math
import os
import sys

# 同目录的自研光栅器：只用于「生成后自检」，不参与生成
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import svg_raster as raster  # noqa: E402

OUT_DIR = ("project/carbon-footprint/entry/src/main/resources/base/media")

# 内容离画布边缘的最小距离（用户坐标）：0.19 ≈ 256px 渲染下的 2px
EDGE_MIN = 0.19


# ---------------------------------------------------------------------------
# 基础构件：坐标一律由代码算出来，避免手写数字对不齐
# ---------------------------------------------------------------------------

def _f(v):
    """数字格式化：去掉多余的零，缩小 SVG 体积（ArkUI 解析路径也更快）。"""
    s = f"{v:.2f}".rstrip("0").rstrip(".")
    return "0" if s in ("-0", "") else s


def _poly_d(pts, close=True):
    d = "M" + " L".join(f"{_f(x)} {_f(y)}" for x, y in pts)
    return d + ("Z" if close else "")


def _rrect_rot(cx, cy, w, h, r, deg=0.0):
    """绕中心旋转 deg 度的圆角矩形（单条子路径）。

    ⚠️ 不能写 transform="rotate"：API 12 的 ArkUI SVG 只支持 translate。
    所以旋转在 Python 里算进坐标 —— 二次曲线是仿射不变的，映射端点与控制点即可。
    """
    a = math.radians(deg)
    ca, sa = math.cos(a), math.sin(a)
    r = min(r, w / 2.0, h / 2.0)
    hw, hh = w / 2.0, h / 2.0

    def T(pt):
        return (cx + pt[0] * ca - pt[1] * sa, cy + pt[0] * sa + pt[1] * ca)

    segs = [("M", T((-hw + r, -hh))), ("L", T((hw - r, -hh))),
            ("Q", T((hw, -hh)), T((hw, -hh + r))), ("L", T((hw, hh - r))),
            ("Q", T((hw, hh)), T((hw - r, hh))), ("L", T((-hw + r, hh))),
            ("Q", T((-hw, hh)), T((-hw, hh - r))), ("L", T((-hw, -hh + r))),
            ("Q", T((-hw, -hh)), T((-hw + r, -hh)))]
    d = ""
    for s in segs:
        if s[0] == "M":
            d += f"M{_f(s[1][0])} {_f(s[1][1])}"
        elif s[0] == "L":
            d += f"L{_f(s[1][0])} {_f(s[1][1])}"
        else:
            d += f"Q{_f(s[1][0])} {_f(s[1][1])} {_f(s[2][0])} {_f(s[2][1])}"
    return d + "Z"


def _round_poly(pts, radii):
    """多边形，每个顶点按给定半径倒圆（二次曲线过顶点，单条子路径）。

    用途：铅笔这类「不规则但要有统一圆角」的形状。
    """
    n = len(pts)
    seq = []
    for i in range(n):
        px, py = pts[(i - 1) % n]
        cx, cy = pts[i]
        nx, ny = pts[(i + 1) % n]
        r = radii[i] if isinstance(radii, (list, tuple)) else radii
        v1x, v1y = cx - px, cy - py
        l1 = math.hypot(v1x, v1y)
        v2x, v2y = nx - cx, ny - cy
        l2 = math.hypot(v2x, v2y)
        seq.append(((cx - v1x / l1 * r, cy - v1y / l1 * r), (cx, cy),
                    (cx + v2x / l2 * r, cy + v2y / l2 * r)))
    d = f"M{_f(seq[0][0][0])} {_f(seq[0][0][1])}"
    for i in range(n):
        _i, c, o = seq[i]
        d += f"Q{_f(c[0])} {_f(c[1])} {_f(o[0])} {_f(o[1])}"
        if i < n - 1:
            nx = seq[i + 1][0]
            d += f"L{_f(nx[0])} {_f(nx[1])}"
    return d + "Z"


def _bar(x1, y1, x2, y2, w):
    """把一条线段变成有宽度的四边形（用于画筷子、飘带这类斜条）。"""
    dx, dy = x2 - x1, y2 - y1
    L = math.hypot(dx, dy)
    nx, ny = -dy / L * w / 2.0, dx / L * w / 2.0
    pts = [(x1 + nx, y1 + ny), (x2 + nx, y2 + ny),
           (x2 - nx, y2 - ny), (x1 - nx, y1 - ny)]
    return _poly_d(pts)


def _dot(cx, cy, r):
    return (f"M{_f(cx - r)} {_f(cy)}a{_f(r)} {_f(r)} 0 0 1 {_f(2 * r)} 0"
            f"a{_f(r)} {_f(r)} 0 0 1 {_f(-2 * r)} 0Z")


def _band(pts, w):
    """折线带：每段一个四边形 + 每个顶点一个圆 —— 圆头端点、圆角转折。

    为什么不用 stroke：ArkUI 的 fillColor 只给 fill 上色，描边线换不了色。
    所有子路径同向（顺时针），nonzero 填充即并集，不会互相挖空。
    """
    subs = [_bar(pts[i][0], pts[i][1], pts[i + 1][0], pts[i + 1][1], w)
            for i in range(len(pts) - 1)]
    subs += [_dot(px, py, w / 2.0) for px, py in pts]
    return subs


def _ring(cx, cy, r_out, r_in):
    """圆环：外圆 + 内圆，靠 evenodd 挖空。"""
    def circ(r):
        return (f"M{_f(cx - r)} {_f(cy)}a{_f(r)} {_f(r)} 0 1 0 {_f(2 * r)} 0"
                f"a{_f(r)} {_f(r)} 0 1 0 {_f(-2 * r)} 0Z")
    return circ(r_out) + circ(r_in)


def _leaf(cx, cy, length, width, deg=-45.0):
    """叶片：两段二次曲线围成的梭形（单条子路径）。deg=-45 → 叶尖指向右上。"""
    a = math.radians(deg)
    ux, uy = math.cos(a), math.sin(a)
    vx, vy = -uy, ux
    hx, hy = ux * length / 2.0, uy * length / 2.0
    return (f"M{_f(cx - hx)} {_f(cy - hy)}"
            f"Q{_f(cx + vx * width)} {_f(cy + vy * width)} "
            f"{_f(cx + hx)} {_f(cy + hy)}"
            f"Q{_f(cx - vx * width)} {_f(cy - vy * width)} "
            f"{_f(cx - hx)} {_f(cy - hy)}Z")


def _book_page(xo, xi, yot, yit, yob, yib, r_out=1.0, r_in=0.5):
    """打开的书：单页轮廓（外缘 xo / 书脊侧 xi；顶边外侧 yot、书脊侧 yit；底边同理）。

    顶边从外缘向书脊「下扇」、底边从书脊向外缘「上扇」，书页才有向两侧铺开的样子。
    外上/外下两个直角用二次曲线倒圆，书脊侧两个小角也倒圆 —— 全图没有尖角。
    """
    def top(x0, y0):
        c1 = (x0 + 0.34 * (xi - x0), y0 + 0.07 * (yit - y0))
        c2 = (x0 + 0.80 * (xi - x0), y0 + 0.45 * (yit - y0))
        return (f"C{_f(c1[0])} {_f(c1[1])} {_f(c2[0])} {_f(c2[1])} "
                f"{_f(xi)} {_f(yit)}")

    def bot(x0, y0):
        c1 = (x0 - 0.34 * (x0 - xo), y0 - 0.07 * (y0 - yob))
        c2 = (x0 - 0.80 * (x0 - xo), y0 - 0.45 * (y0 - yob))
        return (f"C{_f(c1[0])} {_f(c1[1])} {_f(c2[0])} {_f(c2[1])} "
                f"{_f(xo)} {_f(yob)}")

    d = f"M{_f(xo)} {_f(yot + r_out * 1.25)}"
    d += (f"Q{_f(xo)} {_f(yot)} "
          f"{_f(xo + r_out * 0.9)} {_f(yot + 0.16 * (yit - yot))}")
    d += top(xo + r_out * 0.9, yot + 0.16 * (yit - yot))
    d += f"Q{_f(xi + r_in * 0.7)} {_f(yit)} {_f(xi)} {_f(yit + r_in * 1.4)}"
    d += f"L{_f(xi)} {_f(yib - r_in * 1.4)}"
    d += (f"Q{_f(xi)} {_f(yib)} "
          f"{_f(xi - r_in * 0.9)} {_f(yib - 0.10 * (yib - yob))}")
    d += bot(xi - r_in * 0.9, yib - 0.10 * (yib - yob))
    d += f"Q{_f(xo)} {_f(yob)} {_f(xo)} {_f(yob - r_out * 1.25)}"
    return d + "Z"


def _mirror_x(d, axis=12.0):
    """把路径按 x = axis 镜像（只处理 M/L/H/V/C/S/Q/T；遇到圆弧 A 直接报错）。

    用途：打开的书左右两页完全对称 —— 与其手抄一遍坐标（容易抄歪），
    不如把左页镜像过来。
    """
    import re
    toks = re.findall(r"([MLHVCSQTSZmlhvcsqtsz])|(-?\d*\.?\d+)", d)
    out, nums, cmd = [], [], None

    def flush(c, ns):
        if c is None or not ns:
            return c or ""
        up, rel = c.upper(), c.islower()
        if rel or up in "ZT":
            return c + " " + " ".join(ns)
        if up == "H":
            return "H" + _f(2 * axis - float(ns[0]))
        if up == "V":
            return "V" + ns[0]
        step = {"M": 2, "L": 2, "C": 6, "S": 4, "Q": 4}[up]
        res = up
        for i in range(0, len(ns), step):
            grp = [float(v) for v in ns[i:i + step]]
            for j in range(0, len(grp), 2):
                grp[j] = 2 * axis - grp[j]
            res += " " + " ".join(_f(v) for v in grp)
        return res

    for c, n in toks:
        if c:
            if c.upper() == "A":
                raise ValueError("_mirror_x 不支持圆弧 A")
            out.append(flush(cmd, nums))
            cmd, nums = c, []
        else:
            nums.append(n)
    out.append(flush(cmd, nums))
    return "".join(x for x in out if x)


def _fit_path(d, s, dx, dy):
    """把路径做「等比缩放 + 平移」，并把结果**写回坐标**（不留 transform 属性）。

    绝对命令：坐标 = 坐标 × s + 平移；相对命令：增量只乘 s（平移量不会被累加）。
    """
    import re
    toks = re.findall(r"([MLHVCSQTSZmlhvcsqtsz])|(-?\d*\.?\d+)", d)
    out, nums, cmd = [], [], None

    def flush(c, ns):
        if c is None or not ns:
            return c or ""
        up, rel = c.upper(), c.islower()
        if up == "Z":
            return "Z"
        if rel:
            return c + " " + " ".join(_f(float(v) * s) for v in ns)
        if up == "H":
            return "H" + _f(float(ns[0]) * s + dx)
        if up == "V":
            return "V" + _f(float(ns[0]) * s + dy)
        step = {"M": 2, "L": 2, "C": 6, "S": 4, "Q": 4}[up]
        res = up
        for i in range(0, len(ns), step):
            grp = [float(v) for v in ns[i:i + step]]
            for j in range(0, len(grp), 2):
                grp[j] = grp[j] * s + dx
                grp[j + 1] = grp[j + 1] * s + dy
            res += " " + " ".join(_f(v) for v in grp)
        return res

    for c, n in toks:
        if c:
            if c.upper() == "A":
                raise ValueError("_fit_path 不支持圆弧 A")
            out.append(flush(cmd, nums))
            cmd, nums = c, []
        else:
            nums.append(n)
    out.append(flush(cmd, nums))
    return "".join(x for x in out if x)


def _recycle_body(cx=12.0, cy=12.0, r=6.1, thick=2.5, sweep=76.0, gap=44.0):
    """生成三个首尾相接的循环箭头，组成经典回收三角。

    用代码算而不是手写坐标：这样箭头严格等分、首尾对齐，不会看起来「散」。
    """
    out = []
    for k in range(3):
        a0 = math.radians(-90.0 + k * 120.0 + gap / 2.0)
        a1 = math.radians(-90.0 + k * 120.0 + sweep + gap / 2.0)

        def pt(a, rad):
            return (cx + rad * math.cos(a), cy + rad * math.sin(a))

        outer, inner = [], []
        steps = 14
        for i in range(steps + 1):
            a = a0 + (a1 - a0) * i / steps
            outer.append(pt(a, r + thick / 2.0))
            inner.append(pt(a, r - thick / 2.0))

        # 箭头头部：在 a1 处沿切线向外张开的三角
        head_len = thick * 1.75
        head_w = thick * 1.45
        tip = pt(a1, r)
        tanx, tany = -math.sin(a1), math.cos(a1)
        nx, ny = math.cos(a1), math.sin(a1)
        p1 = (tip[0] + tanx * head_len, tip[1] + tany * head_len)
        p2 = (p1[0] + nx * head_w, p1[1] + ny * head_w)
        p3 = (p1[0] - nx * head_w, p1[1] - ny * head_w)

        ring = outer + [p2, p3] + inner[::-1]
        d = "M" + " L".join(f"{x:.2f} {y:.2f}" for x, y in ring) + " Z"
        out.append(f'  <path d="{d}"/>')
    return "\n".join(out)


def _bowl_and_chopsticks():
    """饭碗 + 斜放的筷子。筷子止于碗沿上方，不压住碗身。"""
    bowl_rim = ('  <path d="M3.0 9.0h18.0a1.15 1.15 0 0 1 0 2.3H3.0a1.15 1.15 0 0 1 '
                '0-2.3z"/>')
    bowl = ('  <path d="M4.6 12.4h14.8c0 4.09-3.31 7.4-7.4 7.4s-7.4-3.31-7.4-7.4z"/>')
    # 两根平行筷子，从左下到右上，下端停在碗沿上方
    c1 = "  <path d=\"" + _bar(9.6, 8.6, 16.4, 2.2, 1.5) + "\"/>"
    c2 = "  <path d=\"" + _bar(12.0, 8.6, 18.8, 2.2, 1.5) + "\"/>"
    return "\n".join([c1, c2, bowl_rim, bowl])


RECYCLE_BODY = _recycle_body(cx=12.0, cy=12.0, r=6.4, thick=2.0, sweep=72.0, gap=48.0)
FOOD_BODY = _bowl_and_chopsticks()


# ---------------------------------------------------------------------------
# 五个页签图标（本次重绘）
#
# 统一的设计语言：
#   · 实心面积占比都控制在 24.3%–24.7%（用 check_icons.py 量，极差 0.4 个百分点），
#     一排页签里不会出现「一个特别重、一个特别轻」
#   · 内容都落在 2..22 安全框内，四周留白一致
#   · 圆角语言一致：圆角矩形 + 二次曲线倒圆 + 圆头端点，没有尖角
# ---------------------------------------------------------------------------

def ic_tab_add_body():
    """记一笔：一支斜放的铅笔 + 一条书写线（「记下一笔」而不是「新建一个」）。

    旧图标是「实心圆角方框 + 加号」，读起来像工具栏的「新建」按钮，
    完全看不出「记录一笔低碳行为」——加号在用户心里等于「添加」。
    换成铅笔 + 书写线后，语义直接对上「记一笔」。
    """
    ux, uy = math.cos(math.radians(-45)), math.sin(math.radians(-45))
    vx, vy = -uy, ux
    tip = (5.7, 18.0)                   # 笔尖
    head = (19.3, 4.4)                  # 笔头中心
    half = 3.3                          # 笔杆半宽
    shoulder = (tip[0] + ux * 6.0, tip[1] + uy * 6.0)
    pts = [tip,
           (shoulder[0] + vx * half, shoulder[1] + vy * half),
           (head[0] + vx * half, head[1] + vy * half),
           (head[0] - vx * half, head[1] - vy * half),
           (shoulder[0] - vx * half, shoulder[1] - vy * half)]
    pencil = _round_poly(pts, [0.45, 0.35, 1.0, 1.0, 0.35])
    line = _rrect_rot(10.3, 20.6, 13.8, 2.6, 1.3, 0.0)
    return f'  <path d="{pencil}"/>\n  <path d="{line}"/>'


def ic_tab_medal_body():
    """积分：碳币（圆环）+ 叶片 + 叶脉。

    旧图标是「圆圈套五角星」，那是「收藏」的通用符号，跟积分没有关系。
    现在把「币」和「碳」叠在一起：圆环=硬币/积分，叶=低碳，
    叶脉是一条镂空细线，让叶片在小尺寸下也认得出是叶子而不是水滴。
    """
    coin = _ring(12, 12, 9.85, 8.15)
    lf = _leaf(12, 12, 11.8, 6.8, -45.0)
    vein = _rrect_rot(12, 12, 8.0, 1.0, 0.5, -45.0)
    return (f'  <path fill-rule="evenodd" d="{coin}"/>\n'
            f'  <path fill-rule="evenodd" d="{lf}{vein}"/>')


def ic_tab_chart_body():
    """看板：三根圆角柱 + 一条上升的折线（末端一个数据点）。

    旧图标只有三根柱子（静态的「有多少」）。加上折线后同时表达「趋势」，
    这才是看板要传达的信息；折线末端收在一个圆点上，视觉有落点。
    """
    out = []
    for cx, y0 in ((5.1, 15.2), (12.0, 12.6), (18.9, 10.0)):
        out.append(f'  <path d="{_rrect_rot(cx, (y0 + 21.0) / 2, 4.2, 21.0 - y0, 2.0, 0.0)}"/>')
    for sub in _band([(3.5, 13.0), (10.6, 10.0), (17.4, 6.6)], 2.4):
        out.append(f'  <path d="{sub}"/>')
    out.append(f'  <path d="{_dot(17.4, 6.6, 1.7)}"/>')
    return "\n".join(out)


def ic_tab_book_body():
    """科普：打开的书（两页 + 书脊缝），页内留白，所有转角倒圆。

    保留「书」这个通用符号，但把轮廓重画了一遍：书脊缝笔直居中、
    书页向两侧微微扇开、描边宽度处处一致（旧版书脊侧比外缘细一截，看着发虚）。
    """
    t = 1.75                            # 书页描边宽度
    out = []
    for mirror in (False, True):
        outer = _book_page(2.4, 11.3, 3.8, 5.9, 18.1, 20.2, 1.05, 0.5)
        hole = _book_page(2.4 + t, 11.3 - t, 3.8 + 1.05 * t, 5.9 + 1.05 * t,
                          18.1 - 1.05 * t, 20.2 - 1.05 * t, 1.8, 0.45)
        d = outer + hole
        out.append(f'  <path fill-rule="evenodd" d="{_mirror_x(d) if mirror else d}"/>')
    return "\n".join(out)


def ic_tab_person_body():
    """我的：圆头 + 圆肩（肩线向下微微外扩），头和肩之间留一道缝。

    形状沿用旧版，只是把肩部改成上窄下宽的梯形并用二次曲线收圆，
    重心更稳，也和另外四个图标的「圆角 + 实心块面」语言一致。
    """
    head = _dot(12, 7.35, 4.35)
    body = _round_poly([(3.5, 21.3), (4.1, 19.3), (12, 12.5), (19.9, 19.3),
                        (20.5, 21.3)], [2.2, 1.5, 4.9, 1.5, 2.2])
    return f'  <path d="{head}"/>\n  <path d="{body}"/>'


# 备份图标：原图内容一直顶到 x=23.9（右边只剩 0.1 单位，QuickLook 缩略图里能明显
# 看到云朵贴着画布边缘）。这里按内容包围盒等比缩到 2.2..21.8 并居中 ——
# 图形本身（云 + 下箭头）没动，只是把它摆回安全区。
_BACKUP_BODY_RAW = """
  <path d="M12 2.6c-3.6 0-6.5 2.9-6.5 6.5 0 .2 0 .5.1.7-1.9.6-3.2 2.4-3.2 4.5 0 2.6 2.1 4.7 4.7 4.7h1.4c.6 0 1.1-.5 1.1-1.1s-.5-1.1-1.1-1.1H7.1c-1.4 0-2.5-1.1-2.5-2.5s1.1-2.5 2.5-2.5c.3 0 .6.1.8.1.5.2 1.1-.1 1.2-.6.1-.3.2-.7.2-1 0-2.4 1.9-4.3 4.3-4.3s4.3 1.9 4.3 4.3c0 .3-.1.6-.1.9-.1.5.2 1.1.7 1.2.2.1.5.1.7.1 1.4 0 2.5 1.1 2.5 2.5s-1.1 2.5-2.5 2.5h-1.4c-.6 0-1.1.5-1.1 1.1s.5 1.1 1.1 1.1h1.4c2.6 0 4.7-2.1 4.7-4.7 0-2.1-1.3-3.9-3.2-4.5.1-.2.1-.5.1-.7 0-3.6-2.9-6.5-6.5-6.5z"/>
  <path d="M12 11.4c-.6 0-1.1.5-1.1 1.1v4.1l-1.3-1.3c-.4-.4-1.1-.4-1.5 0s-.4 1.1 0 1.5l3.1 3.1c.4.4 1.1.4 1.5 0l3.1-3.1c.4-.4.4-1.1 0-1.5s-1.1-.4-1.5 0l-1.3 1.3v-4.1c0-.6-.4-1.1-1-1.1z"/>
"""
# 变换量由「原内容包围盒 x 2.40..23.90 / y 2.60..20.19」推出（check_icons 可复核）：
#   s = 19.6 / 21.5，再把包围盒中心 (13.15, 11.40) 移到 (12, 12)
_BACKUP_S = 19.6 / 21.5
_BACKUP_DX = 12.0 - _BACKUP_S * 13.15
_BACKUP_DY = 12.0 - _BACKUP_S * 11.40


def _backup_body():
    import re
    out = []
    for d in re.findall(r'<path d="([^"]+)"/>', _BACKUP_BODY_RAW):
        out.append(f'  <path d="{_fit_path(d, _BACKUP_S, _BACKUP_DX, _BACKUP_DY)}"/>')
    return "\n".join(out)


BACKUP_BODY = _backup_body()

# ---------------------------------------------------------------------------
# 权益/兑换用到的三个图标（积分页「可兑换权益」列表）
#
# 背景：地铁乘车券与共享单车券原来只能共用 ic_travel（走路小人），两张行卡的图标
# 一模一样，用户分不出哪个是哪个。这里补齐三个语义独立的图标。
# ---------------------------------------------------------------------------

def ic_metro_body():
    """地铁/轨道交通：圆角车厢 + 前窗（挖空）+ 车门缝（挖空）+ 两个车轮 + 顶部受电弓。

    为什么不是「走路小人」：地铁券要一眼看出是**轨道交通**——
    车厢轮廓负责「车」，顶部受电弓 + 底部两个车轮负责「轨道」。
    """
    body_h = 11.0
    out = []
    body = _rrect_rot(12.0, 4.6 + body_h / 2.0, 15.2, body_h, 2.4, 0.0)
    win = _rrect_rot(12.0, 7.5, 11.2, 3.7, 1.1, 0.0)
    door = _rrect_rot(12.0, 13.0, 2.5, 4.4, 1.25, 0.0)
    out.append(f'  <path fill-rule="evenodd" d="{body}{win}{door}"/>')
    out.append(f'  <path d="{_dot(7.8, 18.6, 1.65)}"/>')
    out.append(f'  <path d="{_dot(16.2, 18.6, 1.65)}"/>')
    out.append(f'  <path d="{_rrect_rot(12.0, 2.9, 7.4, 1.4, 0.7, 0.0)}"/>')   # 受电弓横杆
    out.append(f'  <path d="{_rrect_rot(12.0, 3.9, 1.4, 1.6, 0.7, 0.0)}"/>')   # 竖杆
    return "\n".join(out)


def ic_bike_body():
    """共享单车：两个圆环轮 + 三角车架 + 车座 + 车把 + 曲柄。

    与 ic_recycle 的区别：回收图标是三个绕圈的箭头（有箭头尖、径向对称），
    这里是两个**闭合圆环**加直杆车架，轮子之间没有旋转关系，不会混。
    """
    wl, wr = (6.0, 15.9), (18.0, 15.9)      # 后轮 / 前轮圆心
    r, t = 3.85, 1.2                        # 轮半径 / 轮圈粗细
    bb, seat, hbar = (11.3, 15.9), (9.5, 10.8), (16.4, 10.5)
    fw = 2.4                                # 车架粗细
    out = []
    wheels = _ring(wl[0], wl[1], r, r - t) + _ring(wr[0], wr[1], r, r - t)
    out.append(f'  <path fill-rule="evenodd" d="{wheels}"/>')
    frame = (_band([wl, seat], fw) + _band([seat, bb], fw) + _band([bb, wr], fw)
             + _band([seat, hbar], fw) + _band([hbar, wr], fw))
    out += [f'  <path d="{s}"/>' for s in frame]
    out.append(f'  <path d="{_dot(bb[0], bb[1], 1.5)}"/>')                     # 曲柄
    out.append(f'  <path d="{_rrect_rot(9.3, 10.0, 3.6, 1.5, 0.75, 0.0)}"/>')  # 车座
    out.append(f'  <path d="{_rrect_rot(16.6, 10.2, 3.4, 1.5, 0.75, 8.0)}"/>')  # 车把
    return "\n".join(out)


def ic_gift_body():
    """权益兑换（礼物）：盒盖 + 盒身 + 竖丝带（挖空）+ 蝴蝶结（两个椭圆环 + 结）。

    丝带做成**镂空**而不是叠一条同色带子 —— 同色叠上去看不见，只有挖空才读得出来。
    蝴蝶结用两个旋转的椭圆环：实心块会变成两个「耳朵」，中空的环才是绸带圈。
    """
    lid = _rrect_rot(12.0, 9.7, 15.6, 3.0, 1.2, 0.0)        # 盒盖 4.2..19.8 / 8.2..11.2
    body = _rrect_rot(12.0, 15.4, 14.0, 8.4, 1.4, 0.0)      # 盒身 5.0..19.0 / 11.2..19.6
    ribbon = _rrect_rot(12.0, 14.1, 3.6, 11.4, 1.8, 0.0)    # 丝带（镂空，8.4..19.8）
    out = [f'  <path fill-rule="evenodd" d="{lid}{body}{ribbon}"/>']
    loops = ""
    for cx, deg in ((9.5, -150.0), (14.5, -30.0)):
        loops += _rrect_rot(cx, 6.25, 5.0, 3.0, 1.5, deg)
        loops += _rrect_rot(cx, 6.25, 2.6, 1.3, 0.65, deg)
    out.append(f'  <path fill-rule="evenodd" d="{loops}"/>')
    out.append(f'  <path d="{_dot(12.0, 7.75, 1.3)}"/>')                        # 结
    return "\n".join(out)


# name -> (title, svg 内容片段)
ICONS = {
    # ---------------- 四个行为类目 ----------------
    "ic_travel": ("出行（步行）", """
  <circle cx="13" cy="4" r="2.1"/>
  <path d="M12.2 6.6c-.5-.2-1.1 0-1.4.5L8.4 11c-.3.5-.1 1.1.4 1.4.5.3 1.1.1 1.4-.4l1-1.7.9 2.6-2.5 3.2c-.3.4-.3.9 0 1.3l2.2 3.1c.3.5.9.6 1.4.3.5-.3.6-.9.3-1.4l-1.8-2.6 2.6-3.3c.3-.4.3-.9.2-1.3l-.6-1.8 1.9 1.1c.4.3 1 .2 1.3-.2l1.6-2c.3-.4.3-1-.2-1.3-.4-.3-1-.3-1.3.2l-1.1 1.4-3.8-2.2z"/>
"""),
    "ic_energy": ("节水节电（闪电）", """
  <path d="M13.6 2.2c-.5-.3-1.2 0-1.3.6L10.6 10H7.2c-.6 0-1 .6-.8 1.1l4 9.9c.2.5.9.6 1.3.2.2-.2.3-.4.3-.6l.1-6.6h3.4c.6 0 1-.6.8-1.1l-2.2-10.3c-.1-.2-.3-.4-.5-.4z"/>
"""),
    "ic_recycle": ("旧物回收（三角循环箭头）", RECYCLE_BODY),
    "ic_food": ("光盘行动（饭碗与筷子）", FOOD_BODY),

    # ---------------- 五个页签（本次重绘：语义 + 视觉重量 + 圆角语言）----------------
    "ic_tab_add": ("记一笔（铅笔与书写线）", ic_tab_add_body()),
    "ic_tab_chart": ("看板（柱状与上升折线）", ic_tab_chart_body()),
    "ic_tab_medal": ("积分（碳币与叶片）", ic_tab_medal_body()),
    "ic_tab_book": ("科普（打开的书本）", ic_tab_book_body()),
    "ic_tab_person": ("我的（用户）", ic_tab_person_body()),

    # ---------------- 功能图标 ----------------
    # 权益/兑换（积分页「可兑换权益」列表用）
    "ic_metro": ("地铁（轨道交通）", ic_metro_body()),
    "ic_bike": ("共享单车（自行车）", ic_bike_body()),
    "ic_gift": ("权益兑换（礼物）", ic_gift_body()),

    "ic_ai": ("端侧 AI（相机 + 星）", """
  <path d="M9.4 3.6c-.5 0-.9.3-1.1.7l-.8 1.7H4.9c-1.6 0-2.9 1.3-2.9 2.9v8.2c0 1.6 1.3 2.9 2.9 2.9h14.2c1.6 0 2.9-1.3 2.9-2.9V8.9c0-1.6-1.3-2.9-2.9-2.9h-2.6l-.8-1.7c-.2-.4-.6-.7-1.1-.7H9.4zm2.6 5.1c2.6 0 4.7 2.1 4.7 4.7s-2.1 4.7-4.7 4.7-4.7-2.1-4.7-4.7 2.1-4.7 4.7-4.7zm0 2.1c-1.4 0-2.6 1.2-2.6 2.6s1.2 2.6 2.6 2.6 2.6-1.2 2.6-2.6-1.2-2.6-2.6-2.6z"/>
  <path d="M19.4 2.1l.7 1.8 1.8.7-1.8.7-.7 1.8-.7-1.8-1.8-.7 1.8-.7z"/>
"""),
    "ic_sync": ("同步（循环箭头）", """
  <path d="M12 3.4c-3.6 0-6.7 2.2-8 5.4-.2.5 0 1.1.5 1.3.5.2 1.1 0 1.3-.5C6.9 7 9.2 5.5 12 5.5c2.4 0 4.5 1.2 5.8 3.1l-1.7.6c-.5.2-.6.9-.2 1.3l3 2.6c.4.3.9.3 1.2-.1l2.2-3c.3-.4.2-1.1-.4-1.3l-1.6-.6C18.6 5.3 15.5 3.4 12 3.4z"/>
  <path d="M12 20.6c3.6 0 6.7-2.2 8-5.4.2-.5 0-1.1-.5-1.3-.5-.2-1.1 0-1.3.5-1.1 2.6-3.4 4.1-6.2 4.1-2.4 0-4.5-1.2-5.8-3.1l1.7-.6c.5-.2.6-.9.2-1.3l-3-2.6c-.4-.3-.9-.3-1.2.1l-2.2 3c-.3.4-.2 1.1.4 1.3l1.6.6c1.3 2.9 4.4 4.7 8.3 4.7z"/>
"""),
    "ic_backup": ("备份（云端下载）", BACKUP_BODY),
    "ic_export": ("导出报表（文档）", """
  <path d="M6.6 2.4c-1.4 0-2.5 1.1-2.5 2.5v14.2c0 1.4 1.1 2.5 2.5 2.5h10.8c1.4 0 2.5-1.1 2.5-2.5V8.6c0-.3-.1-.6-.3-.8l-5.6-5.2c-.2-.2-.5-.3-.8-.3H6.6zm0 2.1h5.2v3.4c0 1.2 1 2.2 2.2 2.2h3.3v9c0 .2-.2.4-.4.4H6.6c-.2 0-.4-.2-.4-.4V4.9c0-.2.2-.4.4-.4zm7.3.6l2.5 2.3h-2.1c-.2 0-.4-.2-.4-.4V5.1z"/>
  <path d="M8.4 12.6c-.6 0-1.1.5-1.1 1.1s.5 1.1 1.1 1.1h7.2c.6 0 1.1-.5 1.1-1.1s-.5-1.1-1.1-1.1H8.4zm0 3.6c-.6 0-1.1.5-1.1 1.1s.5 1.1 1.1 1.1h4.4c.6 0 1.1-.5 1.1-1.1s-.5-1.1-1.1-1.1H8.4z"/>
"""),
    "ic_trash": ("清空（垃圾桶）", """
  <path d="M9.4 2.4c-.6 0-1.1.3-1.4.8l-.9 1.5H4.2c-.6 0-1.1.5-1.1 1.1s.5 1.1 1.1 1.1h15.6c.6 0 1.1-.5 1.1-1.1s-.5-1.1-1.1-1.1h-2.9l-.9-1.5c-.3-.5-.8-.8-1.4-.8H9.4zm-3.3 6.4c-.6 0-1.1.5-1.1 1.1v8.7c0 1.7 1.4 3.1 3.1 3.1h7.8c1.7 0 3.1-1.4 3.1-3.1v-8.7c0-.6-.5-1.1-1.1-1.1s-1.1.5-1.1 1.1v8.7c0 .5-.4.9-.9.9H8.1c-.5 0-.9-.4-.9-.9v-8.7c0-.6-.5-1.1-1.1-1.1z"/>
"""),
    "ic_share": ("分享", """
  <path d="M18 2.6c-2 0-3.6 1.6-3.6 3.6 0 .3 0 .5.1.8l-5 2.9c-.6-.6-1.5-1-2.4-1-2 0-3.6 1.6-3.6 3.6s1.6 3.6 3.6 3.6c.9 0 1.7-.3 2.3-.9l5.1 2.9c0 .2-.1.4-.1.7 0 2 1.6 3.6 3.6 3.6s3.6-1.6 3.6-3.6-1.6-3.6-3.6-3.6c-.9 0-1.7.3-2.3.9l-5.1-2.9c0-.2.1-.4.1-.7s0-.5-.1-.7l5.1-2.9c.6.6 1.4.9 2.3.9 2 0 3.6-1.6 3.6-3.6s-1.6-3.6-3.6-3.6z"/>
"""),
    "ic_leaf": ("叶子", """
  <path d="M20.4 3.2c-6.6-.9-12 1.4-14.4 5.6-1.6 2.8-1.3 6.2.6 8.7l-2.4 2.4c-.4.4-.4 1.1 0 1.5.4.4 1.1.4 1.5 0l2.4-2.4c2.5 1.9 5.9 2.2 8.7.6 4.2-2.4 6.5-7.8 5.6-14.4-.1-.8-.7-1.3-1.4-1.4-2.6-.4-5 .1-7.1 1.1 1.5-1.1 3.4-1.7 5.5-1.4.3.1.9-.2 1-.3z"/>
"""),
    "ic_tree": ("植树", """
  <path d="M12 2.4c-.3 0-.6.2-.8.4L7.6 7.6c-.4.5 0 1.3.7 1.3h1.5l-2.8 4.2c-.4.5 0 1.3.7 1.3h2.1l-2.4 3.6c-.4.6.1 1.3.7 1.3h4.4v2.1c0 .6.5 1.1 1.1 1.1s1.1-.5 1.1-1.1v-2.1h4.4c.7 0 1.1-.8.7-1.3l-2.4-3.6h2.1c.7 0 1.1-.8.7-1.3l-2.8-4.2h1.5c.7 0 1.1-.8.7-1.3L13.2 2.8c-.3-.3-.7-.4-1.2-.4z"/>
"""),
    "ic_flame": ("连续记录", """
  <path fill-rule="evenodd" d="M12 2.6c-.4 0-.7.2-.9.5C9.6 5.2 6.3 9.4 6.3 13.4a5.7 5.7 0 0 0 11.4 0c0-4-3.3-8.2-4.8-10.3-.2-.3-.5-.5-.9-.5zm0 7.4c.9 1.3 2.4 3.5 2.4 5.3a2.4 2.4 0 0 1-4.8 0c0-1.8 1.5-4 2.4-5.3z"/>
"""),
    "ic_check": ("完成", """
  <path d="M20.7 6.3c.5.5.5 1.3 0 1.8L10.4 18.4c-.5.5-1.3.5-1.8 0l-5.3-5.3c-.5-.5-.5-1.3 0-1.8s1.3-.5 1.8 0l4.4 4.4L18.9 6.3c.5-.5 1.3-.5 1.8 0z"/>
"""),
    "ic_arrow": ("右箭头", """
  <path d="M9.3 4.3c.5-.5 1.3-.5 1.8 0l7 7c.5.5.5 1.3 0 1.8l-7 7c-.5.5-1.3.5-1.8 0s-.5-1.3 0-1.8L15.4 12 9.3 6.1c-.5-.5-.5-1.3 0-1.8z"/>
"""),
    "ic_target": ("目标", """
  <path d="M12 2.4c-5.3 0-9.6 4.3-9.6 9.6s4.3 9.6 9.6 9.6 9.6-4.3 9.6-9.6-4.3-9.6-9.6-9.6zm0 2.2c4.1 0 7.4 3.3 7.4 7.4s-3.3 7.4-7.4 7.4-7.4-3.3-7.4-7.4 3.3-7.4 7.4-7.4z"/>
  <path d="M12 6.8c-2.9 0-5.2 2.3-5.2 5.2s2.3 5.2 5.2 5.2 5.2-2.3 5.2-5.2-2.3-5.2-5.2-5.2zm0 2.2c1.7 0 3 1.3 3 3s-1.3 3-3 3-3-1.3-3-3 1.3-3 3-3z"/>
  <circle cx="12" cy="12" r="1.6"/>
"""),
}

# 刻意不写 width/height：只给 viewBox，让使用方（ArkUI Image）按容器尺寸自由缩放。
# 写了固定宽高会导致某些渲染器按 24px 原样画，出现「图标变得极小」的问题。
TPL = """<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" preserveAspectRatio="xMidYMid meet">
  <title>{title}</title>
  <g fill="#000000">{body}</g>
</svg>
"""


def _bounds_check(svgs):
    """用自研光栅器量真实包围盒。

    旧版这里是正则抓「数字对」，把路径里的相对增量（如 c-.5-.2-1.1 0）当成坐标，
    于是 17 个图标全部误报「超出边界」——假警报比没有检查更糟。
    现在按 SVG 规范解析路径（含三次/二次曲线与圆弧），量出来的是真实范围。
    """
    bad = []
    for name, svg in svgs.items():
        box = raster.bbox(svg)
        if box is None:
            bad.append(f"  ⚠️ {name}: 内容为空")
            continue
        x0, y0, x1, y1 = box
        if x0 < EDGE_MIN or y0 < EDGE_MIN or x1 > 24 - EDGE_MIN or y1 > 24 - EDGE_MIN:
            bad.append(f"  ⚠️ {name}: 内容贴边 x {x0:.2f}..{x1:.2f} y {y0:.2f}..{y1:.2f}")
    return bad


def main() -> None:
    os.makedirs(OUT_DIR, exist_ok=True)
    svgs = {}
    for name, (title, body) in ICONS.items():
        svg = TPL.format(title=title, body=body.strip("\n"))
        svgs[name] = svg
        with open(os.path.join(OUT_DIR, name + ".svg"), "w", encoding="utf-8") as f:
            f.write(svg)
    print(f"已生成 {len(ICONS)} 个图标 → {OUT_DIR}")
    warn = _bounds_check(svgs)
    if warn:
        print("边界检查：")
        for w in warn:
            print(w)
    else:
        print("边界检查：全部图标都在 24×24 画布内 ✅")


if __name__ == "__main__":
    main()
