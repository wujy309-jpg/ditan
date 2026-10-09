#!/usr/bin/env python3
"""生成「改造前 vs 改造后」并排对比图。

用法：
    python3 .research/make_compare.py

输入：素材/截图/预览/before-0N-*.jpeg 与 after-0N-*.jpeg
输出：素材/改造前后对比-前端美化.png

为什么要脚本而不是手工拼：这轮美化会反复迭代，每次改完都要重出对比图。
手工拼一次 5 分钟，脚本拼一次 2 秒，且不会因为手抖导致两张图不等高。
"""
import glob
import os
import re
import sys

from PIL import Image, ImageDraw, ImageFont

WS = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SHOT = os.path.join(WS, "素材", "截图", "预览")
OUT = os.path.join(WS, "素材", "改造前后对比-前端美化.png")

TITLES = {
    "01": "记一笔",
    "02": "看板",
    "03": "积分",
    "04": "科普",
    "05": "我的",
    "06": "年度报告",
}

# 本轮新增的页面没有「改造前」，用占位卡说明，而不是让对比图缺一格
NEW_PAGES = {"06"}

BG = (241, 243, 245)
CARD = (255, 255, 255)
INK1 = (10, 10, 10)
INK2 = (90, 90, 90)
GREEN = (31, 154, 78)
GRAY = (150, 158, 168)


def load_font(size: int):
    """找一个能显示中文的字体；找不到就退回默认（英文环境下标题会变方框）。"""
    candidates = [
        "/System/Library/Fonts/PingFang.ttc",
        "/System/Library/Fonts/STHeiti Medium.ttc",
        "/System/Library/Fonts/Hiragino Sans GB.ttc",
    ]
    for p in candidates:
        if os.path.exists(p):
            try:
                return ImageFont.truetype(p, size)
            except OSError:
                continue
    return ImageFont.load_default()


def pick(prefix: str, num: str):
    """找截图；找不到返回 None（用于「本轮新增、没有改造前」的页面）。"""
    hits = sorted(glob.glob(os.path.join(SHOT, f"{prefix}-{num}-*.jpeg")))
    if not hits:
        hits = sorted(glob.glob(os.path.join(SHOT, f"{prefix}-{num}-*.png")))
    return hits[0] if hits else None


def main() -> None:
    nums = sorted(TITLES.keys())
    present = []
    for n in nums:
        b, a = pick("before", n), pick("after", n)
        if a is None:
            print(f"  ⚠️  跳过 {n}：没有 after 截图", file=sys.stderr)
            continue
        present.append((n, b, a))

    if not present:
        raise SystemExit("没有任何 before/after 截图对，先在模拟器上跑 .research/preview.sh")

    # 每张手机截图先缩到统一高度
    PHONE_H = 760
    thumbs = []
    for n, b, a in present:
        ia = Image.open(a).convert("RGB")
        w = int(ia.width * PHONE_H / ia.height)
        if b is None:
            thumbs.append((n, None, ia.resize((w, PHONE_H), Image.LANCZOS)))
            continue
        ib = Image.open(b).convert("RGB")
        thumbs.append((n, ib.resize((w, PHONE_H), Image.LANCZOS),
                       ia.resize((w, PHONE_H), Image.LANCZOS)))
    phone_w = thumbs[0][2].width

    # 版式：两行（改造前 / 改造后），每行 5 列
    GAP, PAD, LABEL_H, ROW_TITLE_H = 14, 28, 34, 46
    cols = len(thumbs)
    cell_w = phone_w + GAP
    grid_w = cols * cell_w - GAP
    W = grid_w + PAD * 2
    H = PAD * 2 + ROW_TITLE_H * 2 + LABEL_H * 2 + PHONE_H * 2 + GAP * 3

    canvas = Image.new("RGB", (W, H), BG)
    d = ImageDraw.Draw(canvas)
    f_row = load_font(30)
    f_lab = load_font(20)
    f_small = load_font(15)

    for row, (key, is_before) in enumerate([("BEFORE", True), ("AFTER", False)]):
        y0 = PAD + row * (ROW_TITLE_H + LABEL_H + PHONE_H + GAP * 2)
        text = "改造前" if is_before else "改造后"
        color = GRAY if is_before else GREEN
        d.text((PAD, y0), text, font=f_row, fill=color)
        # 一行小注，说明这轮改造的规模
        note = ("v1：设计令牌只落地 15%，104 处裸写颜色，全工程零动画"
                if is_before else
                "v2：统一英雄区 + 卡片默认阴影 + 图标化 + 动效 + 修复饼图 2841% bug")
        d.text((PAD + d.textlength(text, font=f_row) + 16, y0 + 10), note,
               font=f_small, fill=GRAY)

        for i, (n, ib, ia) in enumerate(thumbs):
            x = PAD + i * cell_w
            yy = y0 + ROW_TITLE_H
            d.text((x, yy + 6), TITLES[n], font=f_lab, fill=INK2)
            yy += LABEL_H

            if is_before and ib is None:
                # 本轮新增的页面：画一张虚线占位卡，别让对比图缺一格
                canvas.paste(CARD, (x, yy, x + phone_w, yy + PHONE_H))
                d.rectangle([x, yy, x + phone_w - 1, yy + PHONE_H - 1],
                            outline=GRAY, width=1)
                msg = "本轮新增\n（无改造前）"
                for k, line in enumerate(msg.split("\n")):
                    tw = d.textlength(line, font=f_lab)
                    d.text((x + (phone_w - tw) / 2, yy + PHONE_H / 2 - 24 + k * 30),
                           line, font=f_lab, fill=GRAY)
                continue

            img = ib if is_before else ia
            canvas.paste(CARD, (x - 1, yy - 1, x + phone_w + 1, yy + PHONE_H + 1))
            canvas.paste(img, (x, yy))
            d.rectangle([x - 1, yy - 1, x + phone_w, yy + PHONE_H],
                        outline=GRAY, width=1)

    canvas.save(OUT, optimize=True)
    print(f"已生成：{OUT}（{W}×{H}，{len(thumbs)} 组对比）")


if __name__ == "__main__":
    main()
