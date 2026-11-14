# -*- coding: utf-8 -*-
"""生成《碳迹》演示视频的旁白字幕与真人录音稿。

输出：
  交付物/字幕_碳迹.srt
  交付物/字幕_碳迹.ass
  参考资料/真人录音稿.md
  参考资料/录音台本-纯文本.txt

时间轴按现有成片的 9 个段落锚点排定；每句目标语速 4.6 字/秒，
段内若放不下会自动压缩（最低 1.1 秒/句）。
"""
import os
import re
import sys

from PIL import ImageFont

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
FONT = "/System/Library/Fonts/Supplemental/Songti.ttc"
SIZE = 50
MAXW = 940          # 左栏可用宽度（px @1080p）
RATE = 4.6          # 字/秒
PUNCT = "、，。：；！？"

# (段起点, 段终点, 段首留白, 句间间隔, [(旁白, 气口提示)])
SEGMENTS = [
    (0.0, 8.0, 0.20, 0.20, [
        ("下面这段，是真实操作录屏。", "轻、快，别播音腔"),
        ("从记一笔，走到记录、看板、积分、科普，还有我的。", "列举略快，收在“我的”上，略降"),
    ]),
    (8.0, 40.0, 0.35, 0.30, [
        ("先记一笔。", "短促，起拍"),
        ("四个类目，十四种行为，都摆在这一页里。", "“都摆在”重读"),
        ("点出行，选步行，填六公里。", "三顿，一句一顿"),
        ("减排量跟着就跳出来了，一点一七公斤。", "“跳出来”重读；“一点一七公斤”放慢"),
        ("点保存，这笔账立刻进了最近的记录。", "“立刻”重读"),
        ("页尾只留三条，右边一个「全部」。", "停半拍，给下一页留口"),
        ("每条因子后面，都跟着它的基准和出处。", "收尾放慢，重要"),
    ]),
    (40.0, 54.0, 0.30, 0.25, [
        ("点「全部」，进记录页。", "转折，稍提"),
        ("上面是五等分页签：全部，加四类。", "逐项略降"),
        ("切到出行，条数和合计一起变。", "平"),
        ("删掉一条，合计马上跟着减。", "短，收住"),
    ]),
    (54.0, 70.0, 0.30, 0.25, [
        ("返回，往看板走。", "转折"),
        ("这棵树跟着累计减排一起长。", "“长”拖半拍"),
        ("十二周日历记着连续天数。", "平"),
        ("统计粒度收成了一行：日、周、月、年。", "四档逐项"),
        ("切哪一档，三张图一起动。", "“一起”重读"),
    ]),
    (70.0, 83.0, 0.30, 0.25, [
        ("再往下，是今日任务、低碳建议，和一张减排凭证。", "列举略快"),
        ("分类占比的每一行都能点。", "“都能点”重读"),
        ("点出行，就带着类目回到记录页。", "平，收住"),
    ]),
    (83.0, 97.0, 0.30, 0.25, [
        ("积分先看余额。", "平"),
        ("徽章和证书合成了一张卡：可兑换，已获得。", "两段，中间停 0.2s"),
        ("换到的植树证书，印成一张票面。", "“票面”放慢"),
        ("累计减排写得清清楚楚。", "收住"),
    ]),
    (97.0, 104.0, 0.30, 0.25, [
        ("科普是八篇短文，收成一页。", "平"),
        ("点一行，就地展开。", "轻，收住"),
    ]),
    (104.0, 115.0, 0.30, 0.25, [
        ("我的里面三件事：", "“三件事”后停 0.3s"),
        ("同步面板、AI 自检，还有 JSON 备份和 CSV 导出。", "英文词放慢，别吞"),
    ]),
    (115.0, 126.0, 0.30, 0.25, [
        ("最后是年度报告。", "转折"),
        ("记了多少条、活跃多少天，", "问句式，逐项降"),
        ("主力哪一类，还有全年积分。", "最后一项收住"),
    ]),
    (126.0, 133.0, 0.30, 0.25, [
        ("这些数据，全都留在本机。", "放慢，强调“本机”"),
        ("不上云，断网也能用。", "最慢，收得干净"),
    ]),
]


def font():
    return ImageFont.truetype(FONT, SIZE, index=1)


def wrap(text, f):
    """超宽时在标点处断成两行：优先断在句号/逗号，其次顿号，再按左右均衡挑选。"""
    if f.getlength(text) <= MAXW:
        return [text]
    penalty = {"。": 0, "！": 0, "？": 0, "，": 40, "：": 40, "；": 80, "、": 600}
    best = None
    for i, ch in enumerate(text):
        if ch in PUNCT and i + 1 < len(text):
            a, b = text[: i + 1], text[i + 1:]
            wa, wb = f.getlength(a), f.getlength(b)
            if wa <= MAXW and wb <= MAXW:
                score = abs(wa - wb) + penalty.get(ch, 100)
                if best is None or score < best[0]:
                    best = (score, a, b)
    if best:
        return [best[1], best[2]]
    half = len(text) // 2
    return [text[:half], text[half:]]


def build_cues():
    cues = []
    for seg, (s, e, lead, gap, lines) in enumerate(SEGMENTS, 1):
        t, tmp = s + lead, []
        for text, hint in lines:
            n = len(re.sub(r"\s", "", text))
            d = max(1.2, n / RATE)
            tmp.append([t, t + d, text, hint, seg, n, d])
            t = t + d + gap
        if tmp[-1][1] > e:  # 整段超窗，等比压缩
            k = (e - s - lead - gap * (len(lines) - 1)) / sum(c[6] for c in tmp)
            t, tmp = s + lead, []
            for text, hint in lines:
                n = len(re.sub(r"\s", "", text))
                d = max(1.0, n / RATE * k)
                tmp.append([t, t + d, text, hint, seg, n, d])
                t = t + d + gap
        cues += tmp
    return cues


def srt_ts(x):
    """先取整到毫秒再拆分，避免 7.9999 被写成「07,1000」这种非法时间码。"""
    ms = int(round(x * 1000))
    h, rem = divmod(ms, 3600000)
    m, rem = divmod(rem, 60000)
    s, ms = divmod(rem, 1000)
    return "%02d:%02d:%02d,%03d" % (h, m, s, ms)


def ass_ts(x):
    cs = int(round(x * 100))
    h, rem = divmod(cs, 360000)
    m, rem = divmod(rem, 6000)
    s, cs = divmod(rem, 100)
    return "%d:%02d:%02d.%02d" % (h, m, s, cs)


ASS_HEAD = """[Script Info]
Title: 碳迹 · 功能演示
ScriptType: v4.00+
PlayResX: 1920
PlayResY: 1080
WrapStyle: 2
ScaledBorderAndShadow: yes

[V4+ Styles]
Format: Name, Fontname, Fontsize, PrimaryColour, SecondaryColour, OutlineColour, BackColour, Bold, Italic, Underline, StrikeOut, ScaleX, ScaleY, Spacing, Angle, BorderStyle, Outline, Shadow, Alignment, MarginL, MarginR, MarginV, Encoding
Style: Ledger,Songti SC,50,&H001C2226,&H000000FF,&H00F0F7FA,&H00000000,0,0,0,0,100,100,0.5,0,1,2.5,0,1,100,900,96,1

[Events]
Format: Layer, Start, End, Style, Name, MarginL, MarginR, MarginV, Effect, Text
"""


def main():
    f = font()
    cues = build_cues()
    wrapped = [wrap(c[2], f) for c in cues]

    srt = []
    for i, ((a, b, *_rest), ls) in enumerate(zip(cues, wrapped), 1):
        srt.append("%d\n%s --> %s\n%s\n" % (i, srt_ts(a), srt_ts(b), "\n".join(ls)))
    open(os.path.join(ROOT, "交付物/字幕_碳迹.srt"), "w", encoding="utf-8").write("\n".join(srt))

    body = ["Dialogue: 0,%s,%s,Ledger,,0,0,0,,%s" % (ass_ts(c[0]), ass_ts(c[1]), "\\N".join(ls))
            for c, ls in zip(cues, wrapped)]
    open(os.path.join(ROOT, "交付物/字幕_碳迹.ass"), "w", encoding="utf-8").write(ASS_HEAD + "\n".join(body) + "\n")

    md = ["# 真人录音稿 · 碳迹功能演示（%d 句）" % len(cues), "",
          "> 每句一个文件：`01.wav` … `%02d.wav`，按序号读，不要跳。" % len(cues),
          "> “预算时长”按 4.6 字/秒估算；略快略慢都可以，我会在段内吸收。", "",
          "> ⚠️ 这份是**录制前**的稿子。录音已交付并按真实停顿对齐，",
          "> 实际时间码见 `参考资料/旁白对齐表.md`（字幕也已按母带重排）。", "",
          "| # | 目标时间码 | 字数 | 预算 | 旁白 | 气口与重音 |", "|---|---|---|---|---|---|"]
    for i, ((a, b, t, h, seg, n, d), ls) in enumerate(zip(cues, wrapped), 1):
        md.append("| %02d | %s → %s | %d | %.1fs | %s | %s |"
                  % (i, srt_ts(a), srt_ts(b), n, d, t, h))
    md += ["", "## 录制要点", "",
           "- 环境：衣柜里最好（衣服吸音），关空调、关风扇，手机飞行模式；",
           "- 设备：手机录音即可，嘴到麦克风 15–20 cm，别贴太近；",
           "- 每条前后各留 0.5 秒静音；每条录 2 遍，挑更松的一遍；",
           "- 数字读法：一点一七公斤 / 十四种 / 十二周 / 八篇 / 三件事；",
           "- 英文读字母：J-S-O-N、C-S-V、A-I 自检；",
           "- 不要加“嗯”“那个”——口语感来自短句，不来自语气词。", "",
           "## 录完之后", "",
           "把文件按 01–%02d 命名放进一个文件夹，我来排轨、做母带、烧字幕、重新导出。" % len(cues), ""]
    open(os.path.join(ROOT, "参考资料/真人录音稿.md"), "w", encoding="utf-8").write("\n".join(md))

    open(os.path.join(ROOT, "参考资料/录音台本-纯文本.txt"), "w", encoding="utf-8").write(
        "\n".join("%02d  %s" % (i, c[2]) for i, c in enumerate(cues, 1)))

    two = sum(1 for ls in wrapped if len(ls) == 2)
    print("cues=%d  两行=%d  末条=%.2fs" % (len(cues), two, cues[-1][1]))
    for i, ls in enumerate(wrapped, 1):
        if len(ls) == 2:
            print("  %02d %s" % (i, " ／ ".join(ls)))


if __name__ == "__main__":
    sys.exit(main())
