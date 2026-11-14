#!/usr/bin/env python3
"""生成《碳迹》汇报 PPT（v3.4 碳账本）。16:9，23 页，约 10 分钟。"""
import os
from pptx import Presentation
from pptx.util import Inches, Pt, Emu
from pptx.dml.color import RGBColor
from pptx.enum.text import PP_ALIGN, MSO_ANCHOR
from pptx.enum.shapes import MSO_SHAPE
from pptx.oxml.ns import qn

OUT = "交付物/演示文稿_碳迹.pptx"
SHOT = "素材/截图/v3.3"
QI = "素材/截图/质量改进"
ASSET = "素材"
VIS = "/tmp/carbon-visuals"

INK = RGBColor(0x20, 0x1D, 0x17)
INK2 = RGBColor(0x4C, 0x46, 0x3A)
INK3 = RGBColor(0x85, 0x7C, 0x6A)
INK4 = RGBColor(0xB5, 0xAC, 0x98)
SEAL = RGBColor(0xAB, 0x3A, 0x28)
MOSS = RGBColor(0x1D, 0x5C, 0x43)
PAPER = RGBColor(0xF2, 0xED, 0xE1)
PAPER_L = RGBColor(0xFB, 0xF8, 0xF1)
RULE = RGBColor(0xD6, 0xCD, 0xBA)
FONT = "宋体"
TOTAL = 23

prs = Presentation()
prs.slide_width = Inches(13.333)
prs.slide_height = Inches(7.5)
BLANK = prs.slide_layouts[6]


def new():
    s = prs.slides.add_slide(BLANK)
    s.shapes.add_picture(f"{VIS}/paper-bg.png", 0, 0, prs.slide_width, prs.slide_height)
    return s


def tb(s, x, y, w, h, text="", size=16, bold=False, color=INK, font=FONT,
       align=PP_ALIGN.LEFT, ls=1.25, after=0, anchor=MSO_ANCHOR.TOP, spc=None):
    box = s.shapes.add_textbox(Inches(x), Inches(y), Inches(w), Inches(h))
    tf = box.text_frame
    tf.word_wrap = True
    tf.margin_left = 0; tf.margin_right = 0; tf.margin_top = 0; tf.margin_bottom = 0
    tf.vertical_anchor = anchor
    p = tf.paragraphs[0]
    p.alignment = align
    p.line_spacing = ls
    p.space_after = Pt(after)
    r = p.add_run(); r.text = text
    f = r.font; f.name = font; f.size = Pt(size); f.bold = bold; f.color.rgb = color
    if spc:
        r._r.get_or_add_rPr().set("spc", str(int(spc * 100)))
    return box


def rich(s, x, y, w, h, lines, size=15, color=INK2, ls=1.35, gap=6,
         bullet="·", align=PP_ALIGN.LEFT):
    """lines: list[str] 或 (text, bold, color)。加粗元组视为小标题，不加项目符号。"""
    box = s.shapes.add_textbox(Inches(x), Inches(y), Inches(w), Inches(h))
    tf = box.text_frame; tf.word_wrap = True
    tf.margin_left = 0; tf.margin_right = 0; tf.margin_top = 0; tf.margin_bottom = 0
    heading = False
    for i, line in enumerate(lines):
        p = tf.paragraphs[0] if i == 0 else tf.add_paragraph()
        p.alignment = align; p.line_spacing = ls; p.space_after = Pt(gap)
        if isinstance(line, tuple):
            text, bold, col = (line + (color,))[:3] if len(line) == 2 else line
        else:
            text, bold, col = line, False, color
        if bold:
            heading = True
            p.level = 0
        else:
            p.level = 1 if heading else 0
            if bullet:
                rb = p.add_run(); rb.text = bullet + "  "
                rb.font.name = FONT; rb.font.size = Pt(size); rb.font.color.rgb = SEAL
        r = p.add_run(); r.text = text
        r.font.name = FONT; r.font.size = Pt(size + (1 if bold else 0))
        r.font.bold = bold; r.font.color.rgb = col
    return box


def rule(s, x, y, w, h=0.012, color=INK):
    sh = s.shapes.add_shape(MSO_SHAPE.RECTANGLE, Inches(x), Inches(y), Inches(w), Inches(h))
    sh.fill.solid(); sh.fill.fore_color.rgb = color; sh.line.fill.background()


def kicker(s, text, num=""):
    tb(s, 0.8, 0.38, 8.0, 0.28, text, 10.5, False, INK3, spc=2)
    n = len(prs.slides._sldIdLst)
    tb(s, 10.4, 0.34, 2.2, 0.3, f"{n:02d} / {TOTAL}", 11, False, SEAL, align=PP_ALIGN.RIGHT, spc=2)


def title(s, text, sub=None, y=0.66):
    tb(s, 0.8, y, 11.8, 0.72, text, 29, True, INK, ls=1.1)
    rule(s, 0.8, y + 0.82, 11.72, 0.028, INK)
    rule(s, 0.8, y + 0.875, 11.72, 0.012, RULE)
    if sub:
        tb(s, 0.8, y + 0.98, 11.4, 0.4, sub, 13.5, False, INK3)


def footer(s, n, section=""):
    rule(s, 0.8, 7.02, 11.72, 0.01, RULE)
    tb(s, 0.8, 7.08, 7.0, 0.24, "碳迹 · 赛题二" + (f"　/　{section}" if section else ""), 9, False, INK3, spc=1)
    tb(s, 10.8, 7.06, 1.72, 0.26, f"{n:02d}", 10, False, INK3, align=PP_ALIGN.RIGHT)


def pic(s, path, x, y, w=None, h=None):
    """按原图比例放图：只给宽或只给高，另一边自动算，避免拉伸。"""
    from PIL import Image
    iw, ih = Image.open(path).size
    if w is None:
        w = h * iw / ih
    if h is None:
        h = w * ih / iw
    s.shapes.add_picture(path, Inches(x), Inches(y), Inches(w), Inches(h))
    return w, h


def phone(s, path, x, y, h=4.9, cap=None, cap_w=None):
    from PIL import Image
    w = h * Image.open(path).width / Image.open(path).height
    s.shapes.add_picture(path, Inches(x), Inches(y), Inches(w), Inches(h))
    frame = s.shapes.add_shape(MSO_SHAPE.RECTANGLE, Inches(x), Inches(y), Inches(w), Inches(h))
    frame.fill.background(); frame.line.color.rgb = RULE; frame.line.width = Pt(0.75)
    if cap:
        tb(s, x - 0.15, y + h + 0.1, (cap_w or w + 0.3), 0.5, cap, 9.5, False, INK3, ls=1.2)
    return w


def seal(s, x, y, w=1.1):
    s.shapes.add_picture(f"{VIS}/seal.png", Inches(x), Inches(y), Inches(w), Inches(w))


def notes(s, text):
    s.notes_slide.notes_text_frame.text = text


def big_num(s, x, y, num, label, w=2.2, size=54):
    tb(s, x, y, w, 0.9, num, size, True, INK, ls=1.0)
    tb(s, x, y + 0.92, w, 0.4, label, 11, False, INK3, ls=1.1)


# ------------------------------------------------------------------ 01 封面
s = new()
tb(s, 0.85, 0.75, 8, 0.3, "赛题二　碳足迹 · 全民绿色生活碳积分与减排指南", 11.5, False, INK3, spc=1)
tb(s, 0.8, 1.55, 8.5, 1.4, "碳　迹", 84, True, INK, ls=1.0)
tb(s, 0.85, 3.12, 8.0, 0.5, "个人碳账本", 26, False, INK2, spc=6)
rule(s, 0.85, 3.86, 5.6, 0.02, INK)
tb(s, 0.85, 4.12, 7.6, 1.3,
   "记录 → 折算 → 看见 → 激励 → 回馈\n一份可核对、可追溯、可离线运行的个人减排记录",
   15, False, INK2, ls=1.6)
seal(s, 9.6, 1.5, 2.6)
tb(s, 9.55, 4.45, 2.8, 0.4, "碳 账 本", 13, False, INK3, align=PP_ALIGN.CENTER, spc=4)
rule(s, 0.85, 6.35, 11.6, 0.01, RULE)
tb(s, 0.85, 6.5, 6, 0.3, "2026 · 河南省高等学校信息技术应用创新大赛", 10.5, False, INK3)
tb(s, 10.4, 6.5, 2.2, 0.3, "汇报 10 分钟", 10.5, False, INK3, align=PP_ALIGN.RIGHT)
notes(s, "开场 15 秒：各位评委好，我们的作品叫「碳迹」，一款跑在 HarmonyOS 上的个人碳账本。"
         "一句话：把每天的低碳行为算清楚、看见、并且换得到。")

# ------------------------------------------------------------------ 02 一页看懂
s = new(); kicker(s, "一页看懂")
title(s, "一个问题，一条闭环，四个创新")
# 左列
tb(s, 0.8, 1.72, 3.4, 0.35, "问题", 12, True, SEAL, spc=3)
tb(s, 0.8, 2.08, 3.35, 1.9, "低碳行为\n算不清、坚持难，\n也换不到。", 20, True, INK, ls=1.4)
tb(s, 0.8, 4.05, 3.3, 2.0, "把「量化—激励—回馈」\n做成一条能走通的闭环。", 12.5, False, INK2, ls=1.55)
rule(s, 4.38, 1.75, 0.012, 4.9, RULE)
# 中列
tb(s, 4.7, 1.72, 3.8, 0.35, "做法", 12, True, SEAL, spc=3)
big_num(s, 4.7, 2.05, "14", "条权威因子，逐条标出处", 3.6, 40)
big_num(s, 4.7, 3.2, "5 + 4", "五项主功能 + 四项创新", 3.6, 40)
big_num(s, 4.7, 4.35, "100%", "数据本地存储、全程离线", 3.6, 40)
rule(s, 8.78, 1.75, 0.012, 4.9, RULE)
# 右列
tb(s, 9.1, 1.72, 3.4, 0.35, "不同", 12, True, SEAL, spc=3)
tb(s, 9.1, 2.08, 3.35, 4.4,
   "不是又一个\n绿色渐变 App。\n\n界面把碳积分还原成\n「记账」：\n纸、墨、细线、宋体、朱印。\n\n视觉改造有量化验收；\n信息架构也有硬规矩：\n新能力只许合并、下沉、替换。",
   12.5, False, INK2, ls=1.5)
footer(s, 2, "一页看懂")
notes(s, "30 秒：先给结论。问题是三件事：算不清、坚持难、换不到；做法是一条闭环加九个功能；"
         "不同之处是界面语言——碳账本，而不是通用模板。")

# ------------------------------------------------------------------ 03 三道坎
s = new(); kicker(s, "选题背景")
title(s, "「双碳」需要公众参与，但公众缺三样东西")
cols = [
    ("算不清", "同一件事，不同口径能差出几倍。\n用户不知道信谁。", "口径必须可追溯"),
    ("坚持难", "今天少开一次车，明天不会\n发生任何变化。缺少即时反馈。", "反馈必须看得见"),
    ("换不到", "减排量停在数字上，兑换不到\n任何真实权益。", "积分必须能落地"),
]
for i, (h, body_txt, tag) in enumerate(cols):
    x = 0.8 + i * 4.0
    tb(s, x, 1.85, 3.6, 0.7, h, 30, True, INK)
    rule(s, x, 2.6, 3.4, 0.012, RULE)
    tb(s, x, 2.78, 3.5, 1.5, body_txt, 14, False, INK2, ls=1.55)
    tb(s, x, 4.55, 3.5, 0.35, tag, 11.5, True, SEAL, spc=2)
tb(s, 0.8, 5.55, 11.6, 0.8, "「碳迹」不是再做一个计算器，而是把这三道坎连成一条路。", 18, True, INK)
footer(s, 3, "选题背景")
notes(s, "35 秒：这三道坎是真实的。算不清是口径问题；坚持难是反馈问题；换不到是闭环缺口。"
         "我们的产品逻辑就是逐一对应。")

# ------------------------------------------------------------------ 04 闭环
s = new(); kicker(s, "设计思路")
title(s, "把「量化—激励—回馈」做成闭环", "五个动作首尾相接，缺一环都不成立")
pic(s, f"{VIS}/loop-naked.png", 5.55, 2.05, h=3.95)
rich(s, 0.8, 1.95, 4.3, 4.4, [
    ("记录", True, INK), "四个类目、十四种行为；拍照只是「确认」",
    ("折算", True, INK), "活动量 × 因子；因子标基准与出处",
    ("看见", True, INK), "树、12 周日历、四条趋势",
    ("激励", True, INK), "积分、徽章、证书",
    ("回馈", True, INK), "上报碳普惠，兑换真实权益",
], 13.5, ls=1.35, gap=10)
footer(s, 4, "设计思路")
notes(s, "35 秒：这条闭环是我们的产品骨架。注意「记录」必须足够轻，「回馈」必须是真的，"
         "否则闭环断在两头。")

# ------------------------------------------------------------------ 05 三个取舍
s = new(); kicker(s, "设计思路")
title(s, "三处关键取舍，决定了后面的架构与界面")
rows = [
    ("01", "数据全部留在本机", "把「单机版」当成隐私优势：全量本地、完全离线；多设备走分布式直连，不经过云端。"),
    ("02", "AI 用来预填，不用来判定", "通用模型分不清新能源车与燃油车；只在高置信度预填，低置信度交给用户确认。"),
    ("03", "每个因子都能追溯到出处", "数值、基准情景、数据出处三行并列；多来源差异保留口径，不取一个数字了事。"),
]
for i, (n, h, t) in enumerate(rows):
    y = 1.8 + i * 1.55
    tb(s, 0.8, y, 0.8, 0.5, n, 14, True, SEAL, spc=1)
    tb(s, 1.45, y - 0.02, 4.0, 0.5, h, 18, True, INK)
    tb(s, 5.6, y, 6.9, 0.9, t, 14, False, INK2, ls=1.45)
    rule(s, 0.8, y + 1.15, 11.6, 0.008, RULE)
footer(s, 5, "设计思路")
notes(s, "40 秒：这三个取舍是我们和同类作品最不一样的地方：本地优先、AI 只做预填、因子可追溯。"
         "它们不是口号，后面架构图会看到对应。")

# ------------------------------------------------------------------ 06 功能地图
s = new(); kicker(s, "功能总览")
title(s, "五项主功能全部实现，四项创新全部落地")
groups = [
    ("主功能", ["低碳行为核算", "可视化与记录查询", "碳积分体系", "双碳科普", "本地数据管理"]),
    ("创新拓展", ["超级终端同步", "端侧 AI 识图", "城市碳普惠接口", "智能服务与分享"]),
    ("鸿蒙延伸", ["桌面服务卡片", "整屏年度报告", "减排凭证"]),
]
for gi, (name, items) in enumerate(groups):
    x = 0.8 + gi * 4.05
    tb(s, x, 1.8, 3.7, 0.4, name, 12, True, SEAL, spc=3)
    rule(s, x, 2.18, 3.65, 0.012, INK)
    for j, it in enumerate(items):
        tb(s, x, 2.35 + j * 0.72, 3.65, 0.5, it, 15, False, INK2, ls=1.2)
        rule(s, x, 2.35 + j * 0.72 + 0.52, 3.65, 0.006, RULE)
tb(s, 0.8, 5.72, 11.8, 0.9,
   "v3.4 收敛信息架构：记录查询从页底区块下沉为独立页，科普十张卡收成一页，"
   "积分「徽章」与「证书」合并为一张卡内分段。", 11, False, INK3, ls=1.5)
footer(s, 6, "功能总览")
notes(s, "25 秒：功能不用逐个念。左边五项是赛题要求，中间四项是创新，右边是鸿蒙延伸。"
         "这一版没有加新功能，而是把「新能力往页底堆」这件事改掉了——"
         "记录查询下沉成独立页，科普十张卡收成一页，积分两张卡合成一张。")

# ------------------------------------------------------------------ 07 记一笔
s = new(); kicker(s, "功能演示 · 记一笔")
title(s, "把一笔碳账记清楚：选、填、算、存", "实测：6 公里步行 → 1.17 kg CO₂e → 117 积分")
phone(s, f"{QI}/05-记一笔-最近记录收口.jpeg", 9.25, 1.7, 4.95, "页尾只留 3 条最近记录 + 右侧「全部 〉」")
rich(s, 0.8, 2.14, 7.5, 4.5, [
    ("选类目：四行账目行，不是四宫格色块", True, INK),
    ("点行为：十四种常见行为，方角标签，选中朱点", True, INK),
    ("填数量与日期：下划线输入，日期默认今天", True, INK),
    ("实时折算：本次减排随输入即时更新", True, INK),
    ("保存入账：写 behavior 与 points 两条键，发放积分", True, INK),
    ("页尾收口：只留 3 条 + 「全部 〉」，全量查询去记录页", True, INK),
], 13.5, ls=1.3, gap=11)
footer(s, 7, "记一笔")
notes(s, "40 秒：这是最高频的页面。四步，输入成本很低。右边这张图是 6 公里步行，"
         "实时算出 1.17 公斤，保存即入账。注意页尾：只留 3 条最近记录和一个「全部 〉」，"
         "筛选和全量列表搬去了记录页——录入页不再随记录变长。")

# ------------------------------------------------------------------ 08 看板
s = new(); kicker(s, "功能演示 · 看板")
title(s, "让「坚持」看得见：一棵树，一张日历，三张同口径的图")
phone(s, f"{SHOT}/10-看板-总览.jpeg", 0.8, 1.75, 4.6, "我的树：树冠密度 = 累计减排")
phone(s, f"{SHOT}/11-看板-日历.jpeg", 3.6, 1.75, 4.6, "12 周日历：连续 5 天、11 天有记录")
rich(s, 6.8, 1.9, 5.8, 4.7, [
    ("树", True, INK), "0 条只有一根芽；10 kg 以上满冠",
    ("日历", True, INK), "12 周 × 7 天，四档色阶 + 连续天数",
    ("粒度", True, INK), "一行账页式分段，不再单占一张卡",
    ("一条口径", True, INK), "日 24 时、周 7 天、月按当月、年 12 月，三图同源",
    ("可查", True, INK), "分类占比每行都能点，带类目进记录页",
], 12.5, ls=1.3, gap=10)
footer(s, 8, "看板")
notes(s, "45 秒：看板是作品的视觉核心。树是「量」的具象化；日历是「坚持」。"
         "这一版把统计粒度从一张卡降成一行分段——它本来就是全页口径；"
         "同时把三张图的区间统一成同一套日历切分，切粒度时三张图一起动，不再互相打架。")

# ------------------------------------------------------------------ 09 记录页
s = new(); kicker(s, "功能演示 · 记录")
title(s, "「分类查询」不挂页底：下沉成一张明细页")
phone(s, f"{QI}/06-记录-全部类目.jpeg", 0.8, 1.62, 4.7, "全部：12 条、合计 21.75 kg")
phone(s, f"{QI}/07-记录-分类查询.jpeg", 3.82, 1.62, 4.7, "出行：5 条、合计 8.26 kg，进入即预选")
tb(s, 6.95, 5.75, 5.6, 0.9, "赛题原文：以三图展示趋势，支持分类查询历史记录。\n"
   "查询因此落在图例与这张页上，而不是页底再加一块列表。", 10.5, False, SEAL, ls=1.5)
rich(s, 6.95, 1.8, 5.65, 4.0, [
    ("五等分账页签", True, INK), "全部 + 四类，选中项朱砂下划线",
    ("表头即合计", True, INK), "切换类目立即重算条数与 kg",
    ("两个入口", True, INK), "看板图例任一行、记一笔「全部 〉」",
    ("就地删除", True, INK), "删一条，合计与看板同步刷新",
    ("三种落法", True, INK), "合并 / 下沉 / 替换——新能力不许接在页底",
], 12.5, ls=1.3, gap=11)
footer(s, 9, "记录")
notes(s, "40 秒：赛题把「分类查询历史记录」挂在看板这一条下面。我们上一版把筛选项和全量列表"
         "直接垒在保存按钮下面，页面就越用越长。这一版把它下沉成一张整屏明细页："
         "五等分账页签、表头给合计、每行可删；入口只有两个——看板图例的任意一行，"
         "或者记一笔页尾的「全部 〉」。这条规矩我们写进了设计文档：新能力只允许合并、下沉、替换三种落法。")

# ------------------------------------------------------------------ 10 积分
s = new(); kicker(s, "功能演示 · 积分与徽章")
title(s, "从「数字」到「权益」：积分必须能落地")
phone(s, f"{QI}/08-积分-徽章证书合一.jpeg", 0.8, 1.7, 4.6, "徽章与证书合一：卡内分「可兑换 / 已获得」")
phone(s, f"{QI}/09-积分-已获得证书.jpeg", 3.6, 1.7, 4.6, "已获得：证书印成票面，流水同步 −300")
rich(s, 6.75, 1.86, 5.85, 4.7, [
    ("累计 2,175 分", True, SEAL), "兑换植树证书 300 分，余额 1,875 分",
    ("100 积分 / kg", True, INK), "每减排 1 kg 得 100 分",
    ("归属态", True, INK), "兑换写 owned:rewards；已拥有不再扣分",
    ("证书是票面", True, INK), "抬头、授予人、累计减排、落款「本机生成」",
    ("四枚勋章", True, INK), "100 / 300 / 500 / 1000 分各解锁一枚",
    ("能带走", True, INK), "徽章与证书可截图保存，不依赖云端",
], 12.5, ls=1.28, gap=8)
footer(s, 10, "积分与徽章")
notes(s, "35 秒：积分不是游戏币。这一版给奖励补了归属态：兑换会写一条 owned 记录，"
         "已拥有的按钮变「已拥有」，不会再扣一次分；证书按昵称和累计减排印成一张票面，能截图带走。"
         "「攒分 → 兑换 → 拥有」现在在同一屏里连成一条线。")

# ------------------------------------------------------------------ 11 科普与我的
s = new(); kicker(s, "功能演示 · 科普与我的")
title(s, "内容与数据：都能带走，都不出设备")
phone(s, f"{QI}/12-科普-十卡收成一页.jpeg", 0.8, 1.7, 4.55, "8 篇收成一页账页，行内展开正文")
phone(s, f"{SHOT}/41-我的-同步与数据.jpeg", 3.6, 1.7, 4.55, "同步面板、AI 自检、JSON 备份与 CSV 导出")
rich(s, 6.75, 1.9, 5.85, 4.6, [
    ("科普 8 篇", True, INK), "政策 / 概念 / 数据 / 技巧",
    ("一页八行", True, INK), "行内展开、箭头转 90°；标签降为裸芯片",
    ("同步可见", True, INK), "本机、可信设备、冲突数",
    ("AI 自检", True, INK), "验证模型可加载、能输出索引",
    ("数据可携带", True, INK), "JSON 备份、CSV 报表、清空",
    ("全部本地", True, SEAL), "默认不上传云端",
], 12.5, ls=1.3, gap=9)
footer(s, 11, "科普与我的")
notes(s, "30 秒：科普解决「懂不懂」，我的解决「数据归谁」。科普原本八篇各占一张卡，"
         "翻起来像一摞便签；现在收成一页账页八行，点一行就地展开。备份是 JSON，报表是 CSV。")

# ------------------------------------------------------------------ 11 创新1 同步
s = new(); kicker(s, "创新拓展 1")
title(s, "超级终端同步：数据在设备之间直接走")
rich(s, 0.8, 1.95, 6.6, 4.4, [
    ("分布式键值库 + 分布式设备管理", True, INK),
    "不经过云端；同一账号、完成认证、同一局域网即可同步",
    ("信封 { payload, ts, origin }", True, INK),
    "逐键比较时间戳，较新者胜出；本地拒绝远端时冲突计数 +1",
    ("积分流水只增不改", True, INK),
    "追加型数据天然免冲突；行为记录与档案走时间戳合并",
    ("家庭 ID", True, INK),
    "同一家庭 ID 的设备同步后自然形成合并视图",
], 13.5, ls=1.4, gap=10)
pic(s, f"{VIS}/sync.png", 7.35, 1.9, w=5.35)
tb(s, 7.35, 5.35, 5.45, 0.9, "写入用时间戳信封；积分流水只增不改，\n从数据模型上消灭大部分冲突。", 9.5, False, INK3, ls=1.2)
footer(s, 11, "创新 1 · 分布式同步")
notes(s, "35 秒：同步的难点不是传输，是冲突。我们用时间戳信封，积分流水设计成只增不改，"
         "从数据模型上消灭大部分冲突。左边这张是结构示意；模拟器没有软总线，"
         "所以真机上的同步面板会显示「未获取到设备」，我们如实展示。")

# ------------------------------------------------------------------ 12 创新2 AI
s = new(); kicker(s, "创新拓展 2")
title(s, "端侧 AI：图片不出设备，只做「预填」")
pic(s, f"{VIS}/ai-naked.png", 0.75, 1.95, w=7.9)
rich(s, 8.5, 1.9, 4.1, 4.5, [
    ("视觉", True, INK), "MindSpore Lite + MobileNetV2，模型随包内置",
    ("文字", True, INK), "Core Vision Kit 端侧 OCR，关键词映射",
    ("融合", True, INK), "一致提升置信度，冲突取高并降权",
    ("边界", True, SEAL), "仅高置信预填；标定表为空时如实说明",
], 12.5, ls=1.35, gap=10)
footer(s, 12, "创新 2 · 端侧 AI")
notes(s, "40 秒：两路 AI：一路看图，一路读字，按置信度融合。关键不是炫技，是隐私——图片不出设备。"
         "第二关键是克制：只预填，不判定。")

# ------------------------------------------------------------------ 13 创新3 平台
s = new(); kicker(s, "创新拓展 3")
title(s, "城市碳普惠：五个环节，按真实接口的语义实现")
steps = ["绑定", "上报", "查询", "兑换", "订单"]
for i, st in enumerate(steps):
    x = 0.8 + i * 2.4
    tb(s, x, 1.95, 2.2, 0.5, f"0{i+1}", 12, True, SEAL, spc=2)
    tb(s, x, 2.35, 2.2, 0.6, st, 22, True, INK)
    if i < 4:
        tb(s, x + 1.85, 2.45, 0.5, 0.4, "→", 18, False, INK4)
rule(s, 0.8, 3.15, 11.7, 0.012, INK)
rich(s, 0.8, 3.4, 7.2, 3.0, [
    ("异步与延迟", True, INK), "上报 300–900 ms，返回请求号",
    ("错误码与状态", True, INK), "账户冻结、余额不足、库存为零都有明确分支",
    ("幂等", True, INK), "同一请求号不重复入账",
    ("库存原子扣减", True, INK), "并发兑换不会超卖",
], 13.5, ls=1.35, gap=10)
tb(s, 8.4, 3.4, 4.0, 2.6, "业务层只依赖接口契约。\n未来对接真实平台，\n替换通信层即可，\n业务逻辑一行不改。", 15, False, INK2, ls=1.55)
footer(s, 13, "创新 3 · 碳普惠接口")
notes(s, "30 秒：碳普惠不是一个按钮。绑定、上报、查询、兑换、订单五个环节，"
         "每个环节都有真实世界的失败分支：余额不足、库存为零、重复请求。")

# ------------------------------------------------------------------ 14 创新4 智能服务
s = new(); kicker(s, "创新拓展 4")
title(s, "智能服务与减排凭证：让成果可传播")
phone(s, f"{SHOT}/15-看板-分享凭证.jpeg", 0.8, 1.75, 4.85, "减排凭证：小票式排版 + 朱印骑缝")
rich(s, 4.9, 1.95, 3.9, 4.4, [
    ("短板优先", True, INK), "先推今天没记录的类目，再按历史条数排序",
    ("可解释建议", True, INK), "每条建议对应一个数据事实",
    ("凭证而非海报", True, INK), "抬头、双线、明细、落款、骑缝章",
    ("同形印章", True, INK), "确定性种子，屏幕与分享图逐像素同形",
], 12.5, ls=1.35, gap=10)
tb(s, 8.95, 2.0, 3.6, 3.8, "分享不是加一个按钮，\n而是换一套语言：\n\n海报是营销，\n凭证是证据。", 16, False, INK2, ls=1.55)
footer(s, 14, "创新 4 · 智能服务")
notes(s, "30 秒：任务推荐用短板优先，建议必须能解释。分享卡我们改成了「减排凭证」——"
         "海报是营销，凭证是证据。")

# ------------------------------------------------------------------ 15 视觉体系
s = new(); kicker(s, "视觉体系")
title(s, "为什么推翻 v2：可替换的界面，就是可替换的作品")
s.shapes.add_picture(f"{ASSET}/改造前后对比-v3账本.png", Inches(0.8), Inches(1.72), Inches(8.1), Inches(4.9))
rich(s, 9.15, 1.9, 3.5, 4.6, [
    ("不是配色问题", True, SEAL), "是模板感：渐变主卡 + 圆角卡片 + 胶囊标签",
    ("碳账本", True, INK), "纸、墨、细线、宋体、朱印",
    ("三个签名", True, INK), "双线表头 / 引导点线 / -5° 朱印",
    ("减法", True, INK), "圆角 2、阴影全透明、图表去渐变",
], 12, ls=1.35, gap=9)
footer(s, 15, "视觉体系")
notes(s, "45 秒：这是最重要的一页。v2 不丑，但可替换：换成蓝色、换掉 logo 依然成立。"
         "v3 把碳积分还原成记账，用纸墨和印章。左边六组对比可以逐屏看。")

# ------------------------------------------------------------------ 16 设计细节
s = new(); kicker(s, "视觉体系 · 细节")
title(s, "把「不完美」做成可复现的参数")
s.shapes.add_picture(f"{ASSET}/截图/v3/11-印章抖动-放大.png", Inches(0.9), Inches(1.85), Inches(3.2), Inches(3.8))
rich(s, 4.6, 1.9, 4.3, 4.8, [
    ("两遍墨", True, INK), "第一遍定形，第二遍在形上抖 0.55×偏移，像余墨",
    ("平移 + 微倾斜", True, INK), "边是直的，只是位置略偏；拐角自然错开",
    ("确定性种子", True, INK), "种子取自印章文字，不用随机数",
    ("等比缩放", True, INK), "所有尺寸随 sealSize 等比，大印只改一个数",
], 12.5, ls=1.35, gap=9)
tb(s, 9.1, 1.85, 3.5, 4.3, "峰值偏离\n0.800 vp\n\n单边倾斜\n0.370 vp\n\n同 seed 32 个数\n完全一致", 14, False, INK2, ls=1.5)
footer(s, 16, "视觉体系 · 细节")
notes(s, "30 秒：这枚章不是贴图，是 Canvas 画的。两遍墨、平移加微倾斜、确定性种子。"
         "好处是屏幕、截图、分享图逐像素同形。")

# ------------------------------------------------------------------ 17 架构
s = new(); kicker(s, "系统架构")
title(s, "四层架构：界面不碰系统能力，业务不依赖存储")
pic(s, f"{VIS}/architecture-naked.png", 0.65, 1.9, h=4.92)
rich(s, 8.9, 1.95, 3.6, 4.6, [
    ("表现", True, INK), "五页签 + 记录页 + 年报/凭证",
    ("业务", True, INK), "核算、积分、任务、碳普惠",
    ("数据", True, INK), "仓储 + 分布式 KV",
    ("能力", True, INK), "存储、推理、识别、快照",
], 11, ls=1.25, gap=8, bullet=None)
footer(s, 17, "系统架构")
notes(s, "40 秒：四层。最关键的是数据层：我们没用关系型数据库，因为同步要复用分布式 KV，"
         "否则后期要重写。这是一个在项目第一天就必须做的决定。")

# ------------------------------------------------------------------ 18 技术选型
s = new(); kicker(s, "技术选型")
title(s, "关键选型：为什么是 KV、mpchart、MindSpore Lite")
rows = [
    ("存储", "分布式 KV", "同步是存储的天然属性；取全量 + 内存筛选足够个人级数据"),
    ("图表", "mpchart", "纯 ArkTS 源码、可离线、可读可改；修过单色标变黑等三个坑"),
    ("推理", "MindSpore Lite", "模型随包内置，图片不出设备；代价是能力有限，所以只做预填"),
    ("字体", "Noto Serif 子集", "SIL OFL 可打包；546 KB、1176 字，用户输入走系统字体"),
]
for i, (k, v, why) in enumerate(rows):
    y = 1.8 + i * 1.22
    tb(s, 0.8, y, 1.6, 0.4, k, 11, True, SEAL, spc=2)
    tb(s, 2.3, y - 0.04, 3.2, 0.45, v, 17, True, INK)
    tb(s, 5.6, y, 6.6, 0.75, why, 12.5, False, INK2, ls=1.35)
    rule(s, 0.8, y + 0.9, 11.6, 0.008, RULE)
footer(s, 18, "技术选型")
notes(s, "35 秒：四个选型各有代价。KV 换来同步但放弃 SQL；mpchart 可以改源码但要自己填坑；"
         "端侧推理保隐私但能力有限；字体子集可控但不能用于用户输入。")

# ------------------------------------------------------------------ 19 因子
s = new(); kicker(s, "答辩重点")
title(s, "每个数字都能追溯：14 条因子，逐条标出处")
tb(s, 0.8, 1.8, 11.8, 0.6, "ER = AD × ( EF基准 - EF实际 )", 26, True, INK)
tb(s, 0.8, 2.42, 6.0, 0.3, "减排量 = 活动量 × 基准与实际排放因子之差", 11, False, INK3)
src = [
    ("生态环境部 / 国家统计局", "2023 年电力二氧化碳排放因子公告（2025 年第 47 号）", "河南 0.5897 kgCO₂/kWh"),
    ("CPCD", "中国产品全生命周期温室气体排放系数库（2022–2023）", "出行、回收塑料"),
    ("DEFRA 2025", "英国温室气体换算因子", "回收纸/铝/衣物、供水"),
    ("中科院 × WWF / FAO", "中国城市餐饮食物浪费报告（2018）/ 2013", "光盘行动"),
]
for i, (org, what, use) in enumerate(src):
    y = 3.0 + i * 0.92
    tb(s, 0.8, y, 3.5, 0.4, org, 12.5, True, INK)
    tb(s, 4.3, y, 4.9, 0.6, what, 11, False, INK2, ls=1.2)
    tb(s, 9.5, y, 2.9, 0.4, use, 10.5, False, SEAL, ls=1.2)
    rule(s, 0.8, y + 0.72, 11.6, 0.008, RULE)
footer(s, 19, "因子库")
notes(s, "35 秒：这一页是答辩重点。公式是差值；每个因子有出处；中国没有官方因子的，"
         "用 DEFRA 并标注英国口径。我们不取一个数字了事。")

# ------------------------------------------------------------------ 20 测试
s = new(); kicker(s, "测试与验证")
title(s, "55 项断言、24 个图标、五层测试：用可复现代替「应该可以」")
big_num(s, 0.8, 1.85, "55", "项纯逻辑断言，0 失败", 2.4, 54)
big_num(s, 3.5, 1.85, "24", "个图标，视觉重量极差 0.34%", 2.6, 54)
big_num(s, 6.4, 1.85, "5", "层测试：构建 → 逻辑 → 功能 → 视觉 → 能力", 4.6, 54)
rule(s, 0.8, 3.55, 11.6, 0.012, INK)
rich(s, 0.8, 3.8, 6.6, 2.8, [
    ("L1 构建", True, INK), "hvigor assembleHap 成功产出 HAP",
    ("L2 逻辑", True, INK), "因子算术、任务、建议、工具、印章抖动",
    ("L3 功能", True, INK), "19 条用例：录入、看板、记录、积分、科普、数据",
    ("L4 视觉", True, INK), "构建→安装→逐页截图（含空态与记录页）；图标裁切自检",
    ("L5 能力", True, INK), "分布式与端侧 AI 待真机验证",
], 12, ls=1.25, gap=7)
tb(s, 7.9, 3.8, 4.5, 2.6, "修过，才算测过：\n\n环形图 2841% / 按钮胶囊\n柱子纯黑 / 印章不同形\n@Builder 停在首帧\nPath 尺寸 1/3.67", 12, False, INK2, ls=1.45)
footer(s, 20, "测试与验证")
notes(s, "35 秒：测试分五层。最值得说的是 55 项断言和视觉回归——每次改样式都能一条命令重拍，"
         "人工只做判断。这些缺陷都是真踩过的。")

# ------------------------------------------------------------------ 21 边界
s = new(); kicker(s, "能力边界")
title(s, "如实说明：哪些已完成，哪些还需真机")
rows = [
    ("多设备同步", "逻辑与界面完成；模拟器无软总线，待两台真机端到端验证"),
    ("端侧 AI", "推理可自检；索引→类目标定表为空，视觉通路暂不产出建议"),
    ("碳普惠", "本地模拟，保留真实语义；平台未对个人开发者开放"),
    ("深色模式", "未实现；纸墨反转需要把颜色常量改为资源引用"),
]
for i, (k, v) in enumerate(rows):
    y = 1.85 + i * 1.08
    tb(s, 0.8, y, 2.8, 0.4, k, 13, True, INK)
    tb(s, 3.7, y, 8.7, 0.8, v, 13, False, INK2, ls=1.35)
    rule(s, 0.8, y + 0.82, 11.6, 0.008, RULE)
tb(s, 0.8, 6.25, 11.6, 0.45, "不用「应该可以」代替结论；边界写清楚，反而更容易被相信。", 14, True, SEAL)
footer(s, 21, "能力边界")
notes(s, "30 秒：这些限制我们主动说。同步和 AI 需要真机，碳普惠是模拟的，深色模式没做。"
         "把边界写清楚，比夸大更可信。")

# ------------------------------------------------------------------ 22 结尾
s = new()
tb(s, 0.85, 1.1, 8, 0.3, f"{TOTAL} / {TOTAL}　·　谢谢", 11, False, INK3, spc=2)
tb(s, 0.8, 1.8, 9.6, 1.2, "把每一笔低碳，\n都记成看得见的改变。", 40, True, INK, ls=1.45)
rule(s, 0.85, 4.0, 5.6, 0.02, INK)
tb(s, 0.85, 4.25, 8.4, 1.2, "碳迹 · 个人碳账本\nHarmonyOS · ArkTS / ArkUI · API 12", 14, False, INK2, ls=1.6)
seal(s, 9.9, 1.7, 2.2)
tb(s, 0.85, 6.4, 11.5, 0.3, "数据全部保存在本机　·　不上传云端　·　可离线演示", 10.5, False, INK3, spc=1)
notes(s, "20 秒：最后一句话：把每一笔低碳，都记成看得见的改变。谢谢。")

# 文档属性
cp = prs.core_properties
cp.author = ""
cp.last_modified_by = ""
cp.title = "碳迹 · 汇报演示文稿"
cp.subject = "赛题二 碳足迹·全民绿色生活碳积分与减排指南"
cp.comments = ""
cp.keywords = ""

os.makedirs(os.path.dirname(OUT), exist_ok=True)
prs.save(OUT)
print("saved", os.path.abspath(OUT), "slides", len(prs.slides.__iter__.__self__._sldIdLst))
