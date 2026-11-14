#!/usr/bin/env python3
"""合成 v3.4 功能演示成片：真人旁白 + 截图画面 + 已对齐字幕。

为什么是截图而不是真机录屏：
    模拟器这条链路能截屏、能点按，但「点按 + 滚动 + 软键盘输入」在自动化下
    对时序太敏感（滚动未停稳就点、键盘位置随焦点变化），录一版 2 分 20 秒
    的连续操作要重录很多次。这份成片用同一套页面截图（数据同为 21.75 kg /
    12 条 / 1,875 分）配合旁白锚点推进，画面稳定、字幕与人声严格同步。

用法：python3 tools/docs/make_demo_v34.py
产出：交付物/演示视频_碳迹.mp4（1920×1080，24fps，2'21.6"）
"""
import json
import os
import subprocess
from PIL import Image, ImageDraw, ImageFont

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
os.chdir(ROOT)

W, H, FPS = 1920, 1080, 24
AUDIO = os.environ.get("DEMO_AUDIO", "交付物/旁白_碳迹_v3.4_母带.m4a")
ALIGN = os.environ.get("DEMO_ALIGN", "参考资料/旁白对齐.json")
OUT = os.environ.get("DEMO_OUT", "交付物/演示视频_碳迹.mp4")
TMP = "/tmp/demo34"
QI = "素材/截图/质量改进"
V34 = "素材/截图/v3.4"
OLD = "素材/截图/v3.3"

SERIF = "/System/Library/Fonts/Supplemental/Songti.ttc"
INK = (32, 29, 23)
INK2 = (76, 70, 58)
INK3 = (133, 124, 106)
INK4 = (181, 172, 152)
RULE = (214, 205, 186)
SEAL = (171, 58, 40)
PAPER = (242, 237, 225)

PH_X, PH_Y, PH_W, PH_H = 1180, 30, 604, 1020

# (kicker, title, steps, [shots])  shots 按段内均分切换
SEGS = [
    ("功能演示", "碳 迹 · 个 人 碳 账 本",
     ["真实应用页面 · 数据全部留在本机", "记录 → 折算 → 看见 → 激励 → 回馈"],
     [(f"{V34}/10-记一笔-顶部", "")]),
    ("01 / 记一笔", "把一笔碳账记清楚",
     ["四个类目、十四种行为，一页里选", "6 公里步行 → 1.17 kg CO2e", "保存即入账，积分同步发放"],
     [(f"{V34}/10-记一笔-顶部", ""), (f"{QI}/05-记一笔-最近记录收口", "")]),
    ("02 / 记录", "分类查询，翻得到全部明细",
     ["五等分账页签：全部 + 四类", "切类目，条数与合计一起变", "每行可删，删完合计立刻回落"],
     [(f"{QI}/06-记录-全部类目", ""), (f"{QI}/07-记录-分类查询", "")]),
    ("03 / 看板", "让「坚持」看得见",
     ["一棵树：树冠密度 = 累计减排", "12 周日历：连续 5 天、12 天有记录", "日 / 周 / 月 / 年，三张图同一口径"],
     [(f"{V34}/20-看板-树与头部", ""), (f"{V34}/21-看板-年视图", "")]),
    ("04 / 看板 · 下半", "任务、建议与减排凭证",
     ["今日低碳任务：短板优先", "生活建议：每条对应一个数据事实", "减排凭证：小票式排版 + 朱印"],
     [(f"{V34}/22-看板-下半", ""), (f"{QI}/14-看板-底部三块统一表头", "")]),
    ("05 / 积分", "从「数字」到「权益」",
     ["每减排 1 kg 得 100 分", "徽章与证书合一：可兑换 / 已获得", "植树证书印成票面，可截图带走"],
     [(f"{V34}/30-积分-顶部", ""), (f"{QI}/08-积分-徽章证书合一", ""), (f"{QI}/09-积分-已获得证书", "")]),
    ("06 / 科普", "八篇短文，收成一页",
     ["政策 / 概念 / 数据 / 技巧四类", "点一行就地展开，箭头转 90°"],
     [(f"{QI}/12-科普-十卡收成一页", ""), (f"{QI}/13-科普-行内展开", "")]),
    ("07 / 我的", "数据归谁，摊开给你看",
     ["同步面板：本机、可信设备、冲突数", "端侧 AI 自检：模型可加载、能出索引", "JSON 备份、CSV 报表、清空"],
     [(f"{OLD}/41-我的-同步与数据", "")]),
    ("08 / 年度报告", "把一年收成一页",
     ["活跃天数、记录条数、累计减排", "主力贡献与分类构成", "与看板同源同口径"],
     [(f"{V34}/40-年报-封面", ""), (f"{V34}/41-年报-构成", "")]),
    ("结束", "把每一笔低碳，\n都记成看得见的改变",
     ["数据全部保存在本机 · 不上传云端", "离线也能用"],
     [(f"{V34}/42-年报-下半", "")]),
]


def font(size, bold=True):
    return ImageFont.truetype(SERIF, size, index=0 if bold else 1)


F_KICK = font(24, False)
F_TITLE = font(50)
F_STEP = font(27, False)
F_SMALL = font(21, False)
F_BIG = font(58)
F_SUB = font(40, False)


CUES = []


def load_cues():
    d = json.load(open(ALIGN, encoding="utf-8"))
    return [(c["start"], c["end"], c["text"]) for c in d["cues"]]


def wrap_text(text, f, max_w):
    lines, cur = [], ""
    for ch in text:
        if f.getlength(cur + ch) > max_w and cur:
            lines.append(cur)
            cur = ch
        else:
            cur += ch
    if cur:
        lines.append(cur)
    return lines


def draw_subtitle(d, t):
    for start, end, text in CUES:
        if start - 0.05 <= t <= end + 0.15:
            lines = wrap_text(text, F_SUB, 880)
            y = 918 if len(lines) == 1 else 884
            for ln in lines:
                d.text((108, y), ln, font=F_SUB, fill=INK)
                y += 58
            return


def paper_bg():
    return Image.open("/tmp/carbon-visuals/paper-bg.png").convert("RGB").resize((W, H), Image.LANCZOS)


def phone_layer(path):
    """把 1320×2232 的截图缩成右侧手机层，并多留一圈放大余量。"""
    if not os.path.exists(path) and os.path.exists(path + ".jpeg"):
        path += ".jpeg"
    im = Image.open(path).convert("RGB").resize((PH_W + 40, PH_H + 68), Image.LANCZOS)
    return im


def frame_at(t, seg_idx, shot_idx, zoom, bg):
    """一帧：纸底 + 左侧文案 + 右侧手机层（带轻微推近）。"""
    im = bg.copy()
    d = ImageDraw.Draw(im)
    kick, title, steps, shots = SEGS[seg_idx]

    # ---- 左栏
    d.text((110, 96), kick, font=F_KICK, fill=INK3)
    y = 150
    for line in title.split("\n"):
        d.text((108, y), line, font=F_TITLE, fill=INK)
        y += 66
    d.line([(108, y + 18), (1000, y + 18)], fill=INK, width=3)
    d.line([(108, y + 26), (1000, y + 26)], fill=RULE, width=2)
    y += 62
    for st in steps:
        d.ellipse([112, y + 12, 121, y + 21], fill=SEAL)
        d.text((140, y), st, font=F_STEP, fill=INK2)
        y += 56

    draw_subtitle(d, t)

    # ---- 页脚（先画，避免被手机层盖住；只占左栏）
    d.line([(108, 1016), (1000, 1016)], fill=RULE, width=1)
    d.text((108, 1028), "碳迹 · 赛题二　功能演示", font=F_SMALL, fill=INK3)
    d.text((920, 1028), "v3.4", font=F_SMALL, fill=INK3)

    # ---- 右侧手机
    ph = phone_layer(shots[shot_idx][0])
    src_w, src_h = ph.size
    crop_w = int(src_w / zoom)
    crop_h = int(src_h / zoom)
    cx = (src_w - crop_w) // 2
    cy = (src_h - crop_h) // 2
    layer = ph.crop((cx, cy, cx + crop_w, cy + crop_h)).resize((PH_W, PH_H), Image.LANCZOS)
    im.paste(layer, (PH_X, PH_Y))
    d.rectangle([PH_X, PH_Y, PH_X + PH_W - 1, PH_Y + PH_H - 1], outline=RULE, width=2)

    return im


def main():
    os.makedirs(TMP, exist_ok=True)
    global CUES
    align = json.load(open(ALIGN, encoding="utf-8"))
    CUES = load_cues()
    spans = [(s["start"], s["end"]) for s in align["segments"]]
    total = align["duration"]
    bg = paper_bg()

    # 预渲染每个「段 × 镜头」的静态底（不含推近），减少重复绘制
    raw_path = f"{TMP}/video.mp4"
    cmd = ["ffmpeg", "-y", "-hide_banner", "-loglevel", "error",
           "-f", "rawvideo", "-pix_fmt", "rgb24", "-s", f"{W}x{H}", "-r", str(FPS), "-i", "-",
           "-c:v", "libx264", "-preset", "veryfast", "-crf", "17", "-pix_fmt", "yuv420p", raw_path]
    proc = subprocess.Popen(cmd, stdin=subprocess.PIPE)

    n_frames = int(round(total * FPS))
    seg = 0
    for i in range(n_frames):
        t = i / FPS
        while seg + 1 < len(spans) and t >= spans[seg + 1][0] - 0.15:
            seg += 1
        s, e = spans[seg]
        shots = SEGS[seg][3]
        p = min(max((t - s) / max(0.001, e - s), 0), 1)
        shot_idx = min(int(p * len(shots)), len(shots) - 1)
        # 段内每镜头再算一次局部进度，用于推近
        local = (p * len(shots)) - shot_idx
        zoom = 1.0 + 0.035 * min(max(local, 0), 1)
        fr = frame_at(t, seg, shot_idx, zoom, bg)
        proc.stdin.write(fr.tobytes())
    proc.stdin.close()
    proc.wait()
    print("raw done", total)

    # 烧字幕 + 混母带
    sub = ["ffmpeg", "-y", "-hide_banner", "-loglevel", "error",
           "-i", raw_path, "-i", AUDIO,
           "-c:v", "copy",
           "-c:a", "aac", "-b:a", "192k", "-shortest", "-movflags", "+faststart", OUT]
    subprocess.run(sub, check=True)
    print("saved", OUT, round(os.path.getsize(OUT) / 1e6, 1), "MB")


if __name__ == "__main__":
    main()
