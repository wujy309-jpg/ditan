#!/usr/bin/env python3
"""生成《碳迹 —— 设计方案》.docx（v3 碳账本版）。

排版硬约束（大赛要求）：
  · 正文宋体、小四（12pt）、1.5 倍行距
  · 含设计思路、系统架构、技术选型、测试方案
运行：python3 tools/docs/make_design_doc_v3.py
"""
import os
from docx import Document
from docx.enum.section import WD_SECTION
from docx.enum.table import WD_ALIGN_VERTICAL, WD_TABLE_ALIGNMENT
from docx.enum.text import WD_ALIGN_PARAGRAPH, WD_LINE_SPACING
from docx.enum.style import WD_STYLE_TYPE
from docx.oxml import OxmlElement
from docx.oxml.ns import qn
from docx.shared import Cm, Pt, RGBColor
from PIL import Image

OUT = "交付物/设计方案_碳迹.docx"
SHOT = "素材/截图/v3.3"
QI = "素材/截图/质量改进"
ASSET = "素材"
VIS = "/tmp/carbon-visuals"

INK = RGBColor(0x20, 0x1D, 0x17)
INK2 = RGBColor(0x4C, 0x46, 0x3A)
INK3 = RGBColor(0x85, 0x7C, 0x6A)
SEAL = RGBColor(0xAB, 0x3A, 0x28)
RULE = "B5AC98"
PAPER = "F2EDE1"

FONT = "宋体"
BODY = Pt(12)
LS = 1.5
TEXT_W = Cm(16.4)


# ---------------------------------------------------------------- 基础工具
def set_run(run, size=BODY, bold=False, color=INK, font=FONT, italic=False):
    run.font.name = font
    run.font.size = size
    run.font.bold = bold
    run.font.italic = italic
    run.font.color.rgb = color
    rpr = run._element.get_or_add_rPr()
    rf = rpr.find(qn("w:rFonts"))
    if rf is None:
        rf = OxmlElement("w:rFonts")
        rpr.append(rf)
    for a in ("w:ascii", "w:hAnsi", "w:eastAsia", "w:cs"):
        rf.set(qn(a), font)


def fmt_para(p, first_indent=True, before=0, after=0, align=None, ls=LS,
             keep_next=False):
    pf = p.paragraph_format
    pf.line_spacing = ls
    pf.space_before = Pt(before)
    pf.space_after = Pt(after)
    if first_indent:
        pf.first_line_indent = Pt(24)     # 小四两字 = 24pt
    if align is not None:
        p.alignment = align
    pf.keep_with_next = keep_next
    return p


def add_rich(p, text, size=BODY, color=INK):
    """支持 **加粗** 与 `等宽` 两种行内标记。"""
    import re
    for seg in re.split(r"(\*\*.+?\*\*|`.+?`)", text):
        if not seg:
            continue
        if seg.startswith("**") and seg.endswith("**"):
            r = p.add_run(seg[2:-2]); set_run(r, size=size, bold=True, color=color)
        elif seg.startswith("`") and seg.endswith("`"):
            r = p.add_run(seg[1:-1]); set_run(r, size=size, color=INK2, font="Consolas")
        else:
            r = p.add_run(seg); set_run(r, size=size, color=color)


def body(text, indent=True, after=0, before=0, align=WD_ALIGN_PARAGRAPH.JUSTIFY):
    p = doc.add_paragraph()
    fmt_para(p, first_indent=indent, before=before, after=after, align=align)
    add_rich(p, text)
    return p


def bullet(text, size=BODY):
    p = doc.add_paragraph(style="List Bullet")
    fmt_para(p, first_indent=False, after=2, align=WD_ALIGN_PARAGRAPH.JUSTIFY)
    p.paragraph_format.left_indent = Cm(0.74)
    p.paragraph_format.first_line_indent = Cm(-0.37)
    add_rich(p, text, size=size)


def _bottom_border(p, sz=12, color=RULE, double=False):
    pPr = p._p.get_or_add_pPr()
    pbdr = pPr.find(qn("w:pBdr"))
    if pbdr is None:
        pbdr = OxmlElement("w:pBdr"); pPr.append(pbdr)
    b = OxmlElement("w:bottom")
    b.set(qn("w:val"), "double" if double else "single")
    b.set(qn("w:sz"), str(sz))
    b.set(qn("w:space"), "4")
    b.set(qn("w:color"), color)
    pbdr.append(b)


def h1(text, front_matter=False):
    doc.add_paragraph()
    p = doc.add_paragraph(style="FrontHeading" if front_matter else "Heading 1")
    fmt_para(p, first_indent=False, before=6, after=10, keep_next=True)
    r = p.add_run(text)
    set_run(r, size=Pt(16), bold=True, color=INK)
    _bottom_border(p, sz=14, color="201D17", double=True)
    return p


def h2(text):
    p = doc.add_paragraph(style="Heading 2")
    fmt_para(p, first_indent=False, before=14, after=6, keep_next=True)
    r = p.add_run(text)
    set_run(r, size=Pt(14), bold=True, color=INK)
    return p


def h3(text):
    p = doc.add_paragraph(style="Heading 3")
    fmt_para(p, first_indent=False, before=10, after=4, keep_next=True)
    r = p.add_run(text)
    set_run(r, size=BODY, bold=True, color=INK)
    return p


def caption(text):
    p = doc.add_paragraph()
    fmt_para(p, first_indent=False, before=3, after=12, align=WD_ALIGN_PARAGRAPH.CENTER, ls=1.0)
    r = p.add_run(text)
    set_run(r, size=Pt(10.5), color=INK3)


def figure(path, cap, width_cm=7.0):
    p = doc.add_paragraph()
    fmt_para(p, first_indent=False, before=6, after=2, align=WD_ALIGN_PARAGRAPH.CENTER, ls=1.0)
    p.add_run().add_picture(path, width=Cm(width_cm))
    caption(cap)


def figure_pair(items, w_cm=7.2):
    t = doc.add_table(rows=2, cols=len(items))
    t.alignment = WD_TABLE_ALIGNMENT.CENTER
    t.autofit = False
    for i, (path, cap) in enumerate(items):
        cell = t.cell(0, i)
        cell.width = Cm(w_cm)
        p = cell.paragraphs[0]
        fmt_para(p, first_indent=False, align=WD_ALIGN_PARAGRAPH.CENTER, ls=1.0, after=2)
        p.add_run().add_picture(path, width=Cm(w_cm))
        p2 = t.cell(1, i).paragraphs[0]
        fmt_para(p2, first_indent=False, align=WD_ALIGN_PARAGRAPH.CENTER, ls=1.15, after=8)
        r = p2.add_run(cap)
        set_run(r, size=Pt(9.5), color=INK3)
    set_table_borders(t, color="D6CDBA", sz=0)


def shade(cell, color):
    tcPr = cell._tc.get_or_add_tcPr()
    shd = OxmlElement("w:shd")
    shd.set(qn("w:val"), "clear"); shd.set(qn("w:color"), "auto"); shd.set(qn("w:fill"), color)
    tcPr.append(shd)


def set_table_borders(t, color=RULE, sz=4):
    tbl = t._tbl
    tblPr = tbl.tblPr
    borders = OxmlElement("w:tblBorders")
    for edge in ("top", "left", "bottom", "right", "insideH", "insideV"):
        e = OxmlElement(f"w:{edge}")
        e.set(qn("w:val"), "single" if sz else "nil")
        e.set(qn("w:sz"), str(sz))
        e.set(qn("w:color"), color)
        borders.append(e)
    tblPr.append(borders)


def table(headers, rows, widths, cap=None, fs=Pt(10.5), aligns=None):
    t = doc.add_table(rows=1, cols=len(headers))
    t.alignment = WD_TABLE_ALIGNMENT.CENTER
    t.autofit = False
    set_table_borders(t)
    for i, w in enumerate(widths):
        t.columns[i].width = Cm(w)
    tblPr = t._tbl.tblPr
    layout = tblPr.find(qn("w:tblLayout"))
    if layout is None:
        layout = OxmlElement("w:tblLayout"); tblPr.append(layout)
    layout.set(qn("w:type"), "fixed")
    tw = tblPr.find(qn("w:tblW"))
    if tw is None:
        tw = OxmlElement("w:tblW"); tblPr.append(tw)
    tw.set(qn("w:type"), "dxa"); tw.set(qn("w:w"), str(int(sum(widths) * 567)))
    hdr = t.rows[0]
    trPr = hdr._tr.get_or_add_trPr()
    th = OxmlElement("w:tblHeader"); th.set(qn("w:val"), "true"); trPr.append(th)
    for i, h in enumerate(headers):
        c = hdr.cells[i]; c.width = Cm(widths[i]); shade(c, PAPER)
        p = c.paragraphs[0]
        fmt_para(p, first_indent=False, align=WD_ALIGN_PARAGRAPH.CENTER, ls=1.15, before=2, after=2)
        r = p.add_run(h); set_run(r, size=fs, bold=True)
        c.vertical_alignment = WD_ALIGN_VERTICAL.CENTER
    for row in rows:
        cells = t.add_row().cells
        for i, val in enumerate(row):
            cells[i].width = Cm(widths[i])
            p = cells[i].paragraphs[0]
            al = (aligns[i] if aligns else (WD_ALIGN_PARAGRAPH.LEFT if i == 0 else WD_ALIGN_PARAGRAPH.LEFT))
            fmt_para(p, first_indent=False, align=al, ls=1.15, before=1, after=1)
            add_rich(p, str(val), size=fs)
            cells[i].vertical_alignment = WD_ALIGN_VERTICAL.CENTER
    if cap:
        caption(cap)
    else:
        doc.add_paragraph()


def callout(title, text):
    t = doc.add_table(rows=1, cols=1)
    t.alignment = WD_TABLE_ALIGNMENT.CENTER
    set_table_borders(t, color="D6CDBA", sz=4)
    c = t.cell(0, 0); c.width = Cm(16.2); shade(c, "FBF8F1")
    p = c.paragraphs[0]
    fmt_para(p, first_indent=False, ls=1.4, before=4, after=2)
    r = p.add_run(title); set_run(r, size=Pt(11), bold=True, color=SEAL)
    p2 = c.add_paragraph()
    fmt_para(p2, first_indent=False, ls=1.4, before=0, after=4)
    add_rich(p2, text, size=Pt(10.5), color=INK2)


def add_field(paragraph, instr, placeholder=""):
    r = paragraph.add_run()
    fld = OxmlElement("w:fldChar"); fld.set(qn("w:fldCharType"), "begin")
    r._r.append(fld)
    r2 = paragraph.add_run()
    it = OxmlElement("w:instrText"); it.set(qn("xml:space"), "preserve"); it.text = instr
    r2._r.append(it)
    r3 = paragraph.add_run()
    sep = OxmlElement("w:fldChar"); sep.set(qn("w:fldCharType"), "separate")
    r3._r.append(sep)
    r4 = paragraph.add_run(placeholder); set_run(r4, size=Pt(10.5), color=INK3)
    r5 = paragraph.add_run()
    end = OxmlElement("w:fldChar"); end.set(qn("w:fldCharType"), "end")
    r5._r.append(end)


# ---------------------------------------------------------------- 文档骨架
doc = Document()
sec = doc.sections[0]
sec.page_width, sec.page_height = Cm(21.0), Cm(29.7)
sec.top_margin = Cm(2.4); sec.bottom_margin = Cm(2.4)
sec.left_margin = Cm(2.3); sec.right_margin = Cm(2.3)

normal = doc.styles["Normal"]
normal.font.name = FONT
normal.font.size = BODY
normal.font.color.rgb = INK
normal.element.rPr.rFonts.set(qn("w:eastAsia"), FONT)
normal.paragraph_format.line_spacing = LS
normal.paragraph_format.space_before = Pt(0)
normal.paragraph_format.space_after = Pt(0)
front = doc.styles.add_style("FrontHeading", WD_STYLE_TYPE.PARAGRAPH)
front.base_style = doc.styles["Normal"]
front.font.name = FONT; front.font.size = Pt(16); front.font.bold = True
front.font.color.rgb = INK
front.element.rPr.rFonts.set(qn("w:eastAsia"), FONT)
for nm, sz in (("Heading 1", 16), ("Heading 2", 14), ("Heading 3", 12)):
    st = doc.styles[nm]
    st.font.name = FONT
    st.font.size = Pt(sz)
    st.font.bold = True
    st.font.italic = False
    st.font.color.rgb = INK
    st.element.rPr.rFonts.set(qn("w:eastAsia"), FONT)

# 页眉页脚
hdr = sec.header
hp = hdr.paragraphs[0]
fmt_para(hp, first_indent=False, align=WD_ALIGN_PARAGRAPH.LEFT, ls=1.0)
r = hp.add_run("碳迹 · 设计方案　　　　　　　　　　　　　　　　　　赛题二 · 碳足迹·全民绿色生活碳积分与减排指南")
set_run(r, size=Pt(8.5), color=INK3)
_bottom_border(hp, sz=4, color="D6CDBA")

ftr = sec.footer
fp = ftr.paragraphs[0]
fmt_para(fp, first_indent=False, align=WD_ALIGN_PARAGRAPH.CENTER, ls=1.0)
r = fp.add_run("— "); set_run(r, size=Pt(9), color=INK3)
add_field(fp, " PAGE ", "1")
r = fp.add_run(" —"); set_run(r, size=Pt(9), color=INK3)

# 封面
for _ in range(3):
    doc.add_paragraph()
p = doc.add_paragraph(); fmt_para(p, first_indent=False, align=WD_ALIGN_PARAGRAPH.LEFT, ls=1.0, after=4)
r = p.add_run("赛题二　碳足迹 · 全民绿色生活碳积分与减排指南")
set_run(r, size=Pt(12), color=INK2)

p = doc.add_paragraph(); fmt_para(p, first_indent=False, align=WD_ALIGN_PARAGRAPH.LEFT, ls=1.0, before=30, after=6)
r = p.add_run("碳  迹"); set_run(r, size=Pt(54), bold=True)
p = doc.add_paragraph(); fmt_para(p, first_indent=False, ls=1.0, after=10)
r = p.add_run("个人碳账本 · 设计说明书"); set_run(r, size=Pt(20), color=INK2)

p = doc.add_paragraph(); fmt_para(p, first_indent=False, ls=1.0, after=4)
r = p.add_run("一份可核对、可追溯、可离线运行的个人减排记录")
set_run(r, size=Pt(12), color=INK3)
_bottom_border(p, sz=12, color="201D17")

for _ in range(8):
    doc.add_paragraph()
# 封面印章
p = doc.add_paragraph(); fmt_para(p, first_indent=False, align=WD_ALIGN_PARAGRAPH.RIGHT, ls=1.0)
p.add_run().add_picture(f"{VIS}/seal.png", width=Cm(3.4))

for _ in range(2):
    doc.add_paragraph()
info = table(
    ["项目", "内容"],
    [["作品名称", "碳迹 · 个人碳账本"],
     ["运行平台", "HarmonyOS（ArkTS + ArkUI，API 12）"],
     ["文档版本", "v3.4　2026-11"],
     ["文档性质", "参赛设计说明书"]],
    [3.2, 11.0], fs=Pt(10.5))
doc.add_page_break()

# 摘要
h1("摘　要", front_matter=True)
body("「碳迹」是一款运行在 HarmonyOS 上的个人碳账本：它把步行、骑行、公交地铁、节水节电、"
     "旧物回收与光盘行动等日常行为，按内置的权威排放因子折算为可比较的减排量，"
     "再通过数据可视化、碳积分、城市碳普惠权益与社交分享，把「减碳」变成一件看得见、"
     "算得清、换得到的事。")
body("作品完整实现了赛题要求的五项主要功能与四项创新拓展，并额外实现了鸿蒙桌面服务卡片"
     "与整屏年度报告。技术上，数据层建立在分布式键值库之上，为超级终端多设备同步预留通道；"
     "端侧 AI 采用「视觉 + 文字」双通路，图片全程不出设备；碳普惠平台按真实接口的异步、"
     "错误码、库存与幂等语义实现，未来替换通信层即可对接真实平台。")
body("界面是本作品区别于同类作品的重点。我们没有沿用「渐变主卡 + 圆角卡片流 + 胶囊标签」"
     "这套通用模板，而是把碳积分还原为「记账」，用纸、墨、细线、宋体与朱印重建了一套"
     "只属于这个产品的视觉语言，并在 v3.2 中为印章加入确定性的手绘抖动。"
     "这套改造不是审美偏好，而是有可量化验收标准的工程结果：正文全部宋体小四、1.5 倍行距；"
     "逻辑断言 55 项全绿；五个页签、记录页、年报与凭证均经模拟器逐页截图核验。"
     "v3.4 又在视觉之上收敛了一层信息架构：一屏一主题，新能力只允许「合并、下沉、替换」三种落法。")
body("本说明书依次说明设计思路、系统架构、技术选型、功能实现、测试方案、因子库来源、"
     "部署方式与能力边界。所有关键数字均可由随附工程、测试脚本与截图复现。")
callout("一句话",
        "把每一个数字都算清楚，把每一个来源都标明白，把每一点能力边界都如实说明。")

# 目录
doc.add_page_break()
h1("目　录", front_matter=True)
p = doc.add_paragraph(); fmt_para(p, first_indent=False, ls=1.5)
add_field(p, r'TOC \o "1-2" \h \z \u', "（在 Word 中右键「更新域」生成目录）")

settings = doc.settings.element
uf = OxmlElement("w:updateFields"); uf.set(qn("w:val"), "true"); settings.append(uf)

# ================================================================ 一、设计思路
h1("一、设计思路")

h2("1.1 问题：三件事让「低碳」停在口号上")
body("「双碳」目标提出之后，公众参与被反复强调，但落到个人每一天，仍然有三道具体的坎：")
bullet("**算不清。** 一个人走 5 公里、少开 3 度电、回收 2 公斤塑料，到底减了多少碳？"
       "网络上的换算口径互相矛盾，同一件事能算出几倍的差距。")
bullet("**坚持难。** 减碳没有即时反馈：今天少开一次车，明天不会发生任何变化。"
       "缺少正反馈的行为，很难变成习惯。")
bullet("**换不到。** 即使坚持记录，减排量也停留在数字上，无法兑换成任何真实权益，"
       "「碳积分」很容易退化成游戏币。")
body("「碳迹」的目标不是再做一个碳排放计算器，而是把这三道坎连成一条可走通的路："
     "用**可追溯的因子**解决算不清，用**可视化和积分**解决坚持难，"
     "用**城市碳普惠对接**解决换不到。")

h2("1.2 设计思路：把「量化—激励—回馈」做成闭环")
body("作品把产品逻辑收敛为五个动作，首尾相接：")
figure(f"{VIS}/loop.png", "图 1　「量化—激励—回馈」闭环：记录 → 折算 → 看见 → 激励 → 回馈", 13.6)
body("**记录**是入口，必须足够轻：四个类目、十四种常见行为，选类目、点行为、填数量即可；"
     "端侧识图进一步把「填」变成「确认」。**折算**是核心，活动量乘以因子，因子标注基准情景与出处。"
     "**看见**是反馈：一棵随累计减排量长大的树、一张 12 周日历热力图、四条不同粒度的趋势。"
     "**激励**把减排量换成积分、徽章与证书。**回馈**把积分上报城市碳普惠平台，"
     "兑换地铁券、单车券等真实权益，再回到「记录」——闭环由此成立。")

h2("1.3 三处关键取舍")
body("同类作品常见的做法是「什么都做一点」。本作品在三个地方做了明确的取舍，"
     "这些取舍决定了后面的架构与界面。")
h3("取舍一：数据全部留在本机，把「单机版」当成隐私优势")
body("赛题将作品定位为单机版。我们没有把它当成限制，而是当成优势：碳账本属于个人数据，"
     "全量本地存储、完全离线可用，既契合信创语境下的数据主权诉求，"
     "也让演示环节不依赖现场网络。多设备场景则通过鸿蒙分布式数据服务在设备间直接同步，"
     "数据不经过任何云端。")
h3("取舍二：AI 用来「预填」，不用来「判定」")
body("通用图像分类模型天然分不清「新能源车与燃油车」「地铁与公交」这类细分类别。"
     "强行自动判定，只会把错误数据写进用户的碳账本。因此端侧 AI 只在高置信度时预填表单，"
     "低置信度交给用户确认；它的目标是降低输入成本，而不是替代用户判断。"
     "这条边界同时写进了界面文案与本文档。")
h3("取舍三：每个因子都必须能追溯到出处")
body("应用内每条因子都展示三个信息：因子数值与单位、基准情景、数据出处。"
     "对同一指标存在多来源差异的情况（例如地铁因子在不同口径下相差 4.9 倍），"
     "应用保留口径说明，而不是取一个数字了事。这是功能要求，也是作品严谨性的立足点。")

h2("1.4 设计语言：从「可替换的界面」到「碳账本」")
body("界面经历了一次彻底返工，原因不是「不好看」，而是「可替换」。")
body("v2 的界面结构是「渐变大圆角主卡 → 白色圆角卡片流 → 胶囊标签」。"
     "这是近两年 AI 辅助生成的移动端作品共用的同一套模具：把绿色换成蓝色、换掉 logo、"
     "换掉文案，它依然成立。**一个可替换的界面，在评委眼里就是可替换的作品。**")
body("问题的根子有三处：五个页面是同一个模板的五个实例；界面里没有任何形状是「碳」专有的；"
     "视觉重量全给了装饰，而真正值钱的信息（十四条因子逐条标出处）被压成小字。"
     "更具体的证据是：v2 的环形进度一边显示「今日目标 0%」，一边显示「共 6 条记录」，"
     "积分页又是「权益 100% 解锁」配「可用权益 0 项」——数字在互相打架，环就成了纯装饰。")
callout("设计判断",
        "碳积分本质是记账：活动量 × 因子 = 减排量，每一条都可追溯、可核查。"
        "账本、凭证、印章的语言，恰好就是这个产品真正的内核。")
body("v3 由此确立五条硬规则，后续所有页面都受它约束：")
table(
    ["维度", "v2", "v3「碳账本」"],
    [["底色", "冷灰 #F1F3F5 + 纯白卡", "暖纸 #F2EDE1 + 账页 #FBF8F1"],
     ["文字", "黑色四级透明度", "暖墨四级 #201D17 / #4C463A / #857C6A / #B5AC98"],
     ["主色", "荧光绿 #1F9A4E", "墨绿 #1D5C43 + 朱砂 #AB3A28（唯一高饱和色，面积 ≤ 2%）"],
     ["分组", "圆角卡 + 投影", "1px 细线 + 留白；阴影一律返回全透明"],
     ["圆角", "16 / 20 / 32", "2（账本没有圆角）"],
     ["标题", "系统黑体", "宋体（Noto Serif CJK SC 子集，SIL OFL 1.1）"],
     ["数字", "系统字", "系统字 + tnum 等宽 + 右对齐"]],
    [2.4, 5.0, 8.6],
    "表 1　v2 与 v3 的视觉参数对照")
body("三个签名元素让这套语言不依赖装饰也成立：**双线表头**（宋体标题下粗线、再下细线，"
     "账簿表头的标准画法）、**引导点线**（项目 ······ 金额，把名称与数值连成一行账）、"
     "**朱印**（两字竖排、-5° 倾斜的方章，压在抬头右上角）。"
     "朱印是整套界面里唯一一处「不整齐」——真实盖出来的章不可能摆正，"
     "而这正是「被设计过」与「生成出来的」之间的分界线。")
body("v3.2 又把这种「不完美」推到笔画层面：印章边框不再是 border 画的完美矩形，"
     "而是 Canvas 上两遍抖动贝塞尔。第一遍定形，第二遍在第一遍的形上抖 0.55 倍偏移，"
     "模拟余墨；种子取自印章文字，不用随机数，因此同一枚章在屏幕、截图与分享图里逐像素同形。"
     "实测边缘峰值偏离 0.800vp（验收线 1.5），单边倾斜 0.370vp。")
figure_pair([
    (f"{SHOT}/00-记一笔-总览.jpeg", "图 2　记一笔：墨色封面 + 朱印 + 双线表头"),
    (f"{ASSET}/改造前后对比-v3账本.png", "图 3　六屏「改造前 / 改造后」对比"),
], w_cm=7.4)
body("视觉参数不只是审美，它也承担可用性职责：正文与底色对比度均高于 WCAG AA；"
     "四类目除颜色外还有文字标签与图标，不做「仅靠颜色」的区分；"
     "所有数字使用 tnum 等宽并右对齐，便于逐行核对。")

h2("1.5 信息架构：一屏一主题")
body("视觉统一之后，暴露了第二个问题：每加一个能力，就在页面底部多垒一张卡。"
     "记一笔页尾长出「记录查询」，积分页尾长出「我的证书」——页面越用越长，读起来像功能堆。"
     "问题不在功能多，而在**新功能没有落点，只能往下接**。")
body("为此定了一条硬规矩：**一屏一主题**——录入页只讲「记」，看板页只讲「看」，积分页只讲「攒与换」。"
     "新能力只允许三种落法：")
bullet("**合并**：与已有区块同主题的，并成一张卡，卡内分段切换；")
bullet("**下沉**：次要且低频的，做成整屏二级页，主页只留一个行内入口；")
bullet("**替换**：能塞进已有行或图例的，就地长出交互，不新增区块。")
body("按这把尺子量下来，本轮改了五处：记录查询下沉为独立的「记录」页（五等分账页签：全部 + 四类），"
     "记一笔页尾只留 3 条最近记录与一个「全部 ›」；看板的统计粒度从独立卡片降为一行账页式分段；"
     "分类占比的图例每行加「›」，点击带类目跳转到记录页；"
     "积分页把「徽章」与「证书」两张卡合成一张，卡内分「可兑换 / 已获得」；"
     "科普把 8 篇文章从 8 张卡收成一页账页 + 8 行，行内展开。")
body("判断依据不是「块多不多」，而是「块与块之间是不是同一件事」：记一笔的 01→05 是同一件事的"
     "五个步骤，必须顺着走；科普的八篇彼此独立，就没有理由各占一张卡。"
     "这条规矩同样适用于答辩——一屏讲一件事，投影上看的人才跟得上。")

h2("1.6 与赛题要求的对应关系")
table(
    ["赛题要求", "实现情况", "对应模块"],
    [["主要功能 1　低碳行为核算", "已实现", "记一笔、CarbonRepository、因子库"],
     ["主要功能 2　数据可视化看板", "已实现", "看板（树 / 日历 / 折线 / 柱状 / 环形，日周月年）+ 记录页（按类目查询与删除）"],
     ["主要功能 3　碳积分激励体系", "已实现", "积分（余额、徽章与证书合一、归属态、流水）"],
     ["主要功能 4　双碳科普专栏", "已实现", "科普（8 篇，四类标签）"],
     ["主要功能 5　本地数据管理", "已实现", "我的（JSON 备份、CSV 导出、清空）"],
     ["创新拓展 1　超级终端多设备同步", "已实现", "同步面板 + 分布式 KV + 时间戳信封"],
     ["创新拓展 2　端侧 AI 图片识别", "已实现", "MindSpore Lite + Core Vision Kit 双通路"],
     ["创新拓展 3　模拟城市碳普惠接口", "已实现", "积分页碳普惠专区（绑定/上报/查询/兑换/订单）"],
     ["创新拓展 4　智能服务与社交分享", "已实现", "今日任务、生活建议、减排凭证"],
     ["延伸：年度报告", "已实现", "看板 → 整屏年报（全年汇总与构成）"],
     ["延伸：桌面服务卡片", "已实现", "2×2 / 2×4 / 4×4 三尺寸，数据随应用刷新"]],
    [5.0, 2.6, 8.4],
    "表 2　赛题要求与实现情况对照")

# ================================================================ 二、系统架构
doc.add_page_break()
h1("二、系统架构")

h2("2.1 总体架构：四层，自上而下")
body("工程采用四层结构。层与层之间只通过明确的接口或数据模型通信，"
     "界面不直接触达系统能力，业务逻辑不依赖具体存储实现。")
figure(f"{VIS}/architecture.png", "图 4　系统架构：表现层 / 业务层 / 数据层 / 能力层", 15.4)
table(
    ["层次", "职责", "主要模块"],
    [["表现层", "界面与交互：五个页签、记录页、年报、凭证",
      "EntryPage、DashboardPage、RecordsPage、Charts、PointsPage、KnowledgePage、"
      "SmartService、ProfilePage、YearReportPage、Index"],
     ["业务层", "领域逻辑：减排核算、积分规则、任务推荐、碳普惠流程",
      "Models、TaskEngine、FactorLibrary、KnowledgeBase、CarbonInclusiveApi"],
     ["数据层", "统一存取、序列化、跨设备同步与冲突合并",
      "CarbonRepository、DistributedStore"],
     ["能力层", "鸿蒙系统能力：存储、分布式、推理、识别、快照",
      "distributedKVStore、distributedDeviceManager、MindSpore Lite、"
      "Core Vision Kit、ArkUI componentSnapshot、Image Kit"]],
    [2.2, 6.4, 7.4],
    "表 3　分层架构与主要模块")

h2("2.2 工程结构与文件职责")
body("源码正本位于 `project/carbon-footprint`。工程路径不能包含中文（hvigor 会硬性拒绝），"
     "因此构建脚本会先把源码同步到纯英文路径再编译。核心文件如下：")
table(
    ["文件", "行数", "职责"],
    [["`common/Theme.ets`", "约 352", "设计令牌：纸墨色、字号、行高、圆角、动效；所有渐变与阴影在此退化为纯色/透明"],
     ["`common/RoughMath.ets`", "约 250", "确定性伪随机与抖动几何，纯 TS，不 import 任何 ArkUI 类型"],
     ["`common/DistributedStore.ets`", "约 721", "分布式 KV 封装：信封写入、监听、同步、冲突计数"],
     ["`view/Rough.ets`", "约 79", "把抖动贝塞尔交给 Canvas，只负责绘制"],
     ["`view/Common.ets`", "约 705", "11 个通用组件与手绘印章 Seal（唯一的画布逻辑）"],
     ["`view/EntryPage.ets`", "约 860", "记一笔：类目账目行、行为标签、下划线输入、最近记录"],
     ["`view/DashboardPage.ets`", "约 1112", "看板：英雄区、我的树、日历热力图、图表、智能服务"],
     ["`view/PointsPage.ets`", "约 1022", "积分 / 碳普惠 / 权益 / 流水"],
     ["`view/KnowledgePage.ets`", "约 249", "科普：一页账页 + 8 行，行内展开，标签裸芯片"],
     ["`view/RecordsPage.ets`", "约 314", "记录：五等分账页签、全量明细、删除与合计"],
     ["`view/YearReportPage.ets`", "约 751", "整屏年度报告"],
     ["`view/Charts.ets`", "约 490", "mpchart 封装：折线、柱状、环形"],
     ["`view/SmartService.ets`", "约 693", "任务、建议、减排凭证与分享图"],
     ["`data/CarbonRepository.ets`", "约 489", "仓储：记录、积分、档案、导入导出"],
     ["`data/FactorLibrary.ets`", "—", "14 条因子（数值、基准、出处、单位）"],
     ["`data/CarbonInclusiveApi.ets`", "—", "碳普惠模拟接口：异步、错误码、库存、幂等"]],
    [5.2, 1.8, 9.2],
    "表 4　主要文件与职责（行数为量级）")

h2("2.3 数据层的关键决策：为什么不用关系型数据库")
body("数据层没有采用关系型数据库（relationalStore），而是直接建立在分布式键值库"
     "（distributedKVStore）之上。这是一处影响全局的取舍。")
body("原因在于创新拓展 1 需要复用分布式存储能力，而分布式数据服务与关系型数据库是两套"
     "互不通用的存储引擎。如果先用关系型数据库建表、后期再接入分布式同步，"
     "整个数据层需要重写。因此在项目起步阶段就把存储建立在 KV 之上，"
     "使后续同步成为「接入一个已有组件」，而不是「重构数据层」。")
table(
    ["维度", "关系型数据库", "分布式 KV（本作品采用）"],
    [["建模", "三张表 + 外键 + 索引", "主键 → JSON 值，无 schema"],
     ["多设备同步", "需要自建同步服务或额外通道", "系统原生分布式能力，设备间直连"],
     ["查询", "SQL where / join", "keys() 取全量，内存排序筛选"],
     ["迁移成本", "同步接入需重写数据层", "同步是存储的天然属性"],
     ["适用规模", "万级以上、复杂关联", "个人级（每天数条至数十条）"]],
    [2.6, 6.4, 7.0],
    "表 5　存储选型对比")

h2("2.4 数据模型与键设计")
body("存储以 `carbon:` 为库前缀，业务键如下：")
table(
    ["业务键", "值", "说明"],
    [["`behavior:<id>`", "BehaviorRecord JSON", "一条低碳行为；id 由时间戳、进程内序号与随机数共同保证唯一"],
     ["`points:<id>`", "PointsEntry JSON", "一条积分流水，只增不改，天然免冲突"],
     ["`profile`", "Profile JSON", "用户档案（单例），含昵称、家庭 ID"],
     ["`owned:rewards`", "string[] JSON", "已兑换的徽章 / 证书 id，归属态去重，重复兑换不再扣分"],
     ["`platform:account`", "PlatformAccount JSON", "碳普惠平台账户"],
     ["`platform:order:<id>`", "ExchangeOrder JSON", "权益兑换订单"]],
    [5.2, 5.2, 5.8],
    "表 6　分布式 KV 键设计")
body("查询策略是「取全量后内存排序筛选」。KV 没有 where 子句，但个人级碳数据的量级为"
     "每天数条至数十条，远未达到需要索引的程度，因此没有为查询性能引入额外复杂度。"
     "这一取舍在代码注释中写明，避免后续维护者误以为漏了索引。")

h2("2.5 冲突处理与最终一致性")
body("所有写入都以「信封」形式落库：`{ payload, ts, origin }`。payload 是业务负载，"
     "ts 是写入时间戳，origin 是写入方设备标识。同步时逐键比较时间戳，"
     "较新的一方胜出；当本地版本更新、拒绝了远端版本时，冲突计数加一，"
     "并在同步面板中如实展示。")
body("积分流水被设计为「只增不改」的追加型数据，因此天然免冲突；"
     "行为记录与档案采用时间戳信封，冲突时以最新版本为准。"
     "这对应赛题要求的「以最新时间戳的版本为准，确保数据最终一致性」。"
     "需要说明的是：模拟器不具备分布式软总线能力，完整链路需两台真机验证（见第八章）。")

h2("2.6 四条关键流程")
h3("流程一：记一笔（写入与折算）")
body("用户选择类目与行为 → 输入数量与日期 → 实时回显「本次减排」→ 保存。"
     "保存时业务层按「活动量 × 因子」计算，写入 behavior 键与 points 键，"
     "再通知看板刷新。计算与写入都在本地完成，不依赖网络。")
h3("流程二：多设备同步")
body("设备发现 → 认证 → 建立信任 → 拉取远端键 → 逐键比较信封时间戳 → 合并 → 回写 → "
     "刷新面板。同步面板展示本机标识、可信设备、上次同步时间、同步结果、冲突数与远端写入数。")
h3("流程三：碳普惠上报与兑换")
body("绑定账户 → 上报积分（异步，带请求号，幂等）→ 查询平台余额 → 选择权益 → 兑换"
     "（校验库存与余额）→ 生成订单 → 查询订单。模拟层保留了真实接口的延迟、错误码、"
     "库存扣减与幂等语义，业务层只依赖接口契约。")
h3("流程四：端侧识图")
body("拍照 / 选图 → 视觉通路（MindSpore Lite + MobileNetV2）与文字通路（Core Vision Kit）"
     "并行 → 置信度融合 → 命中高置信行为则预填表单，否则只给出候选。"
     "图片全程留在设备内，不上传任何服务器。")

# ================================================================ 三、技术选型
doc.add_page_break()
h1("三、技术选型")

h2("3.1 平台、语言与版本")
table(
    ["项目", "选型", "说明"],
    [["操作系统", "HarmonyOS / OpenHarmony", "赛题指定平台"],
     ["开发语言", "ArkTS", "类型安全，适合中大型声明式 UI"],
     ["UI 框架", "ArkUI（声明式）", "状态驱动、组件化，便于统一设计令牌"],
     ["API 版本", "compatibleSdkVersion 5.0.0(12)", "满足赛题「API 12 及以上」"],
     ["开发工具", "DevEco Studio 26.0.0", "实测版本"],
     ["构建", "hvigor + ohpm", "依赖仅 @ohos/mpchart 一个，可完全离线构建"],
     ["测试设备", "HarmonyOS 7.0.0 模拟器（1320×2232）", "另需两台真机验证分布式与 AI"]],
    [3.0, 7.0, 6.2],
    "表 7　平台与工具链")

h2("3.2 存储：分布式 KV 是唯一能同时满足「本地优先 + 多设备」的选择")
body("如 2.3 所述，KV 的选择由创新拓展 1 反推而来。这里补充两点工程细节："
     "一是信封与影子副本都放在内存 Map 中，应用启动时从 KV 重建，"
     "避免把同步元数据再写回存储造成双写；二是所有写入串行化，"
     "防止同一键的并发写导致时间戳乱序。")

h2("3.3 图表：为什么选 mpchart，以及踩过的三个坑")
body("图表层评估过三条路线：WebView 嵌入 ECharts（体积大、离线资源多、与 ArkUI 手势冲突）、"
     "Canvas 手绘（可控但工作量大）、OpenHarmony-TPC 官方图表组件库 mpchart"
     "（纯 ArkTS 源码、可离线、支持折线/柱状/饼图）。最终选择 mpchart，"
     "原因是它可读可改——遇到问题能直接改源码，而不是等第三方修复。")
body("落地过程中修复了三类问题：")
bullet("**柱子变纯黑**：`new Fill([色])` 只给一个色标时不报错，直接把柱子画成黑色；"
       "给两个相同色标（首尾同色 = 纯色）才稳定。")
bullet("**环形图百分比 2841%**：百分比被重复换算（先按总量取百分比，渲染时又乘 100）。"
       "修复后中心显示总量、图例显示正确百分比与进度条，四类合计 100%。")
bullet("**零数据时 Y 轴跑到负数**：折线图在 0 记录时自动把轴范围算成 −1.2~1.2，"
       "而「减排趋势」出现负数是说不通的。已改为显式设置轴最小值 0。")

h2("3.4 端侧 AI：MindSpore Lite 负责「看」，Core Vision Kit 负责「读」")
body("视觉通路使用 MindSpore Lite 加载随包内置的 MobileNetV2，推理完全离线；"
     "文字通路使用 Core Vision Kit 的端侧 OCR 读取图片中的文字，再用关键词规则映射到行为。"
     "两路结果按置信度融合：一致时提升置信度，冲突时取较高者并降低置信度；"
     "仅当置信度达到阈值且映射到的因子存在时，才自动预填。")
body("选择端侧而非云端，理由有三：图片不出设备，符合隐私与信创要求；"
     "无网络依赖，演示环境可控；推理延迟稳定。代价是模型能力有限，"
     "因此产品定位为「预填」而非「判定」，这一点在前文已说明。")

h2("3.5 字体与视觉资产：可打包、可复现、可校验")
body("设备上没有宋体，也不能打包苹果的 Songti（许可证不允许）。作品使用 SDK 自带的"
     "Noto Serif CJK SC（SIL OFL 1.1），按工程实际用到的字符子集化为 546 KB 的"
     "`LedgerSerif.otf`，仅用于固定文案（标题、期次、印章）；用户输入一律走系统字体，"
     "避免缺字渲染成豆腐块。")
body("纸张纹理没有下载任何素材，而是程序化生成三张 512×512 无缝 tile"
     "（纸页、账页、墨卡），低频噪声做纸浆斑、高频做纤维，均值归零以保持亮度。"
     "图标同样是脚本生成的 24×24 SVG，全部由同一管线产出，视觉重量极差校准到 0.34%。")

h2("3.6 依赖、构建与可复现性")
body("工程只依赖 `@ohos/mpchart` 一个三方库，`ohpm install` 后即可完全离线构建。"
     "仓库已验证自包含：克隆到空目录后执行 `ohpm install` 与 `./hvigorw assembleHap`"
     "可成功产出 HAP；`tools/test-logic.sh` 与 `tools/icon/check_icons.py` 全绿。"
     "本地签名使用 SDK 自带的调试材料，全程不需要登录华为账号。")

# ================================================================ 四、功能实现
doc.add_page_break()
h1("四、功能实现")

h2("4.1 低碳行为核算：把「一笔账」记清楚")
body("录入流程被压缩为四步：选类目 → 点行为 → 填数量与日期 → 保存。"
     "类目不是四宫格色块，而是四行账目行：序号、名称、项数、选中朱点。"
     "行为以方角标签呈现，数量与日期是下划线输入，保存按钮为墨底方角。"
     "保存时按「减排量 = 活动量 × 因子」计算，结果实时回显，并同步发放积分。")
body("内置 14 条因子，覆盖出行、节水节电、旧物回收、光盘行动四类。"
     "每条因子在界面上展示因子数值与单位、基准情景、数据出处三行信息，"
     "不需要跳出页面就能核对。因子表见第六章。")
figure_pair([
    (f"{SHOT}/00-记一笔-总览.jpeg", "图 5　记一笔首页：累计减排、今日目标与四类账目行"),
    (f"{QI}/05-记一笔-最近记录收口.jpeg", "图 6　05 数量与日期与页尾收口：只留 3 条最近记录 + 「全部 ›」"),
], w_cm=7.2)
body("页尾固定为「最近记录」：表头显示总条数，只列 3 条，右侧一个「全部 ›」。"
     "筛选与全量列表都下沉到独立的记录页，录入页因此保持「抬头 + 01–05 + 保存 + 3 条」的固定节奏，"
     "不会随记录变长——这一处改动对应 1.5 节的「下沉」。")
body("输入校验只做必要的三件事：数量必须为正数、日期不得晚于今天、"
     "所选行为必须存在对应因子。校验失败时在输入框下方给出具体原因，"
     "而不是弹一个笼统的「输入有误」。")

h2("4.2 数据可视化与记录查询：让「坚持」看得见")
body("本文档的截图取自同一套演示数据，跨越了演示录屏前后的两个时点：补录那笔 6 公里步行之前是"
     "20.58 kg CO₂e、11 条记录、2,058 碳积分；之后是 21.75 kg、12 条、累计 2,175 分，"
     "兑换植树证书（300 分）后余额 1,875 分。两组数字相差恰好一笔 1.17 kg 的记录与一次 300 分兑换，"
     "可据此逐图核对——图中数字按拍摄时点如实保留，没有为统一口径而修改截图。")
body("看板支持日、周、月、年四种粒度，并提供五种表达：")
bullet("**我的树**：树冠密度随累计减排量增长（叶子数 = 90 + kg × 14，封顶 320），"
       "0 条记录时只有一根芽，10 kg 以上为四层枝、满冠。它是「量」的具象化，"
       "也是整页唯一带生长感的元素。")
bullet("**减排日历**：最近 12 周 × 7 天，每格一天，按当日减排量分四档着色；"
       "顶部给出连续记录天数与有记录天数。")
bullet("**折线趋势**：平滑曲线，本期实线、上期灰色虚线；横轴是日期而不是索引值。"
       "分桶口径与顶部「区间」严格一致，全部按日历切：日视图 24 个小时、周视图本周一至周日、"
       "月视图当月天数、年视图 12 个月；幽灵线取「上一期同位置」（昨天同一小时 / 上周同一天 / "
       "上月同一天 / 去年同月），两条线逐点可比。")
bullet("**分类对比**：四类柱状图，柱顶直接标注数值，去掉竖向渐变（柱是量，不是立体物）。")
bullet("**分类占比**：环形图中心显示累计总量，图例用「色点 + 百分比 + 进度条」，"
       "不依赖悬浮提示。")
figure(f"{SHOT}/10-看板-总览.jpeg", "图 7　看板总览：墨色封面、我的树与年度报告入口", 7.2)
figure_pair([
    (f"{SHOT}/11-看板-日历.jpeg", "图 8　减排日历与本周趋势：连续 5 天，周减排 5.96 kg"),
    (f"{QI}/14-看板-底部三块统一表头.jpeg", "图 9　看板下半部：任务、建议与凭证统一为账页表头，建议默认只露 1 条"),
], w_cm=7.2)
body("三处与信息架构有关的处理：**统计粒度**不再单占一张卡，而是降为一行账页式分段（日 / 周 / 月 / 年，"
     "选中项用朱砂下划线），它本来就作用于全页口径，收在同一行里控制感反而更直接。")
body("**分类占比的图例就是入口**：每一行「色点 + 类别 + 百分比 + 进度条」右侧加一个「›」，"
     "点击带类目跳到记录页并预选该类目。赛题要求「以三图展示趋势，支持分类查询历史记录」，"
     "这一步把「查询」落到了图例上，而不是在图下面另起一块列表。")
body("**记录页承接「分类查询」。**从图例或页尾的「全部 ›」进入，是整屏二级页：顶部五等分账页签"
     "（全部 + 四类），选中项用朱砂下划线；表头给出当前筛选下的条数与合计减排；列表按时间倒序，"
     "每行「类目色点 + 行为名 + 减排量」，第二行「日期 · 数量 · 类目」，右侧可直接删除。"
     "切换类目即重新汇总，不需要返回看板；删除后就地刷新合计，让「查询—核对—修正」在一屏内闭合。"
     "它不占第六个页签——页签栏五个已是上限，而「翻旧账」是低频动作。")
figure_pair([
    (f"{QI}/06-记录-全部类目.jpeg", "图 10　记录页（全部）：12 条、合计 21.75 kg CO₂e，五等分账页签"),
    (f"{QI}/07-记录-分类查询.jpeg", "图 11　按「出行」筛选：5 条、合计 8.26 kg，带类目进入即已预选"),
], w_cm=7.2)
body("**空区间不留白洞**：柱状图卡内给「本 X 还没有记录 / 看全年 › / 翻明细 ›」，"
     "饼图在区间为空时整张不渲染——不会出现图表库自带的黄色「暂无图表数据」提示。")
body("五张图共用同一份数据源与同一套类目配色，读图时不需要在不同图之间重新建立对应关系。"
     "所有数字使用 tnum 等宽并右对齐，便于逐行核对。")

h2("4.3 碳积分与城市碳普惠：从「数字」到「权益」")
body("积分规则是每减排 1 kg CO₂e 得 100 积分。积分有两个去向：本地兑换虚拟徽章与电子证书；"
     "上报城市碳普惠平台后兑换地铁乘车券、共享单车券、环保购物袋、公园门票与电费红包。"
     "兑换按钮根据余额与库存自动置灰或点亮，避免无效操作。")
body("碳普惠对接层完整实现「绑定 → 上报 → 查询 → 兑换 → 订单」五个环节。"
     "由于城市平台未对个人开发者开放接口，该层为本地模拟，但保留了真实接口的全部语义："
     "异步调用、网络延迟、业务错误码、库存扣减、幂等与账户状态校验。"
     "业务层只依赖接口契约，未来替换通信层即可对接真实平台。")
body("「徽章」与「证书」原本是两张卡——一张列可兑换项，一张列已拥有项，中间隔着一屏。"
     "本轮合成一张，卡内分段切换，表头直接写「已获得 1/4」，"
     "「攒分 → 兑换 → 拥有」于是在同一屏里连成一条线（对应 1.5 节的「合并」）。")
body("奖励补上了**归属态**。原来兑换只是「花分」：扣完分只多一条流水，屏幕上什么也不多，"
     "同一张证书还能被反复兑换、反复扣分。现在每次兑换写一条 `owned:rewards`，"
     "已拥有的条目按钮变为「已拥有」且不再扣分；证书按档案昵称、累计减排量与本机日期印成一张"
     "可截图的票面（抬头、授予人、累计减排、落款「本机生成 · 数据不出设备」），"
     "徽章则以「已获得」小条目排列——赛题要求的「兑换虚拟低碳徽章、植树证书等奖励」因此有了可看的实物。")
figure(f"{SHOT}/20-积分-碳普惠.jpeg", "图 12　积分页：碳积分余额、城市碳普惠平台与可兑换权益", 7.2)
figure_pair([
    (f"{QI}/08-积分-徽章证书合一.jpeg", "图 13　徽章与证书合一：卡内分「可兑换 / 已获得」，表头显示已获得 1/4"),
    (f"{QI}/09-积分-已获得证书.jpeg", "图 14　「已获得」段：植树证书印成本机生成的票面，流水同步 −300 分"),
], w_cm=7.2)

h2("4.4 双碳科普：内容与界面分离")
body("内置 8 篇图文科普，按政策、概念、数据、技巧四类标签组织。"
     "内容涵盖双碳目标、碳足迹计算方法、电网排放因子的地域差异、出行与居家技巧、"
     "回收的减排原理、食物浪费与碳排放、碳普惠机制。"
     "文章以独立数据文件组织，后续扩充不需要改动界面代码。")
body("上一版是八篇文章各占一张带内边距的白卡，翻起来像一摞便签。"
     "本轮收成一页账页：表头写「全部科普 · 8 篇」，下面是 8 行——"
     "每行「分类字 + 标题 + 一行说明 + 右箭头」，点击就地展开正文，箭头旋转 90°。"
     "分类标签也从卡片降为一行裸芯片。八篇文章彼此独立，没有理由各占一张卡（对应 1.5 节的「合并」）。")
figure(f"{QI}/12-科普-十卡收成一页.jpeg", "图 15　科普：8 篇文章收成一页账页 + 8 行，行内展开", 7.2)

h2("4.5 本地数据管理：可带走，也可清空")
body("提供三种能力：备份为结构化 JSON（档案、全部行为记录、积分流水）；"
     "导出 CSV 报表（行为记录，便于在电脑上统计）；清空全部本地数据。"
     "前两者写入应用沙箱并在界面回显完整路径，清空操作即时生效并给出提示。"
     "所有数据默认留在本机，不上传云端。")

h2("4.6 创新拓展 1：超级终端多设备同步")
body("基于鸿蒙分布式数据服务实现。两台设备登录同一账号、完成设备认证并处于同一局域网后，"
     "行为记录与积分流水自动同步。同步面板展示本机标识、可信设备列表、上次同步时间、"
     "同步结果、冲突记录数与远端写入数，让数据流转过程对用户可见。")
body("家庭碳积分合并通过在档案中引入「家庭 ID」实现：同一家庭 ID 的设备同步后自然形成"
     "合并视图，不需要额外的服务端聚合。")
figure(f"{SHOT}/41-我的-同步与数据.jpeg", "图 16　「我的」页下半部：同步面板、端侧 AI 自检与数据管理", 7.2)
body("如实说明：模拟器不具备分布式软总线能力，当前面板显示「未获取到本机标识」；"
     "代码与业务逻辑已完成，端到端验证需两台真机。")

h2("4.7 创新拓展 2：端侧 AI 图片识别")
body("用户在录入页拍照或选图，应用在本机完成识别并预填，图片不出设备。"
     "视觉通路用 MindSpore Lite 跑 MobileNetV2，文字通路用 Core Vision Kit 读文字，"
     "两路按置信度融合。应用内提供「运行 AI 自检」，用内置测试图验证模型可加载、"
     "张量形状正确、能输出候选索引——这也是做「索引 → 类目」标定表的第一步。")
figure(f"{VIS}/ai-naked.png", "图 17　端侧 AI 双通路与置信度融合", 14.2)
body("自检结果与已知限制在界面上直接呈现，不把「能跑通」包装成「识别准确」。"
     "当前标定表仍为空，因此视觉通路暂不产出建议；这是如实标注的能力边界。")

h2("4.8 创新拓展 3：模拟城市碳普惠接口")
table(
    ["环节", "接口语义", "模拟实现要点"],
    [["绑定", "账户注册 / 绑定，返回账户号", "幂等：同一设备重复绑定返回同一账户"],
     ["上报", "异步提交积分，返回请求号", "延迟 300–900 ms；重复请求号不重复入账"],
     ["查询", "查询平台余额与账户状态", "账户冻结时返回业务错误码"],
     ["兑换", "校验余额与库存，生成订单", "库存原子扣减；余额不足返回明确错误码"],
     ["订单", "按订单号查询状态", "订单状态机：待处理 → 已完成 / 已取消"]],
    [2.2, 6.4, 7.4],
    "表 8　碳普惠五环节与模拟语义")

h2("4.9 创新拓展 4：智能服务与减排凭证")
body("每日生成 3 条任务，规则为「短板优先」：先选今天尚未记录的类目，再按历史记录条数"
     "从少到多排序，优先推送最薄弱的环节；已完成的事项标记并排到末尾。"
     "生活建议由可解释的规则生成，每条建议都对应一个具体数据事实，"
     "例如「本周比上周多减排 X kg」「你还没有记录过旧物回收」。")
body("分享卡在 v3.2 中从「海报」改成「减排凭证」：抬头、账簿双线、累计减排大字、"
     "三条引导点线明细、落款与朱印骑缝、底注「本机生成 · 数据不出设备」。"
     "凭证通过 ArkUI 组件快照导出为 PNG，印章与屏幕逐像素同形。")
figure(f"{SHOT}/15-看板-分享凭证.jpeg", "图 18　减排凭证：小票式排版与朱印骑缝", 7.2)

h2("4.10 延伸：整屏年度报告")
body("年度报告把分散在图表里的全年数据收拢到一页：封面给出年度、低碳称号、活跃天数与"
     "记录条数；正文依次给出全年累计减排、等效植树量、记录条数、碳积分与分类构成。"
     "口径与看板严格一致，等效植树按「1 棵树·年 ≈ 18 kg CO₂e」折算并在页脚写明。")
figure_pair([
    (f"{SHOT}/50-年度报告-封面.jpeg", "图 19　年度报告封面：2026、低碳生活家、活跃天数"),
    (f"{SHOT}/51-年度报告-构成.jpeg", "图 20　全年数字与减排构成：与看板同源同口径"),
], w_cm=7.2)

h2("4.11 延伸：鸿蒙桌面服务卡片")
body("除赛题列出的四项创新外，作品还实现了桌面服务卡片：不必打开应用即可看到今日减排量、"
     "碳积分、近 7 日趋势与个性化提示；支持 2×2、2×4、4×4 三种尺寸，"
     "新增记录后主应用主动通知卡片刷新。卡片数据直接读取同一分布式库，"
     "因此显示内容与打开应用一致。")

# ================================================================ 五、测试方案
doc.add_page_break()
h1("五、测试方案")

h2("5.1 测试策略：五层，越靠下越自动")
body("作品采用分层测试策略，目标不是「测得多」，而是「让每一层都能独立复现」：")
table(
    ["层级", "对象", "手段", "频率"],
    [["L1 构建与静态检查", "工程可编译、依赖完整", "hvigor assembleHap；code-linter", "每次提交"],
     ["L2 纯逻辑断言", "因子算术、任务、建议、工具、抖动几何", "Node 直跑 test-logic.sh", "每次提交"],
     ["L3 功能用例", "录入、看板、积分、科普、数据管理", "模拟器手工 / 脚本化点击", "每轮迭代"],
     ["L4 视觉回归", "五页签、年报、凭证、图标", "构建→安装→逐页截图；人工比对", "每次改样式"],
     ["L5 能力验证", "分布式同步、端侧 AI", "真机双机 / 真机自检", "待真机条件"]],
    [3.4, 5.6, 5.2, 2.0],
    "表 9　五层测试策略")
body("越靠下的层级越自动化：L1 与 L2 可以在无人值守下跑完，L4 由脚本完成截图、"
     "人工只做判断。这样把「回归成本」压到最低，样式改动可以一天迭代多轮。")

h2("5.2 测试环境")
table(
    ["项目", "配置"],
    [["测试设备", "HarmonyOS 7.0.0 手机模拟器，1320×2232，RAM 4 GB"],
     ["开发工具", "DevEco Studio 26.0.0"],
     ["编译目标", "compatibleSdkVersion 5.0.0(12)"],
     ["安装方式", "本地签名后通过 hdc 安装（无需登录华为账号）"],
     ["构建路径", "同步到 /tmp/carbon-footprint（纯英文路径）"]],
    [3.2, 12.8],
    "表 10　测试环境")

h2("5.3 L2：55 项纯逻辑断言")
body("不依赖界面的纯逻辑被单独抽出，编译后在 Node 环境中执行断言。"
     "当前共 55 项，全部通过，覆盖五组：")
table(
    ["组别", "覆盖内容", "项数"],
    [["因子算术", "逐条验证「减排量 = 基准 - 实际」；因子为正；出处与基准非空；四类目均有覆盖", "14"],
     ["任务推荐", "新用户任务数、已完成标记、配额补齐、短板优先排序", "9"],
     ["生活建议", "空数据引导、周对比趋势、未记录类目提醒", "7"],
     ["通用工具", "两位小数边界、日期格式化、唯一标识生成", "10"],
     ["印章抖动", "峰值偏离 ≤ 1.5vp、单边倾斜、拐角错开、余墨偏离、同 seed 32 个数完全一致", "15"]],
    [3.0, 11.4, 1.6],
    "表 11　55 项断言的分组")
body("这组测试在开发中实际抓到了两个缺陷：唯一标识生成函数在短时间内连续调用会重复；"
     "存储读取接口在键不存在时的行为与文档约定不一致，导致「不存在则写默认值」的逻辑不生效。"
     "两者均已修复并补了回归断言。")
callout("可复现命令",
        "`tools/test-logic.sh` → 55 passed / 0 failed；`python3 tools/icon/check_icons.py` → "
        "24 个图标、视觉重量极差 0.34%。")

h2("5.4 L3：功能测试用例")
table(
    ["用例", "操作与预期", "结果"],
    [["核算-01", "录入 12 公里步行，预期 12 × 0.19567 ≈ 2.35 kg，发放 235 积分", "通过，数值一致"],
     ["核算-02", "数量为 0 / 负数 / 非数字，预期拒绝保存并提示原因", "通过"],
     ["核算-03", "日期晚于今天，预期拒绝并提示", "通过"],
     ["持久化-01", "录入后杀掉应用重开，预期数据仍在", "通过"],
     ["看板-01", "切换日/周/月/年，预期区间、总量与横轴同步更新", "通过"],
     ["看板-02", "0 记录时折线图不出现负轴", "通过（已修）"],
     ["看板-03", "环形图百分比合计 100%，中心显示总量", "通过（修复 2841% 缺陷）"],
     ["看板-04", "热力图色阶与连续天数一致", "通过"],
     ["看板-05", "周 / 月 / 年三档的区间、折线横轴与柱状 / 环形同口径；空区间给「看全年 / 翻明细」", "通过（已修）"],
     ["记录-01", "从看板「出行」行进入，记录页已预选「出行」，条数与合计等于该类目合计", "通过"],
     ["记录-02", "删除一条后，记录页合计与看板总量同步减少；切回「全部」恢复", "通过"],
     ["积分-01", "余额、勋章、权益解锁比例一致", "通过"],
     ["碳普惠-01", "上报后平台余额增加、待上报清零", "通过"],
     ["碳普惠-02", "重复点击上报不重复入账（幂等）", "通过"],
     ["碳普惠-03", "库存为 0 时兑换按钮置灰", "通过"],
     ["科普-01", "四类标签筛选、展开与收起", "通过"],
     ["数据-01", "备份 JSON / 导出 CSV，文件落盘且回显路径", "通过"],
     ["分享-01", "生成凭证 PNG，印章与屏幕同形", "通过"],
     ["年报-01", "年报数字与看板一致", "通过"]],
    [2.6, 10.4, 3.0],
    "表 12　功能测试用例（节选）")

h2("5.5 L4：视觉回归与截图")
body("样式改动的回归靠一条命令完成：`tools/preview.sh all` 会构建、签名、安装，"
     "并逐页切换截图；`tools/look.sh` 则用于细节迭代（只截当前屏，并把印章裁出放大 4 倍）。"
     "每轮改动后人工比对五页签首屏、看板下滚、记录页、空区间、年报、凭证几个关键画面；"
     "信息架构改动（1.5 节）另按「新能力是否落在页底」逐页复查，本轮据此改掉了五处。")
body("图标另有一套自检：24 个 SVG 统一 24×24 画布、统一填充式造型，"
     "脚本会检测内容是否被画布裁切，并统计五个页签图标的视觉重量极差。"
     "实测抓出并修掉了一个底部被裁的火焰图标。")

h2("5.6 L5：能力验证的边界")
body("分布式同步与端侧 AI 两条链路受测试设备限制，尚未完成端到端验证："
     "模拟器不具备分布式软总线；Core Vision Kit 官方不支持模拟器。"
     "当前可验证的部分是界面、业务逻辑、状态展示与端侧推理自检；"
     "不可验证的部分在第八章如实列出，不用「应该可以」代替结论。")

h2("5.7 缺陷记录：修过的，才算测过")
table(
    ["#", "症状", "根因", "修复"],
    [["1", "环形图出现 2841%", "百分比重复换算", "只在一处换算，补断言"],
     ["2", "按钮设了圆角仍显示胶囊", "Button 默认 Capsule，此时 borderRadius 被忽略",
      "全部按钮显式 ButtonType.Normal"],
     ["3", "柱子画成纯黑", "mpchart 单色标 Fill 的退化行为", "给两个相同色标"],
     ["4", "印章与分享图重绘后不一致", "使用 Math.random()", "改为文字哈希种子"],
     ["5", "@Builder 明细停在首帧", "按值传参不触发重绘", "改为 @Component + @Prop"],
     ["6", "Path 画的树只有 1/3.67 大小", "Path commands 单位是 px，布局是 vp", "改用 Canvas（vp 坐标）"],
     ["7", "纹理完全看不见", "backgroundColor 盖住 backgroundImage", "把底色烤进 tile"],
     ["8", "零数据时折线轴跑到负数", "图表自动轴范围", "显式 setAxisMinimum(0)"]],
    [0.9, 4.8, 5.6, 4.7],
    "表 13　主要缺陷与修复")

h2("5.8 验收结论")
body("以「可构建、可运行、可复现、可解释」四条作为验收标准：")
table(
    ["验收项", "标准", "结果"],
    [["构建", "hvigor assembleHap 成功产出 HAP", "通过"],
     ["安装运行", "hdc 安装后五页签可正常切换", "通过"],
     ["逻辑回归", "55 项断言 0 失败", "通过"],
     ["图标自检", "24 个图标无裁切、视觉重量极差 < 1%", "通过（0.34%）"],
     ["视觉回归", "五个页签 + 记录页 + 年报 + 凭证逐页截图核验", "通过"],
     ["文档", "宋体小四、1.5 倍行距，含设计/架构/选型/测试", "本文件"]],
    [3.2, 9.2, 3.6],
    "表 14　验收结果")

# ================================================================ 六、因子库
doc.add_page_break()
h1("六、碳排放因子库：每个数字都能追溯")

h2("6.1 折算公式")
body("减排量按「基准情景与实际情景的差值」计算：", indent=False)
p = doc.add_paragraph(); fmt_para(p, first_indent=False, align=WD_ALIGN_PARAGRAPH.CENTER, before=6, after=6)
r = p.add_run("ER = AD × ( EF基准 - EF实际 )"); set_run(r, size=Pt(13), bold=True)
body("ER 为减排量（kg CO₂e）；AD 为活动量（公里 / 度 / 立方米 / 公斤 / 餐次）；"
     "EF基准 为被替代的高碳行为因子；EF实际 为实际低碳行为因子。"
     "应用内所有因子数值都已经是两者的差值，即减排量而非排放量。")

h2("6.2 数据来源")
bullet("**CPCD** 中国产品全生命周期温室气体排放系数库：本土数据，用于出行与回收塑料。")
bullet("**生态环境部 / 国家统计局**《关于发布 2023 年电力二氧化碳排放因子的公告》"
       "（公告 2025 年第 47 号）：用于节约用电，河南省 0.5897 kgCO₂/kWh。")
bullet("**DEFRA 2025** 英国温室气体换算因子：用于中国官方尚未发布对应因子的条目"
       "（回收废纸、回收铝、回收旧衣物、供水与污水处理），应用内逐条标注「英国口径」。")
bullet("**中科院地理所 × WWF**《中国城市餐饮食物浪费报告》（2018）与 "
       "**FAO**《Food Wastage Footprint》（2013）：用于光盘行动。")

h2("6.3 因子明细")
table(
    ["类目", "行为", "单位", "因子值", "基准情景", "出处"],
    [["出行", "步行", "公里", "0.19567", "燃油小汽车", "CPCD 2023"],
     ["出行", "骑行", "公里", "0.19567", "燃油小汽车", "CPCD 2023"],
     ["出行", "地铁出行", "公里", "0.15253", "燃油小汽车", "CPCD 2023 差值"],
     ["出行", "公交出行", "公里", "0.14267", "燃油小汽车", "CPCD 2023 差值"],
     ["出行", "新能源车", "公里", "0.02567", "燃油小汽车", "CPCD 2023 差值"],
     ["节水节电", "节约用电", "度", "0.5897", "等量电网供电", "公告 2025 年第 47 号（河南）"],
     ["节水节电", "少开空调", "度", "0.5897", "等量电网供电", "同上"],
     ["节水节电", "节约用水", "立方米", "0.36218", "供水与污水处理", "DEFRA 2025"],
     ["旧物回收", "回收塑料（PET）", "公斤", "0.3208", "原生 PET 生产", "CPCD 2022 差值"],
     ["旧物回收", "回收废纸", "公斤", "0.2197", "原生纸浆", "DEFRA 2025"],
     ["旧物回收", "回收易拉罐（铝）", "公斤", "8.1208", "原生铝电解", "DEFRA 2025"],
     ["旧物回收", "回收旧衣物", "公斤", "22.1578", "新纺织面料", "DEFRA 2025"],
     ["光盘行动", "光盘行动", "餐次", "0.19", "每餐平均浪费量折算", "中科院 × FAO 折算"],
     ["光盘行动", "减少食物浪费", "公斤", "2.06", "混合食物碳强度均值", "FAO 2013 折算"]],
    [2.0, 4.0, 1.4, 1.9, 3.6, 3.6],
    "表 15　内置 14 条因子",
    fs=Pt(9.5))

h2("6.4 口径说明与局限")
body("**其一，出行基准是单人驾车。** 基准值 0.19567 kgCO₂e/车·公里来自 CPCD 中型汽油轿车"
     "「大门到坟墓」口径，并假设单人驾车。若多人共乘，人均排放应除以乘员数；"
     "本作品暂未做此折算，已在应用内说明。")
body("**其二，部分条目采用英国口径。** 回收类、节水类与光盘行动类因子，"
     "中国官方尚未发布对应数值，应用内以「英国口径」明确标注，不做模糊处理。")
body("**其三，少开空调按电量而非小时计量。** 每小时耗电随匹数、能效与环境温度差异极大，"
     "没有权威出处可依，按小时计量会引入不可控误差。")
body("另有两处容易误用的资料需要澄清：生态环境部《大型活动碳中和实施指南（试行）》"
     "本身不含排放因子数值，只给出「排放源对应哪份标准」的对照关系，"
     "本作品将其作为合规性依据而非数值来源；《省级温室气体清单编制指南》属于区域清单方法学，"
     "其中没有「每人公里」口径的交通因子，不能直接用作个人出行因子。")

# ================================================================ 七、部署与运行
doc.add_page_break()
h1("七、部署与运行")

h2("7.1 环境要求")
bullet("DevEco Studio 26.0.0（本项目实测版本）。")
bullet("HarmonyOS SDK，工程声明 compatibleSdkVersion 5.0.0(12)。")
bullet("Node.js（hvigor 自带）与 ohpm。")
bullet("工程路径不能包含中文；工作区源码需同步到纯英文路径后构建。")

h2("7.2 从零构建")
body("仓库是自包含的。克隆后执行：")
p = doc.add_paragraph(); fmt_para(p, first_indent=False, ls=1.3, before=2, after=2)
r = p.add_run("cd project/carbon-footprint\nohpm install\n./hvigorw assembleHap --no-daemon")
set_run(r, size=BODY, font="Consolas", color=INK2)
body("依赖只有 `@ohos/mpchart` 一个，还原后可完全离线构建。"
     "本地签名使用 SDK 自带的调试材料，不需要登录华为账号。")

h2("7.3 安装与运行")
body("`tools/preview.sh build` 会同步源码到 `/tmp/carbon-footprint`、构建并签名；"
     "`tools/emulator.sh start && tools/emulator.sh wait` 启动模拟器；"
     "`tools/preview.sh all` 安装并逐页截图。真机安装使用 hdc install 安装签名后的 HAP。")

h2("7.4 回归命令")
table(
    ["命令", "作用", "期望"],
    [["`tools/test-logic.sh`", "55 项纯逻辑断言", "55 passed / 0 failed"],
     ["`python3 tools/icon/check_icons.py`", "24 个图标自检", "无裁切，极差 0.34%"],
     ["`tools/preview.sh build`", "构建 + 签名", "BUILD SUCCESSFUL"],
     ["`tools/preview.sh all`", "安装 + 五页截图", "五张截图"],
     ["`tools/look.sh <名字>`", "细节迭代（裁印章放大 4×）", "约 20 秒往返"]],
    [6.2, 6.4, 3.4],
    "表 16　常用命令")

h2("7.5 兼容性说明")
body("工程在 API 12 上编译与运行，未使用 API 13 及以上才有的接口。"
     "分布式与端侧 AI 能力依赖设备支持：模拟器不具备分布式软总线，"
     "Core Vision Kit 不支持模拟器；这两项在真机上的行为需按第八章的验证清单确认。")

# ================================================================ 八、局限与规划
h1("八、已知限制与后续规划")

h2("8.1 当前限制")
table(
    ["项目", "当前状态", "原因"],
    [["多设备同步", "界面、业务逻辑、冲突合并已完成；同步面板可展示状态；"
      "尚未在两台真机间做端到端验证", "模拟器不具备分布式软总线，同步权限需真机授权"],
     ["端侧 AI 类目标定", "推理链路可自检；「索引 → 类目」标定表仍为空，视觉通路暂不产出建议；"
      "文字识别未在设备上验证", "标定必须用真实拍摄照片；Core Vision Kit 不支持模拟器"],
     ["城市碳普惠", "本地模拟实现，保留真实接口语义", "平台未对个人开发者开放接口"],
     ["深色模式", "未实现", "纸墨关系需整体反转为「夜账」，要把颜色常量改为资源引用，是一次重构"],
     ["图表图例字体", "仍为系统黑体", "mpchart 改字体需 setTypeface 并把 OTF 打进 assets，成本较高"]],
    [3.2, 8.2, 4.8],
    "表 17　已知限制")

h2("8.2 后续规划")
bullet("**补真机验证**：两台设备完成分布式同步；用真实照片完成 AI 类目标定，"
       "把「能跑通」推进到「识别准」。")
bullet("**因子库更新**：中国官方发布回收类与节水类因子后及时替换，保留旧口径作为对照。")
bullet("**目标与提醒**：在数据积累到一定规模后，引入周/月减排目标与达成提醒，强化习惯养成。")
bullet("**深色模式**：把纸墨关系反转为夜账，作为一次完整的资源化改造。")

h2("8.3 一句话总结")
callout("设计原则",
        "把每一个数字都算清楚，把每一个来源都标明白，把每一点能力边界都如实说明。"
        "界面可以简洁，但数据必须可核对；功能可以有边界，但边界必须写清楚。")

# ================================================================ 参考文献
h1("参考文献")
refs = [
    "生态环境部，国家统计局．关于发布 2023 年电力二氧化碳排放因子的公告（公告 2025 年第 47 号）．2025．",
    "中国产品全生命周期温室气体排放系数库（CPCD）．2022–2023．",
    "UK Department for Environment, Food & Rural Affairs (DEFRA). Greenhouse Gas Conversion Factors 2025.",
    "联合国粮农组织（FAO）. Food Wastage Footprint: Impacts on Natural Resources. 2013.",
    "中国科学院地理科学与资源研究所，世界自然基金会．中国城市餐饮食物浪费报告．2018．",
    "华为．HarmonyOS 设计规范 / ArkUI 开发文档 / 分布式数据服务开发指南．2025．",
    "rough-stuff/rough：手绘风格图形库（MIT）．https://github.com/rough-stuff/rough",
    "Noto Serif CJK（SIL Open Font License 1.1）．",
]
for i, ref in enumerate(refs, 1):
    p = doc.add_paragraph()
    fmt_para(p, first_indent=False, after=3, ls=1.5)
    p.paragraph_format.left_indent = Cm(0.74)
    p.paragraph_format.first_line_indent = Cm(-0.74)
    r = p.add_run(f"[{i}] "); set_run(r, size=BODY, color=INK3)
    add_rich(p, ref, size=BODY, color=INK2)

# ================================================================ 附录
h1("附录 A　术语表")
table(
    ["术语", "含义"],
    [["减排量（ER）", "基准情景排放量与实际情景排放量之差，单位 kg CO₂e"],
     ["碳排放因子（EF）", "单位活动量对应的碳排放量，本作品中为差值"],
     ["碳普惠", "把个人低碳行为量化为积分并兑换权益的机制"],
     ["分布式 KV", "HarmonyOS 的分布式键值数据库，支持多设备同步"],
     ["信封", "本作品的写入结构 { payload, ts, origin }，用于冲突合并"],
     ["短板优先", "任务推荐规则：优先推荐用户记录最少的类目"],
     ["tnum", "等宽数字字体特性，让数字按位对齐"]],
    [4.2, 11.8],
    "表 A-1　术语表")

h1("附录 B　复现清单")
body("本文档中的关键结论均可由以下材料复现：")
bullet("工程源码：`project/carbon-footprint`（构建、安装、截图脚本在 `tools/`）。")
bullet("逻辑测试：`tools/test-logic.sh`（55 项）。")
bullet("图标自检：`tools/icon/check_icons.py`（24 个）。")
bullet("截图：`素材/截图/v3.3/` 与 `素材/截图/质量改进/`（本文件所用图；后者为 v3.4 信息架构改动后的页面）。")
bullet("视觉改造记录：`视觉改造v3-碳账本.md`（诊断、改动清单、字体复现、三稿抖动）。")
bullet("信息架构记录：`信息架构_去堆叠改动.md`（一屏一主题、合并 / 下沉 / 替换三种落法与逐页判断）。")
bullet("交接文档：`交接文档-v3账本-下一会话.md`（环境、文件地图、ArkUI 陷阱）。")

# 文档属性
cp = doc.core_properties
cp.author = ""
cp.last_modified_by = ""
cp.title = "碳迹 —— 设计方案"
cp.subject = "赛题二 碳足迹·全民绿色生活碳积分与减排指南"
cp.comments = ""
cp.category = ""
cp.keywords = ""

os.makedirs(os.path.dirname(OUT), exist_ok=True)
doc.save(OUT)
print("saved", os.path.abspath(OUT))
