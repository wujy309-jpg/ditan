#!/usr/bin/env python3
"""碳迹视觉资产：纸纹、朱印、架构图、闭环图。所有图都用同一套纸墨令牌。"""
import math, os, random
from PIL import Image, ImageDraw, ImageFont, ImageFilter

PAPER = (242, 237, 225)
PAPER_L = (251, 248, 241)
INK = (32, 29, 23)
INK2 = (76, 70, 58)
INK3 = (133, 124, 106)
INK4 = (181, 172, 152)
RULE = (214, 205, 186)
SEAL = (171, 58, 40)
MOSS = (29, 92, 67)
OUT = "/tmp/carbon-visuals"

SERIF = "/System/Library/Fonts/Supplemental/Songti.ttc"
SANS = "/System/Library/Fonts/STHeiti Medium.ttc"

def serif(size, bold=True):
    return ImageFont.truetype(SERIF, size, index=0 if bold else 1)

def sans(size):
    return ImageFont.truetype(SANS, size)

def paper(w, h, base=PAPER, amp=3.2, seed=7):
    import numpy as np
    rng = np.random.default_rng(seed)
    lh, lw = (h + 7) // 8, (w + 7) // 8
    low = rng.normal(0, 1, (max(2, lh), max(2, lw)))
    low = np.kron(low, np.ones((8, 8)))[:h, :w]
    high = rng.normal(0, 1, (h, w))
    n = low * 0.45 + high * 0.55
    n = n / (np.abs(n).max() + 1e-6) * amp
    arr = np.zeros((h, w, 3), dtype=np.float32)
    for i in range(3):
        arr[..., i] = base[i] + n
    return Image.fromarray(np.clip(arr, 0, 255).astype(np.uint8), "RGB")

def dashed_line(d, xy, fill=RULE, width=2, dash=6, gap=6):
    x1, y1, x2, y2 = xy
    L = math.hypot(x2 - x1, y2 - y1)
    if L == 0: return
    ux, uy = (x2 - x1) / L, (y2 - y1) / L
    t = 0
    while t < L:
        e = min(L, t + dash)
        d.line([(x1 + ux * t, y1 + uy * t), (x1 + ux * e, y1 + uy * e)], fill=fill, width=width)
        t = e + gap

def arrow(d, x1, y1, x2, y2, fill=INK3, width=3, head=12):
    d.line([(x1, y1), (x2, y2)], fill=fill, width=width)
    ang = math.atan2(y2 - y1, x2 - x1)
    for s in (-1, 1):
        d.line([(x2, y2), (x2 - head * math.cos(ang + s * 0.5), y2 - head * math.sin(ang + s * 0.5))],
               fill=fill, width=width)

def seal(text="碳迹", size=220, angle=-5, color=SEAL, seed=11, pad=26):
    """手绘抖动方章：两遍墨 + 内栏 + 竖排两字。"""
    rng = random.Random(seed)
    W = size + pad * 2
    im = Image.new("RGBA", (W, W), (0, 0, 0, 0))
    d = ImageDraw.Draw(im)
    x0, y0, x1, y1 = pad, pad, pad + size, pad + size
    off = max(1.1, size * 0.007)

    def edge(p1, p2, w, alpha, jitter):
        # 平移 + 微倾斜
        dx, dy = p2[0] - p1[0], p2[1] - p1[1]
        L = math.hypot(dx, dy)
        nx, ny = -dy / L, dx / L
        a = rng.uniform(-jitter, jitter)
        b = rng.uniform(-jitter, jitter)
        q1 = (p1[0] + nx * a + rng.uniform(-jitter, jitter) * 0.3,
              p1[1] + ny * a + rng.uniform(-jitter, jitter) * 0.3)
        q2 = (p2[0] + nx * b + rng.uniform(-jitter, jitter) * 0.3,
              p2[1] + ny * b + rng.uniform(-jitter, jitter) * 0.3)
        mx, my = (q1[0] + q2[0]) / 2, (q1[1] + q2[1]) / 2
        bow = rng.uniform(-jitter, jitter)
        pts = [q1, (mx + nx * bow, my + ny * bow), q2]
        d.line(pts, fill=color + (alpha,), width=w, joint="curve")

    def rect(w, alpha, jitter):
        edge((x0, y0), (x1, y0), w, alpha, jitter)
        edge((x1, y0), (x1, y1), w, alpha, jitter)
        edge((x1, y1), (x0, y1), w, alpha, jitter)
        edge((x0, y1), (x0, y0), w, alpha, jitter)

    rect(max(2, int(size * 0.048)), 235, off)
    rect(max(2, int(size * 0.048)), 95, off * 0.55)   # 余墨
    inset = size * 0.16
    rect(max(1, int(size * 0.020)), 210, off * 0.45)
    # 内栏位置：外框内缩
    # 竖排两字
    f = serif(int(size * 0.40), True)
    chars = list(text)[:2]
    for i, ch in enumerate(chars):
        bb = d.textbbox((0, 0), ch, font=f)
        tw, th = bb[2] - bb[0], bb[3] - bb[1]
        cx = W / 2 - tw / 2 - bb[0]
        cy = y0 + inset + i * (size - inset * 2) / 2 + ((size - inset * 2) / 2 - th) / 2 - bb[1]
        d.text((cx, cy), ch, font=f, fill=color + (240,))
    im = im.rotate(angle, resample=Image.BICUBIC, expand=True)
    return im

def centered(d, box, text, font, fill=INK, spacing=4):
    x0, y0, x1, y1 = box
    bb = d.textbbox((0, 0), text, font=font)
    w, h = bb[2] - bb[0], bb[3] - bb[1]
    d.text(((x0 + x1 - w) / 2 - bb[0], (y0 + y1 - h) / 2 - bb[1]), text, font=font, fill=fill)

def architecture(path):
    W, H = 2200, 1420
    im = paper(W, H)
    d = ImageDraw.Draw(im)
    d.text((100, 92), "系统架构", font=serif(58), fill=INK)
    d.line([(100, 176), (760, 176)], fill=INK, width=4)
    d.line([(100, 190), (760, 190)], fill=INK, width=2)
    d.text((100, 214), "四层结构，自上而下；箭头表示调用方向", font=sans(30), fill=INK3)

    layers = [
        ("表现层", "五个页签 + 年度报告", [
            "记一笔\nEntryPage", "看板\nDashboard / Charts", "积分\nPointsPage",
            "科普\nKnowledgePage", "我的\nProfilePage", "年报\nYearReport"
        ], "11 个通用组件 · 零第三方 UI 依赖"),
        ("业务层", "领域逻辑，不依赖界面", [
            "减排核算\nER = AD × EF", "积分与徽章", "任务推荐\n短板优先",
            "生活建议", "碳普惠五环节", "分享凭证"
        ], "纯 TS，可在 Node 中直接断言"),
        ("数据层", "统一仓储 + 分布式 KV", [
            "CarbonRepository", "BehaviorRecord", "PointsEntry",
            "Profile / 家庭 ID", "PlatformAccount", "信封\n{payload, ts, origin}"
        ], "取全量 → 内存筛选；时间戳冲突合并"),
        ("能力层", "鸿蒙系统能力", [
            "distributedKVStore", "distributed\nDeviceManager", "MindSpore Lite",
            "Core Vision Kit", "ArkUI 快照", "组件快照 / 字体注册"
        ], "全部离线，图片不出设备"),
    ]
    top = 300
    bh = 236
    gap = 34
    for i, (name, sub, mods, note) in enumerate(layers):
        y = top + i * (bh + gap)
        # 左侧标签
        d.text((100, y + 24), name, font=serif(40), fill=INK)
        d.text((100, y + 84), sub, font=sans(24), fill=INK3)
        # 分隔双线
        d.line([(100, y + bh - 44), (2100, y + bh - 44)], fill=RULE, width=2)
        # 模块
        n = len(mods)
        x = 470
        avail = 2100 - x
        mw = (avail - (n - 1) * 18) / n
        for j, m in enumerate(mods):
            bx = x + j * (mw + 18)
            d.rectangle([bx, y + 8, bx + mw, y + bh - 78], outline=RULE, width=2, fill=PAPER_L)
            lines = m.split("\n")
            fsz = 22
            while fsz > 17 and max(d.textlength(l, font=sans(fsz)) for l in lines) > mw - 16:
                fsz -= 1
            f = sans(fsz)
            total = len(lines) * (fsz + 8)
            ty = (y + 8 + y + bh - 78) / 2 - total / 2
            for l in lines:
                centered(d, (bx, ty, bx + mw, ty + fsz + 8), l, f, INK2)
                ty += fsz + 8
        d.text((100, y + bh - 32), note, font=sans(21), fill=INK4)
    # 层间箭头
    for i in range(3):
        y = top + i * (bh + gap) + bh - 6
        for xx in (700, 1290, 1880):
            arrow(d, xx, y, xx, y + gap - 6, fill=INK4, width=2, head=8)
    # 右侧竖排说明
    im.save(path)

def loop(path):
    W, H = 1800, 1120
    im = paper(W, H)
    d = ImageDraw.Draw(im)
    d.text((100, 82), "「量化 — 激励 — 回馈」闭环", font=serif(52), fill=INK)
    d.line([(100, 158), (1080, 158)], fill=INK, width=4)
    d.line([(100, 172), (1080, 172)], fill=INK, width=2)
    cx, cy, R = 900, 660, 330
    nodes = [
        ("01", "记录", "拍照 / 选图 / 手填"),
        ("02", "折算", "活动量 × 因子"),
        ("03", "看见", "树 / 日历 / 趋势"),
        ("04", "激励", "积分 · 勋章 · 证书"),
        ("05", "回馈", "城市碳普惠权益"),
    ]
    ang0 = -90
    pts = []
    for i in range(5):
        a = math.radians(ang0 + i * 72)
        pts.append((cx + R * math.cos(a), cy + R * math.sin(a)))
    # 弧线箭头
    for i in range(5):
        a1 = math.radians(ang0 + i * 72 + 10)
        a2 = math.radians(ang0 + (i + 1) * 72 - 12)
        box = [cx - R, cy - R, cx + R, cy + R]
        d.arc(box, start=ang0 + i * 72 + 10, end=ang0 + (i + 1) * 72 - 10,
              fill=INK3, width=3)
        ex, ey = cx + R * math.cos(a2), cy + R * math.sin(a2)
        tx, ty = cx + R * math.cos(a2 - 0.06), cy + R * math.sin(a2 - 0.06)
        ang = math.atan2(ey - ty, ex - tx)
        for s in (-1, 1):
            d.line([(ex, ey), (ex - 16 * math.cos(ang + s * 0.5), ey - 16 * math.sin(ang + s * 0.5))],
                   fill=INK3, width=3)
    for i, ((num, title, sub), (x, y)) in enumerate(zip(nodes, pts)):
        rr = 92
        d.ellipse([x - rr, y - rr, x + rr, y + rr], fill=PAPER_L, outline=RULE, width=2)
        centered(d, (x - rr, y - 78, x + rr, y - 18), num, serif(26), SEAL)
        centered(d, (x - rr, y - 34, x + rr, y + 36), title, serif(38))
        centered(d, (x - rr, y + 40, x + rr, y + 76), sub, sans(19), INK3)
    # 中心
    s = seal("碳迹", size=150, angle=-5)
    im.paste(s, (int(cx - s.width / 2), int(cy - s.height / 2)), s)
    d.text((cx - 120, cy + 100), "碳账本", font=serif(28), fill=INK3)
    im.save(path)

def ai_path(path):
    W, H = 1800, 900
    im = paper(W, H)
    d = ImageDraw.Draw(im)
    d.text((90, 70), "端侧 AI：双通路 + 置信度融合", font=serif(46), fill=INK)
    d.line([(90, 136), (980, 136)], fill=INK, width=4)
    # 输入
    d.rectangle([90, 330, 330, 570], outline=RULE, width=2, fill=PAPER_L)
    centered(d, (90, 330, 330, 470), "一张照片", serif(32))
    centered(d, (90, 470, 330, 560), "不出设备", sans(20), INK3)
    # 两路
    d.rectangle([460, 190, 980, 370], outline=RULE, width=2, fill=PAPER_L)
    d.text((490, 220), "视觉通路", font=serif(30), fill=INK)
    d.text((490, 272), "MindSpore Lite · MobileNetV2", font=sans(22), fill=INK2)
    d.text((490, 312), "输出 Top-5 类别索引", font=sans(22), fill=INK3)
    d.rectangle([460, 530, 980, 710], outline=RULE, width=2, fill=PAPER_L)
    d.text((490, 560), "文字通路", font=serif(30), fill=INK)
    d.text((490, 612), "Core Vision Kit 端侧 OCR", font=sans(22), fill=INK2)
    d.text((490, 652), "关键词 → 行为映射", font=sans(22), fill=INK3)
    # 融合
    d.rectangle([1130, 330, 1600, 570], outline=INK2, width=3, fill=PAPER_L)
    centered(d, (1130, 340, 1600, 430), "置信度融合", serif(34))
    centered(d, (1130, 430, 1600, 500), "一致 ↑ / 冲突取高", sans(22), INK3)
    centered(d, (1130, 500, 1600, 550), "仅高置信预填", sans(22), SEAL)
    arrow(d, 330, 420, 450, 310, fill=INK4, width=3, head=12)
    arrow(d, 330, 480, 450, 620, fill=INK4, width=3, head=12)
    arrow(d, 980, 280, 1120, 400, fill=INK4, width=3, head=12)
    arrow(d, 980, 620, 1120, 500, fill=INK4, width=3, head=12)
    im.save(path)

if __name__ == "__main__":
    os.makedirs(OUT, exist_ok=True)
    paper(1920, 1080).save(f"{OUT}/paper-bg.png")
    paper(1600, 900, base=PAPER_L, amp=2.4, seed=3).save(f"{OUT}/paper-light.png")
    seal("碳迹", 260).save(f"{OUT}/seal.png")
    seal("减排账", 200, angle=-4).save(f"{OUT}/seal-ledger.png")
    seal("碳迹", 160, angle=-6, seed=5).save(f"{OUT}/seal-small.png")
    architecture(f"{OUT}/architecture.png")
    loop(f"{OUT}/loop.png")
    ai_path(f"{OUT}/ai-path.png")
    print("ok", os.listdir(OUT))
