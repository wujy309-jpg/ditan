#!/usr/bin/env python3
"""极简 SVG 光栅器（纯 Python，零第三方依赖）—— 给图标自检提供「可复现」的渲染结果。

为什么需要它（而不是继续用 qlmanage）：
  check_icons.py 原来用 macOS QuickLook（qlmanage）把 SVG 渲染成 256px 缩略图再量像素。
  实测有两个致命问题：
    1) qlmanage 依赖 QuickLook 服务，在沙箱 / CI / 无 GUI 会话里会直接失败
       （本机报 `sandbox initialization failed: Operation not permitted`，退出码 255）；
    2) 更糟的是**失败时静默**：旧的 PNG 留在 /tmp 里，脚本照读不误
       —— 于是自检结果来自「上一次渲染的图」，与当前文件无关（会报出假警报）。
  自己算慢一点（21 个图标约几秒），但结果只取决于文件内容，且能在任何环境跑。

提供三件事：
  · bbox(svg)              —— 内容的精确包围盒（用户坐标 0..24），用于「是否出框/贴边」
  · coverage(svg)          —— 墨迹覆盖率（= 实心面积占比），用于「视觉重量是否统一」
  · preview_png(...)       —— 灰度预览图，用于人眼复核

支持的 SVG 子集（= 本项目图标集实际用到的）：
  <path d>（M m L l H h V v C c S s Q q T t A a Z z）、<circle>、<ellipse>、
  <rect x y width height rx ry>、<polygon>、<polyline>
  fill-rule="nonzero|evenodd"（默认 nonzero）；fill="none" 的元素跳过。
  不支持：stroke、transform、渐变、CSS、<text> —— 这些本来就在图标约定里被禁掉了
  （ArkUI 的 fillColor 只能给 fill 上色，且 API 12 只支持 translate）。

命令行自检：
  python3 tools/icon/svg_raster.py <file.svg> [--size 192] [--ss 4] [--png out.png]
"""
import math
import re
import struct
import sys
import zlib

# ---------------------------------------------------------------------------
# 1. 路径解析 → 折线
# ---------------------------------------------------------------------------

_NUM = re.compile(r'[-+]?(?:\d*\.\d+|\d+\.?)(?:[eE][-+]?\d+)?')
_CMD = re.compile(r'([MmZzLlHhVvCcSsQqTtAa])')


def _tokenize(d: str):
    """把 d 拆成 [(cmd, [num, ...]), ...]，处理隐式重复（如 c 后面连写多组）。"""
    out = []
    pos = 0
    cur = None
    nums = []
    for m in re.finditer(r'([MmZzLlHhVvCcSsQqTtAa])|([-+]?(?:\d*\.\d+|\d+\.?)(?:[eE][-+]?\d+)?)', d):
        if m.group(1):
            if cur is not None:
                out.append((cur, nums))
            cur = m.group(1)
            nums = []
        else:
            nums.append(float(m.group(2)))
    if cur is not None:
        out.append((cur, nums))
    return out


_ARGC = {'M': 2, 'L': 2, 'H': 1, 'V': 1, 'C': 6, 'S': 4, 'Q': 4, 'T': 2, 'A': 7, 'Z': 0}


def _expand(tokens):
    """把隐式重复展开成每条命令恰好带一组参数。"""
    out = []
    for cmd, nums in tokens:
        up = cmd.upper()
        n = _ARGC[up]
        if n == 0:
            out.append((cmd, []))
            continue
        if len(nums) < n:
            raise ValueError(f'路径命令 {cmd} 参数不足：{nums}')
        i = 0
        first = True
        while i + n <= len(nums):
            c = cmd
            # M 后面跟多组坐标 = 隐式 L（m 则是隐式 l）
            if not first and up == 'M':
                c = 'L' if cmd == 'M' else 'l'
            out.append((c, nums[i:i + n]))
            i += n
            first = False
    return out


def _bez3(p0, p1, p2, p3, n):
    pts = []
    for i in range(1, n + 1):
        t = i / n
        mt = 1.0 - t
        a = mt * mt * mt
        b = 3 * mt * mt * t
        c = 3 * mt * t * t
        e = t * t * t
        pts.append((a * p0[0] + b * p1[0] + c * p2[0] + e * p3[0],
                    a * p0[1] + b * p1[1] + c * p2[1] + e * p3[1]))
    return pts


def _bez2(p0, p1, p2, n):
    pts = []
    for i in range(1, n + 1):
        t = i / n
        mt = 1.0 - t
        a = mt * mt
        b = 2 * mt * t
        c = t * t
        pts.append((a * p0[0] + b * p1[0] + c * p2[0],
                    a * p0[1] + b * p1[1] + c * p2[1]))
    return pts


def _segs_for(p0, ctrl_len):
    """按曲线长度决定采样段数：太粗会在斜边上看到折线，太细纯属浪费。"""
    return max(8, min(64, int(ctrl_len * 3.0) + 8))


def _mid(p, q):
    return ((p[0] + q[0]) / 2.0, (p[1] + q[1]) / 2.0)


def _dist(p, q):
    return math.hypot(q[0] - p[0], q[1] - p[1])


def _arc_to_points(p0, rx, ry, phi_deg, large, sweep, p1, n_hint=64):
    """SVG 椭圆弧（端点参数化）→ 折线。算法按 SVG 1.1 规范 F.6.5。"""
    x1, y1 = p0
    x2, y2 = p1
    if rx == 0 or ry == 0 or (abs(x1 - x2) < 1e-12 and abs(y1 - y2) < 1e-12):
        return [p1]
    rx, ry = abs(rx), abs(ry)
    phi = math.radians(phi_deg)
    cosp, sinp = math.cos(phi), math.sin(phi)
    dx2, dy2 = (x1 - x2) / 2.0, (y1 - y2) / 2.0
    x1p = cosp * dx2 + sinp * dy2
    y1p = -sinp * dx2 + cosp * dy2
    lam = (x1p * x1p) / (rx * rx) + (y1p * y1p) / (ry * ry)
    if lam > 1.0:
        s = math.sqrt(lam)
        rx *= s
        ry *= s
    num = rx * rx * ry * ry - rx * rx * y1p * y1p - ry * ry * x1p * x1p
    den = rx * rx * y1p * y1p + ry * ry * x1p * x1p
    coef = 0.0 if den == 0 else math.sqrt(max(0.0, num / den))
    if large == sweep:
        coef = -coef
    cxp = coef * (rx * y1p / ry)
    cyp = coef * (-ry * x1p / rx)
    cx = cosp * cxp - sinp * cyp + (x1 + x2) / 2.0
    cy = sinp * cxp + cosp * cyp + (y1 + y2) / 2.0

    def ang(ux, uy, vx, vy):
        dot = ux * vx + uy * vy
        nrm = math.hypot(ux, uy) * math.hypot(vx, vy)
        if nrm == 0:
            return 0.0
        a = math.acos(max(-1.0, min(1.0, dot / nrm)))
        return -a if (ux * vy - uy * vx) < 0 else a

    ux, uy = (x1p - cxp) / rx, (y1p - cyp) / ry
    vx, vy = (-x1p - cxp) / rx, (-y1p - cyp) / ry
    theta1 = ang(1.0, 0.0, ux, uy)
    dtheta = ang(ux, uy, vx, vy)
    if not sweep and dtheta > 0:
        dtheta -= 2 * math.pi
    elif sweep and dtheta < 0:
        dtheta += 2 * math.pi

    n = max(8, min(96, int(abs(dtheta) * max(rx, ry) * 2.0) + 6, n_hint))
    pts = []
    for i in range(1, n + 1):
        t = theta1 + dtheta * i / n
        ct, st = math.cos(t), math.sin(t)
        pts.append((cx + rx * ct * cosp - ry * st * sinp,
                    cy + rx * ct * sinp + ry * st * cosp))
    return pts


def flatten_path(d: str):
    """把路径 d 展开成若干子路径的折线：[[(x, y), ...], ...]（绝对坐标）。"""
    subs = []
    cur = []
    x = y = 0.0
    sx = sy = 0.0
    prev_c2 = None   # 上一个三次控制点（S/s 用）
    prev_q = None    # 上一个二次控制点（T/t 用）
    for cmd, a in _expand(_tokenize(d)):
        rel = cmd.islower()
        up = cmd.upper()
        if up == 'M':
            if len(cur) > 1:
                subs.append(cur)
            x = (x + a[0]) if rel else a[0]
            y = (y + a[1]) if rel else a[1]
            sx, sy = x, y
            cur = [(x, y)]
            prev_c2 = prev_q = None
        elif up == 'L':
            x = (x + a[0]) if rel else a[0]
            y = (y + a[1]) if rel else a[1]
            cur.append((x, y))
            prev_c2 = prev_q = None
        elif up == 'H':
            x = (x + a[0]) if rel else a[0]
            cur.append((x, y))
            prev_c2 = prev_q = None
        elif up == 'V':
            y = (y + a[0]) if rel else a[0]
            cur.append((x, y))
            prev_c2 = prev_q = None
        elif up == 'C':
            p1 = (x + a[0], y + a[1]) if rel else (a[0], a[1])
            p2 = (x + a[2], y + a[3]) if rel else (a[2], a[3])
            p3 = (x + a[4], y + a[5]) if rel else (a[4], a[5])
            n = _segs_for((x, y), _dist((x, y), p1) + _dist(p1, p2) + _dist(p2, p3))
            cur.extend(_bez3((x, y), p1, p2, p3, n))
            x, y = p3
            prev_c2, prev_q = p2, None
        elif up == 'S':
            p1 = (2 * x - prev_c2[0], 2 * y - prev_c2[1]) if prev_c2 else (x, y)
            p2 = (x + a[0], y + a[1]) if rel else (a[0], a[1])
            p3 = (x + a[2], y + a[3]) if rel else (a[2], a[3])
            n = _segs_for((x, y), _dist((x, y), p1) + _dist(p1, p2) + _dist(p2, p3))
            cur.extend(_bez3((x, y), p1, p2, p3, n))
            x, y = p3
            prev_c2, prev_q = p2, None
        elif up == 'Q':
            p1 = (x + a[0], y + a[1]) if rel else (a[0], a[1])
            p2 = (x + a[2], y + a[3]) if rel else (a[2], a[3])
            n = _segs_for((x, y), _dist((x, y), p1) + _dist(p1, p2))
            cur.extend(_bez2((x, y), p1, p2, n))
            x, y = p2
            prev_q, prev_c2 = p1, None
        elif up == 'T':
            p1 = (2 * x - prev_q[0], 2 * y - prev_q[1]) if prev_q else (x, y)
            p2 = (x + a[0], y + a[1]) if rel else (a[0], a[1])
            n = _segs_for((x, y), _dist((x, y), p1) + _dist(p1, p2))
            cur.extend(_bez2((x, y), p1, p2, n))
            x, y = p2
            prev_q, prev_c2 = p1, None
        elif up == 'A':
            p1 = (x + a[5], y + a[6]) if rel else (a[5], a[6])
            cur.extend(_arc_to_points((x, y), a[0], a[1], a[2], int(a[3]) != 0, int(a[4]) != 0, p1))
            x, y = p1
            prev_c2 = prev_q = None
        elif up == 'Z':
            if len(cur) > 1:
                subs.append(cur)
            cur = [(sx, sy)]
            x, y = sx, sy
            prev_c2 = prev_q = None
    if len(cur) > 1:
        subs.append(cur)
    return subs


# ---------------------------------------------------------------------------
# 2. 元素抽取（只认已支持的标签）
# ---------------------------------------------------------------------------

_ATTR = re.compile(r'([a-zA-Z-]+)\s*=\s*"([^"]*)"')


def _attrs(tag: str):
    return {k: v for k, v in _ATTR.findall(tag)}


def _rect_path(x, y, w, h, rx, ry):
    if rx <= 0 and ry <= 0:
        return f'M{x} {y}H{x + w}V{y + h}H{x}Z'
    rx = min(rx, w / 2.0)
    ry = min(ry, h / 2.0)
    return (f'M{x + rx} {y}H{x + w - rx}A{rx} {ry} 0 0 1 {x + w} {y + ry}'
            f'V{y + h - ry}A{rx} {ry} 0 0 1 {x + w - rx} {y + h}H{x + rx}'
            f'A{rx} {ry} 0 0 1 {x} {y + h - ry}V{y + ry}A{rx} {ry} 0 0 1 {x + rx} {y}Z')


def _ellipse_path(cx, cy, rx, ry):
    return (f'M{cx - rx} {cy}A{rx} {ry} 0 0 1 {cx + rx} {cy}'
            f'A{rx} {ry} 0 0 1 {cx - rx} {cy}Z')


def shapes(svg: str):
    """抽出所有可填充图形：[(subpaths, evenodd_bool), ...]"""
    out = []
    for m in re.finditer(r'<(path|circle|ellipse|rect|polygon|polyline)\b([^>]*)>', svg, re.S):
        tag, rest = m.group(1), m.group(2)
        at = _attrs(rest)
        if at.get('fill', '').strip().lower() == 'none':
            continue
        rule = at.get('fill-rule', 'nonzero').strip().lower() == 'evenodd'
        d = None
        if tag == 'path':
            d = at.get('d', '')
        elif tag == 'circle':
            cx, cy = float(at.get('cx', 0)), float(at.get('cy', 0))
            d = _ellipse_path(cx, cy, float(at.get('r', 0)), float(at.get('r', 0)))
        elif tag == 'ellipse':
            d = _ellipse_path(float(at.get('cx', 0)), float(at.get('cy', 0)),
                              float(at.get('rx', 0)), float(at.get('ry', 0)))
        elif tag == 'rect':
            rx = float(at.get('rx', at.get('ry', 0)) or 0)
            ry = float(at.get('ry', at.get('rx', 0)) or 0)
            d = _rect_path(float(at.get('x', 0)), float(at.get('y', 0)),
                           float(at.get('width', 0)), float(at.get('height', 0)), rx, ry)
        else:  # polygon / polyline
            nums = [float(v) for v in _NUM.findall(at.get('points', ''))]
            pts = list(zip(nums[0::2], nums[1::2]))
            if len(pts) < 2:
                continue
            d = 'M' + 'L'.join(f'{px} {py}' for px, py in pts) + 'Z'
        subs = flatten_path(d) if d else []
        if subs:
            out.append((subs, rule))
    return out


# ---------------------------------------------------------------------------
# 3. 包围盒 / 覆盖率（扫描线填充，超采样做抗锯齿）
# ---------------------------------------------------------------------------

def bbox(svg: str):
    """内容包围盒（用户坐标）。没有内容返回 None。"""
    xs0 = ys0 = float('inf')
    xs1 = ys1 = float('-inf')
    for subs, _rule in shapes(svg):
        for sub in subs:
            for px, py in sub:
                xs0 = min(xs0, px); xs1 = max(xs1, px)
                ys0 = min(ys0, py); ys1 = max(ys1, py)
    if xs0 == float('inf'):
        return None
    return (xs0, ys0, xs1, ys1)


def _edges_for(subs):
    """折线 → 非水平边 [(x0,y0,x1,y1,dir)]。"""
    edges = []
    for sub in subs:
        pts = list(sub)
        if len(pts) < 3:
            continue
        if pts[0] != pts[-1]:
            pts.append(pts[0])          # 填充时子路径总是隐式闭合
        for i in range(len(pts) - 1):
            x0, y0 = pts[i]
            x1, y1 = pts[i + 1]
            if y0 == y1:
                continue
            edges.append((x0, y0, x1, y1, 1 if y1 > y0 else -1))
    return edges


def render(svg: str, view: float = 24.0, size: int = 192, ss: int = 4):
    """光栅化。返回 (coverage_bytearray, W, H)，coverage 值 0..255，行优先。

    超采样：网格 W = size*ss，每个像素的覆盖率取该格子内的墨迹占比 —— 既做抗锯齿，
    也让「墨迹覆盖率」有亚像素精度（这正是量视觉重量需要的）。
    """
    W = size * ss
    s = W / view                      # 用户单位 → 超采样像素
    buf = bytearray(W * W)            # 画布是正方形（viewBox 0 0 24 24）
    groups = []
    for subs, rule in shapes(svg):
        e = _edges_for(subs)
        if e:
            groups.append((e, rule))
    if not groups:
        return buf, W, W
    for (edges, rule) in groups:
        # 按 y 分桶，避免每行都扫全部边
        buckets = {}
        for ed in edges:
            ylo = min(ed[1], ed[3])
            yhi = max(ed[1], ed[3])
            r0 = max(0, int(math.floor(ylo * s)))
            r1 = min(W - 1, int(math.ceil(yhi * s)) - 1)
            for r in range(r0, r1 + 1):
                buckets.setdefault(r, []).append(ed)
        for r, eds in buckets.items():
            y = (r + 0.5) / s
            xs = []
            for (x0, y0, x1, y1, dr) in eds:
                if (y >= y0 and y < y1) or (y >= y1 and y < y0):
                    t = (y - y0) / (y1 - y0)
                    xs.append(((x0 + t * (x1 - x0)) * s, dr))
            if len(xs) < 2:
                continue
            xs.sort()
            spans = []
            if rule:
                for i in range(0, len(xs) - 1, 2):
                    spans.append((xs[i][0], xs[i + 1][0]))
            else:
                wind = 0
                start = None
                for px, dr in xs:
                    if wind == 0:
                        start = px
                    wind += dr
                    if wind == 0 and start is not None:
                        spans.append((start, px))
                        start = None
            base = r * W
            for (a, b) in spans:
                if b <= a:
                    continue
                c0 = max(0, int(math.floor(a)))
                c1 = min(W, int(math.ceil(b)))
                if c1 <= c0:
                    continue
                # 首尾两列按部分覆盖算，中间整列直接置满（切片赋值 = C 速度）
                if c1 - c0 == 1:
                    cov = int(round(255 * min(b, c0 + 1) - 255 * max(a, c0)))
                    if a <= c0 and b >= c0 + 1:
                        cov = 255
                    if cov > buf[base + c0]:
                        buf[base + c0] = cov
                    continue
                first = int(round(255 * min(b, c0 + 1) - 255 * a))
                last = int(round(255 * b - 255 * max(a, c1 - 1)))
                first = max(0, min(255, first))
                last = max(0, min(255, last))
                if first > buf[base + c0]:
                    buf[base + c0] = first
                if c1 - 1 > c0 and last > buf[base + c1 - 1]:
                    buf[base + c1 - 1] = last
                if c1 - 1 - (c0 + 1) > 0:
                    seg = buf[base + c0 + 1: base + c1 - 1]
                    # 只把「还没满」的位置补满，保证多图形叠加时取并集（max）
                    if min(seg) < 255:
                        buf[base + c0 + 1: base + c1 - 1] = bytes(
                            255 if v < 255 else v for v in seg)
    return buf, W, W


def downsample(buf, W, H, ss):
    """超采样缓冲 → 每像素覆盖率（0..1 的二维列表）。"""
    w, h = W // ss, H // ss
    out = []
    inv = 1.0 / (255.0 * ss * ss)
    for y in range(h):
        row = []
        base = y * ss * W
        for x in range(w):
            tot = 0
            for dy in range(ss):
                off = base + dy * W + x * ss
                tot += sum(buf[off: off + ss])
            row.append(tot * inv)
        out.append(row)
    return out


def coverage(svg: str, size: int = 192, ss: int = 4):
    """返回 (墨迹覆盖率, 内容包围盒(像素, 右下开区间), (W, H), 每像素覆盖率)。"""
    buf, W, H = render(svg, size=size, ss=ss)
    cov = downsample(buf, W, H, ss)
    tot = 0.0
    x0 = y0 = 10 ** 9
    x1 = y1 = -1
    for y in range(H // ss):
        row = cov[y]
        for x in range(W // ss):
            v = row[x]
            tot += v
            if v > 0.5:
                if x < x0:
                    x0 = x
                if y < y0:
                    y0 = y
                if x > x1:
                    x1 = x
                if y > y1:
                    y1 = y
    box = None if x1 < 0 else (x0, y0, x1 + 1, y1 + 1)
    return tot / float((W // ss) * (H // ss)), box, (W // ss, H // ss), cov


def hex_to_gray(hexstr: str) -> int:
    """#RRGGBB / #AARRGGBB → 0..255 灰度（近似的感知灰度）。"""
    h = hexstr.lstrip('#')
    if len(h) == 8:
        h = h[2:]
    if len(h) != 6:
        return 0
    r, g, b = int(h[0:2], 16), int(h[2:4], 16), int(h[4:6], 16)
    return int(0.299 * r + 0.587 * g + 0.114 * b)


def preview_png(svg: str, path: str, size: int = 192, ss: int = 3,
                fg: str = '#000000', bg: str = '#FFFFFF'):
    """把 SVG 渲染成灰度 PNG（只依赖 zlib，不依赖 Pillow）。"""
    cov = downsample(*render(svg, size=size, ss=ss), ss)
    f = hex_to_gray(fg)
    b = hex_to_gray(bg)
    raw = bytearray()
    for row in cov:
        raw.append(0)
        for v in row:
            g = int(round(f * v + b * (1.0 - v)))
            raw.append(max(0, min(255, g)))
    ihdr = struct.pack('>IIBBBBB', size, size, 8, 0, 0, 0, 0)
    def chunk(t, data):
        return (struct.pack('>I', len(data)) + t + data
                + struct.pack('>I', zlib.crc32(t + data) & 0xffffffff))
    png = (b'\x89PNG\r\n\x1a\n' + chunk(b'IHDR', ihdr)
           + chunk(b'IDAT', zlib.compress(bytes(raw), 9)) + chunk(b'IEND', b''))
    with open(path, 'wb') as fp:
        fp.write(png)
    return path


def main() -> int:
    args = sys.argv[1:]
    if not args:
        print(__doc__)
        return 2
    size, ss, png = 192, 4, None
    files = []
    i = 0
    while i < len(args):
        if args[i] == '--size':
            size = int(args[i + 1]); i += 2
        elif args[i] == '--ss':
            ss = int(args[i + 1]); i += 2
        elif args[i] == '--png':
            png = args[i + 1]; i += 2
        else:
            files.append(args[i]); i += 1
    for f in files:
        with open(f, encoding='utf-8') as fp:
            svg = fp.read()
        bx = bbox(svg)
        cov, box, sz, _ = coverage(svg, size=size, ss=ss)
        print(f'{f}')
        if bx:
            print(f'  包围盒(用户坐标): x {bx[0]:.2f}..{bx[2]:.2f}  y {bx[1]:.2f}..{bx[3]:.2f}')
        print(f'  墨迹覆盖率: {cov * 100:.2f}%   内容像素盒: {box} / {sz}')
        if png:
            preview_png(svg, png, size=size)
            print(f'  预览: {png}')
    return 0


if __name__ == '__main__':
    sys.exit(main())
