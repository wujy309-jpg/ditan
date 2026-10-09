#!/usr/bin/env python3
"""生成《碳迹》演示文稿（PPTX）。

规格要求（来自大赛通知）：
  · 图文并茂，内容完整、简明扼要
  · 重点展示设计亮点、功能实现、创新点
  · 讲解时长控制在 10 分钟以内
  · ⚠️ 不得出现参赛团队、指导老师、院校信息

用法：python3 tools/docs/make_ppt.py

截图说明（2026-09-30 前端视觉美化后重拍）：
  · 取图目录仍是 素材/截图/，但**文件名与旧版完全不同**，旧文件已备份到
    素材/截图/旧版-改造前/，不要再引用旧名字。
  · 截图内容与文件名的对应关系已在 SHOTS 注释中逐条核对（有几张是「滚动位置
    与命名不一致」的连续帧，见各页 caption，caption 只描述画面里真实存在的内容）。
  · 热力图页用到两张**裁剪图**：从 03 截「减排日历」卡片标题与网格、从 04 截
    四档色阶图例。裁剪在构建时用 PIL 完成，不修改素材文件本身。
"""
import os

from PIL import Image
from pptx import Presentation
from pptx.dml.color import RGBColor
from pptx.enum.shapes import MSO_SHAPE
from pptx.enum.text import MSO_ANCHOR, PP_ALIGN
from pptx.oxml.ns import qn
from pptx.util import Emu, Inches, Pt

OUT = "交付物/演示文稿_碳迹.pptx"   # 与 make_video.py 一致：从仓库根目录运行，直接写进交付物/
SHOT_DIR = "素材/截图"
ASSET_DIR = "素材"
FIG_DIR = "/tmp/carbon-ppt-figs"      # 构建期裁剪出的派生图，不写进交付物目录
CROP_BASE = (1320, 2232)              # 手机截图的基准分辨率，换分辨率时按比例缩放裁剪框


def fig(path, crop=None):
    """返回可直接插入的图片路径。

    crop=(left, top, right, bottom)，单位是**基准分辨率 1320×2232 下的像素**；
    实际截图分辨率不同则等比缩放，避免换机重拍后裁剪框错位。
    """
    if not crop:
        return path
    os.makedirs(FIG_DIR, exist_ok=True)
    im = Image.open(path)
    sx, sy = im.width / CROP_BASE[0], im.height / CROP_BASE[1]
    box = (int(crop[0] * sx), int(crop[1] * sy),
           int(crop[2] * sx), int(crop[3] * sy))
    name = os.path.splitext(os.path.basename(path))[0]
    out = os.path.join(FIG_DIR, f"{name}-crop-{box[0]}_{box[1]}_{box[2]}_{box[3]}.png")
    if not os.path.exists(out):
        im.crop(box).save(out)
    return out

GREEN = RGBColor(0x1F, 0x9A, 0x4E)
GREEN_DARK = RGBColor(0x14, 0x6B, 0x36)
GREEN_LIGHT = RGBColor(0xE8, 0xF3, 0xEC)
INK = RGBColor(0x1B, 0x27, 0x33)
GREY = RGBColor(0x5A, 0x6B, 0x7B)
GREY_LIGHT = RGBColor(0x8A, 0x98, 0xA6)
WHITE = RGBColor(0xFF, 0xFF, 0xFF)
AMBER = RGBColor(0xD9, 0x8A, 0x00)

FONT = "微软雅黑"
SW = Inches(13.333)
SH = Inches(7.5)


def set_font(run, size=18, bold=False, color=INK, font=FONT):
    """设置字体。中文必须额外写入 a:ea，否则 PowerPoint 会用默认宋体。"""
    run.font.size = Pt(size)
    run.font.bold = bold
    run.font.color.rgb = color
    run.font.name = font
    rPr = run._r.get_or_add_rPr()
    for tag in ("a:ea", "a:cs"):
        el = rPr.find(qn(tag))
        if el is None:
            el = rPr.makeelement(qn(tag), {})
            rPr.append(el)
        el.set("typeface", font)


def textbox(slide, x, y, w, h, align=PP_ALIGN.LEFT, anchor=MSO_ANCHOR.TOP):
    tb = slide.shapes.add_textbox(x, y, w, h)
    tf = tb.text_frame
    tf.word_wrap = True
    tf.vertical_anchor = anchor
    tf.paragraphs[0].alignment = align
    return tf


def para(tf, text, size=18, bold=False, color=INK, first=False,
         space_before=0, space_after=6, align=PP_ALIGN.LEFT, level=0):
    p = tf.paragraphs[0] if first else tf.add_paragraph()
    p.alignment = align
    p.level = level
    p.space_before = Pt(space_before)
    p.space_after = Pt(space_after)
    run = p.add_run()
    run.text = text
    set_font(run, size=size, bold=bold, color=color)
    return p


def rect(slide, x, y, w, h, fill=GREEN, line=None, shape=MSO_SHAPE.ROUNDED_RECTANGLE,
         radius=0.08):
    s = slide.shapes.add_shape(shape, x, y, w, h)
    s.fill.solid()
    s.fill.fore_color.rgb = fill
    if line is None:
        s.line.fill.background()
    else:
        s.line.color.rgb = line
        s.line.width = Pt(1)
    s.shadow.inherit = False
    if shape == MSO_SHAPE.ROUNDED_RECTANGLE:
        try:
            s.adjustments[0] = radius
        except Exception:
            pass
    return s


def blank(prs):
    return prs.slides.add_slide(prs.slide_layouts[6])


def header(slide, title, sub=None):
    """统一的内页页头：左侧竖条 + 标题（+ 副标题）。"""
    rect(slide, Inches(0.55), Inches(0.42), Inches(0.09), Inches(0.46),
         fill=GREEN, shape=MSO_SHAPE.RECTANGLE)
    tf = textbox(slide, Inches(0.78), Inches(0.32), Inches(11.9), Inches(0.7))
    para(tf, title, size=26, bold=True, color=INK, first=True, space_after=0)
    y = Inches(1.06)
    if sub:
        tf2 = textbox(slide, Inches(0.8), Inches(0.92), Inches(11.9), Inches(0.4))
        para(tf2, sub, size=13, color=GREY_LIGHT, first=True, space_after=0)
        y = Inches(1.36)
    return y


def footer(slide, text):
    tf = textbox(slide, Inches(0.8), Inches(7.0), Inches(11.9), Inches(0.35))
    para(tf, text, size=10, color=GREY_LIGHT, first=True, space_after=0)


# ---------------------------------------------------------------------------
def slide_cover(prs):
    slide = blank(prs)
    rect(slide, 0, 0, SW, SH, fill=GREEN, shape=MSO_SHAPE.RECTANGLE)

    tf = textbox(slide, Inches(1.0), Inches(2.1), Inches(11.3), Inches(1.4),
                 align=PP_ALIGN.CENTER)
    para(tf, "碳  迹", size=60, bold=True, color=WHITE, first=True,
         align=PP_ALIGN.CENTER, space_after=4)

    tf = textbox(slide, Inches(1.0), Inches(3.5), Inches(11.3), Inches(0.7),
                 align=PP_ALIGN.CENTER)
    para(tf, "碳足迹 · 全民绿色生活碳积分与减排指南", size=22, color=WHITE,
         first=True, align=PP_ALIGN.CENTER)

    tf = textbox(slide, Inches(1.0), Inches(4.35), Inches(11.3), Inches(0.5),
                 align=PP_ALIGN.CENTER)
    para(tf, "赛题二", size=16, color=RGBColor(0xD7, 0xE8, 0xDC), first=True,
         align=PP_ALIGN.CENTER)

    # 底部三个关键词
    labels = ["量化减排", "积分激励", "碳普惠回馈"]
    for i, t in enumerate(labels):
        x = Inches(4.03 + i * 1.9)
        s = rect(slide, x, Inches(5.5), Inches(1.7), Inches(0.5),
                 fill=RGBColor(0x17, 0x83, 0x42))
        tf = s.text_frame
        tf.vertical_anchor = MSO_ANCHOR.MIDDLE
        para(tf, t, size=14, color=WHITE, first=True, align=PP_ALIGN.CENTER,
             space_after=0)


def slide_agenda(prs):
    slide = blank(prs)
    header(slide, "汇报要点")
    items = [
        ("01", "选题背景与设计思路", "为什么做、怎么做、有哪些取舍"),
        ("02", "功能实现与演示", "五个主要功能 + 四个创新拓展"),
        ("03", "技术架构与选型", "分层架构、数据层关键决策"),
        ("04", "碳排放因子库来源", "每个数字都能追溯到出处"),
        ("05", "测试与验证", "真机实测结果与已知限制"),
    ]
    y = Inches(1.5)
    for num, title, desc in items:
        box = rect(slide, Inches(0.8), y, Inches(11.7), Inches(0.92),
                   fill=GREEN_LIGHT, radius=0.12)
        tf = box.text_frame
        tf.vertical_anchor = MSO_ANCHOR.MIDDLE
        tf.margin_left = Inches(0.3)
        p = tf.paragraphs[0]
        r1 = p.add_run(); r1.text = num + "   "
        set_font(r1, size=20, bold=True, color=GREEN)
        r2 = p.add_run(); r2.text = title
        set_font(r2, size=19, bold=True, color=INK)
        r3 = p.add_run(); r3.text = "      " + desc
        set_font(r3, size=13, color=GREY)
        y += Inches(1.06)


def slide_background(prs):
    slide = blank(prs)
    header(slide, "选题背景", "「双碳」目标需要公众参与这一环")
    body = [
        "我国提出「双碳」目标：二氧化碳排放力争 2030 年前达到峰值，努力争取 2060 年前实现碳中和。",
        "工业与能源领域的减排路径相对清晰，但**公众日常行为的减排贡献长期难以量化**——",
        "一个人少开一天车、少浪费一顿饭，到底减了多少碳？这个数字没人告诉他。",
        "没有量化，就没有反馈；没有反馈，低碳行为就很难坚持。",
    ]
    tf = textbox(slide, Inches(0.8), Inches(1.6), Inches(11.7), Inches(2.2))
    for i, t in enumerate(body):
        para(tf, t, size=16, color=INK if i != 3 else GREEN_DARK,
             bold=(i == 3), first=(i == 0), space_after=8)

    # 三个现状痛点
    pains = [
        ("算不清", "不知道自己的行为对应多少碳排放"),
        ("坚持难", "缺少即时反馈与正向激励"),
        ("没回馈", "减排了也换不来任何实际权益"),
    ]
    for i, (t, d) in enumerate(pains):
        x = Inches(0.8 + i * 4.0)
        rect(slide, x, Inches(4.0), Inches(3.7), Inches(1.9), fill=GREEN_LIGHT,
             radius=0.1)
        tf = textbox(slide, x + Inches(0.3), Inches(4.2), Inches(3.1), Inches(1.5))
        para(tf, t, size=20, bold=True, color=GREEN, first=True, space_after=6)
        para(tf, d, size=13, color=GREY)

    tf = textbox(slide, Inches(0.8), Inches(6.15), Inches(11.7), Inches(0.6))
    para(tf, "本作品要做的，就是把这条链路补上：让每一次低碳行为都被算清楚、被记录、被回馈。",
         size=15, bold=True, color=GREEN_DARK, first=True)


def slide_approach(prs):
    slide = blank(prs)
    header(slide, "设计思路", "围绕「量化 — 激励 — 回馈」做成闭环")
    steps = [
        ("量化", "行为量 × 碳排放因子", "四类日常行为折算为可比较的减排量（kg CO₂e）"),
        ("激励", "减排量 → 碳积分", "每日任务、虚拟徽章与电子证书形成正反馈"),
        ("回馈", "积分 → 真实权益", "上报城市碳普惠平台，兑换地铁券、单车券"),
    ]
    for i, (t, f, d) in enumerate(steps):
        x = Inches(0.8 + i * 4.0)
        rect(slide, x, Inches(1.6), Inches(3.7), Inches(2.1), fill=GREEN, radius=0.1)
        tf = textbox(slide, x + Inches(0.28), Inches(1.78), Inches(3.15), Inches(1.8))
        para(tf, t, size=24, bold=True, color=WHITE, first=True, space_after=6)
        para(tf, f, size=14, bold=True, color=RGBColor(0xD7, 0xE8, 0xDC),
             space_after=6)
        para(tf, d, size=12, color=RGBColor(0xD7, 0xE8, 0xDC))
        if i < 2:
            arrow = rect(slide, x + Inches(3.74), Inches(2.42), Inches(0.22),
                         Inches(0.4), fill=GREEN_LIGHT, shape=MSO_SHAPE.RIGHT_ARROW)

    tf = textbox(slide, Inches(0.8), Inches(4.0), Inches(11.7), Inches(0.5))
    para(tf, "三处刻意的取舍", size=19, bold=True, color=INK, first=True)

    trades = [
        ("数据不出设备", "全量本地存储、完全离线可用。\n碳账本属于个人数据，\n这既是隐私优势，\n也让演示不依赖网络。"),
        ("AI 只预填不判定", "高置信才自动填表，\n低置信交给用户确认。\n通用模型分不清\n新能源车与燃油车。"),
        ("因子必须可追溯", "每条因子标注来源与基准。\n答辩时能逐条讲清\n「这个数是怎么来的」。"),
    ]
    for i, (t, d) in enumerate(trades):
        x = Inches(0.8 + i * 4.0)
        rect(slide, x, Inches(4.6), Inches(3.7), Inches(2.1), fill=GREEN_LIGHT,
             radius=0.1)
        tf = textbox(slide, x + Inches(0.28), Inches(4.78), Inches(3.15), Inches(1.8))
        para(tf, t, size=17, bold=True, color=GREEN_DARK, first=True, space_after=6)
        para(tf, d, size=12, color=GREY, space_after=0)


def slide_features(prs):
    slide = blank(prs)
    header(slide, "功能总览", "五个主要功能全部实现，四个创新拓展全部实现，视觉体系整体返工")
    rows = [
        ["主要功能 1", "低碳行为核算", "四类行为录入，内置因子库自动折算减排量"],
        ["主要功能 2", "数据可视化看板", "折线 / 柱状 / 环形图 + 减排日历热力图，日周月年粒度切换"],
        ["主要功能 3", "碳积分激励体系", "每 kg CO₂e 得 100 积分，勋章墙与电子证书兑换"],
        ["主要功能 4", "双碳科普专栏", "8 篇图文科普，按政策/概念/数据/技巧分类"],
        ["主要功能 5", "本地数据管理", "JSON 备份与 CSV 报表导出，全程离线"],
        ["创新拓展 1", "超级终端多设备同步", "分布式数据服务 + 同步状态可视化面板"],
        ["创新拓展 2", "端侧 AI 图片识别", "端侧推理 + 端侧 OCR 双通路，离线不出设备"],
        ["创新拓展 3", "模拟城市碳普惠接口", "账户/上报/权益/兑换/订单完整链路"],
        ["创新拓展 4", "智能服务与社交分享", "短板优先任务推荐 + 减排成果分享图"],
        ["新增页面", "我的年度碳迹（年度报告）", "从看板一键进入，全年汇总与减排构成一页读完"],
        ["鸿蒙特色", "桌面服务卡片", "不开应用即可看今日碳数据，点卡片直达记录页"],
    ]
    y = Inches(1.4)
    rh = Inches(0.5)
    for i, (a, b, c) in enumerate(rows):
        is_new = a.startswith("创新") or a.startswith("新增")
        bg = RGBColor(0xFF, 0xF8, 0xE8) if is_new else GREEN_LIGHT
        rect(slide, Inches(0.8), y, Inches(11.7), rh, fill=bg, radius=0.14)
        tf = textbox(slide, Inches(1.0), y + Inches(0.05), Inches(1.5), Inches(0.4),
                     anchor=MSO_ANCHOR.MIDDLE)
        para(tf, a, size=12, bold=True,
             color=AMBER if is_new else GREEN, first=True, space_after=0)
        tf = textbox(slide, Inches(2.5), y + Inches(0.05), Inches(3.3), Inches(0.4),
                     anchor=MSO_ANCHOR.MIDDLE)
        para(tf, b, size=13, bold=True, color=INK, first=True, space_after=0)
        tf = textbox(slide, Inches(5.9), y + Inches(0.05), Inches(6.4), Inches(0.4),
                     anchor=MSO_ANCHOR.MIDDLE)
        para(tf, c, size=12, color=GREY, first=True, space_after=0)
        y += Inches(0.55)


def slide_shots(prs, title, sub, images, note=None, foot=None, img_ratio=1320 / 2232,
                top=1.55, avail_h=4.55):
    """截图页：横向排布若干张手机截图 + 图注 + 一行结论。

    images 里每项为 (路径, 图注) 或 (路径, 图注, 裁剪框)；裁剪框见 fig()。
    """
    slide = blank(prs)
    header(slide, title, sub)
    n = len(images)
    top = Inches(top)
    avail_h = Inches(avail_h)
    avail_w = Inches(11.7)
    gap = Inches(0.3)
    each_w = int((avail_w - gap * (n - 1)) / n)
    # 手机截图是竖版，按高度约束反推宽度，避免拉伸
    img_h = avail_h
    img_w = int(img_h * img_ratio)
    if img_w > each_w:
        img_w = each_w
        img_h = int(img_w / img_ratio)
    total = img_w * n + gap * (n - 1)
    x0 = int((SW - total) / 2)
    for i, item in enumerate(images):
        path, cap = item[0], item[1]
        crop = item[2] if len(item) > 2 else None
        path = fig(path, crop)
        if os.path.exists(path):
            slide.shapes.add_picture(path, x0 + i * (img_w + gap), top,
                                     width=img_w, height=img_h)
        tf = textbox(slide, x0 + i * (img_w + gap), top + img_h + Inches(0.06),
                     img_w, Inches(0.3), align=PP_ALIGN.CENTER)
        para(tf, cap, size=11, color=GREY_LIGHT, first=True,
             align=PP_ALIGN.CENTER, space_after=0)
    if note:
        tf = textbox(slide, Inches(0.8), top + img_h + Inches(0.45),
                     Inches(11.7), Inches(0.6))
        para(tf, note, size=13, color=GREEN_DARK, bold=True, first=True)
    if foot:
        footer(slide, foot)


def slide_heatmap(prs):
    """新增页：减排日历热力图 —— 补上「打卡类三件套」的最后一件。"""
    slide = blank(prs)
    header(slide, "数据可视化 · 减排日历热力图",
           "本次视觉改造新增：最近 12 周 × 7 天，四档色阶 + 连续记录天数")

    # 左：两张裁剪图（同一次滚动的上下两段），拼成完整的日历卡片
    left_w = Inches(5.6)
    x = Inches(0.85)
    y = Inches(1.6)
    for src, crop, cap, w in [
        (f"{SHOT_DIR}/03-看板-总览.jpeg", (40, 1395, 1280, 1972),
         "「减排日历」卡片：最近 12 周网格 + 连续记录天数", 5.6),
        (f"{SHOT_DIR}/04-看板-减排日历.jpeg", (40, 150, 1280, 525),
         "四档色阶与图例（少 → 多，每格 = 一天）", 5.6),
    ]:
        p = fig(src, crop)
        if not os.path.exists(p):
            continue
        im = Image.open(p)
        h = int(w * im.height / im.width)
        slide.shapes.add_picture(p, x, y, width=Inches(w), height=Inches(h))
        tf = textbox(slide, x, y + Inches(h) + Inches(0.04), Inches(w), Inches(0.28),
                     align=PP_ALIGN.CENTER)
        para(tf, cap, size=10.5, color=GREY_LIGHT, first=True,
             align=PP_ALIGN.CENTER, space_after=0)
        y += Inches(h) + Inches(0.36)

    # 右：为什么加、怎么做的
    bullets = [
        ("让「坚持」看得见",
         "把每天的减排量铺成 12 周 × 7 天的格子，每格一天；连续记录天数用火焰徽章直接给出。"),
        ("四档色阶，不用图例也能读",
         "按当日减排量分档着色，无记录为浅灰；卡片底部给出「少 → 多」图例与「每格 = 一天」标注。"),
        ("只用系统原生能力",
         "网格由 ArkUI 原生布局绘制，没有引入第三方日历库，也不增加安装包体积。"),
        ("和统计粒度联动",
         "日历始终展示最近 12 周，与上方日 / 周 / 月 / 年粒度互不干扰，可同时对照。"),
    ]
    y = Inches(1.75)
    for t, d in bullets:
        rect(slide, Inches(6.75), y, Inches(5.75), Inches(1.05), fill=GREEN_LIGHT,
             radius=0.12)
        tf = textbox(slide, Inches(7.0), y + Inches(0.12), Inches(5.25), Inches(0.85))
        para(tf, t, size=14.5, bold=True, color=GREEN_DARK, first=True, space_after=3)
        para(tf, d, size=11.5, color=GREY, space_after=0)
        y += Inches(1.15)

    footer(slide, "实测数据：最近 12 周共 6 天有记录，连续 1 天；色阶按当日减排量分档。")


def slide_visual(prs):
    """新增页：视觉改造前后对比 —— 本次交付物更新的直接证据。"""
    slide = blank(prs)
    header(slide, "视觉改造 · 改造前 vs 改造后",
           "不是「重新配色」，而是把《HarmonyOS 设计规范》的官方 Token 真正落到每一个页面")

    img = f"{ASSET_DIR}/改造前后对比-前端美化.png"
    if os.path.exists(img):
        w = 7.05
        im = Image.open(img)
        h = w * im.height / im.width
        slide.shapes.add_picture(img, Inches(0.8), Inches(1.55),
                                 width=Inches(w), height=Inches(h))
        tf = textbox(slide, Inches(0.8), Inches(1.55) + Inches(h) + Inches(0.05),
                     Inches(w), Inches(0.3), align=PP_ALIGN.CENTER)
        para(tf, "六组「改造前 / 改造后」并排对比（含新增的年度报告页）", size=10.5,
             color=GREY_LIGHT, first=True, align=PP_ALIGN.CENTER, space_after=0)

    bullets = [
        ("统一英雄区", "五个页面都用「渐变英雄区」开场，按页面气质分三档绿色，但每页主角不同。"),
        ("卡片默认投影", "把「卡片长什么样」收敛到一个公共组件，投影成为默认行为，而不是逐页手写。"),
        ("列表图标化", "科普、积分、同步等列表一律加图标块，同一屏里的信息密度立刻变得可读。"),
        ("弹簧动效", "页签切换、类目选中、保存、展开折叠、环形进度共 9 处 animateTo，全工程从 0 到 9。"),
    ]
    y = Inches(1.6)
    for t, d in bullets:
        tf = textbox(slide, Inches(8.05), y, Inches(4.5), Inches(0.95))
        para(tf, t, size=15, bold=True, color=GREEN_DARK, first=True, space_after=3)
        para(tf, d, size=11.5, color=GREY, space_after=0)
        y += Inches(1.02)

    tf = textbox(slide, Inches(8.05), Inches(5.85), Inches(4.5), Inches(1.1))
    para(tf, "可复现的量化结果", size=13, bold=True, color=INK, first=True,
         space_after=4)
    for t in ["裸写颜色 104 处 → 12 处，孤儿色 12 种 → 0 种",
              "官方字号令牌采纳 26 次 → 114 次",
              "饼图百分比显示缺陷（曾达 2841%）已修复"]:
        para(tf, "· " + t, size=11, color=GREY, space_after=2)


def slide_card(prs):
    """桌面服务卡片 —— 本作品最有辨识度的鸿蒙特色。"""
    slide = blank(prs)
    header(slide, "鸿蒙特色 · 桌面服务卡片", "不用打开应用，桌面上就能看到今日碳数据")

    img = f"{SHOT_DIR}/14-服务卡片-特写.png"
    if os.path.exists(img):
        slide.shapes.add_picture(img, Inches(0.85), Inches(1.75),
                                 height=Inches(4.4))

    bullets = [
        ("不开应用也能看", "今日减排量、碳积分、近 7 日迷你趋势、个性化提示，全部常驻桌面。"),
        ("三种尺寸自适应", "支持 2×2 / 2×4 / 4×4，随桌面布局自由摆放。"),
        ("数据实时同步", "新增记录后主应用主动通知卡片刷新；系统也会定期拉取。"),
        ("点击直达应用", "点卡片直接进入记录页，省掉找图标这一步。"),
    ]
    y = Inches(1.85)
    for t, d in bullets:
        rect(slide, Inches(6.6), y, Inches(5.9), Inches(1.0), fill=GREEN_LIGHT,
             radius=0.12)
        tf = textbox(slide, Inches(6.85), y + Inches(0.12), Inches(5.4), Inches(0.8))
        para(tf, t, size=15, bold=True, color=GREEN_DARK, first=True, space_after=3)
        para(tf, d, size=11.5, color=GREY, space_after=0)
        y += Inches(1.12)

    tf = textbox(slide, Inches(0.85), Inches(6.35), Inches(11.7), Inches(0.5))
    para(tf, "这是其它平台复刻不了的能力：安卓与小程序都没有等价的桌面常驻卡片机制。",
         size=13, bold=True, color=GREEN_DARK, first=True)


def slide_arch(prs):
    slide = blank(prs)
    header(slide, "技术架构", "四层结构，自上而下")
    layers = [
        ("表现层", "五个功能页签的界面与交互", "记一笔 · 看板 · 积分 · 科普 · 我的"),
        ("业务层", "领域逻辑", "减排计算 · 积分规则 · 任务推荐 · 碳普惠流程"),
        ("数据层", "统一数据存取与跨设备同步", "CarbonRepository（仓储） · DistributedStore（分布式 KV）"),
        ("能力层", "鸿蒙系统能力", "分布式 KV · 设备管理 · MindSpore Lite · Core Vision Kit · 组件快照"),
    ]
    y = Inches(1.6)
    for i, (a, b, c) in enumerate(layers):
        shade = [GREEN, RGBColor(0x27, 0xA8, 0x5A), RGBColor(0x3F, 0xB2, 0x73),
                 RGBColor(0x6B, 0xC4, 0x91)][i]
        rect(slide, Inches(0.8), y, Inches(11.7), Inches(1.05), fill=shade,
             radius=0.1)
        tf = textbox(slide, Inches(1.1), y + Inches(0.12), Inches(2.0), Inches(0.8))
        para(tf, a, size=18, bold=True, color=WHITE, first=True, space_after=2)
        tf = textbox(slide, Inches(3.2), y + Inches(0.13), Inches(9.0), Inches(0.8))
        para(tf, b, size=14, bold=True, color=WHITE, first=True, space_after=2)
        para(tf, c, size=12, color=RGBColor(0xE4, 0xF4, 0xEA), space_after=0)
        y += Inches(1.18)


def slide_datadecision(prs):
    slide = blank(prs)
    header(slide, "数据层的关键决策", "为什么用分布式键值库，而不是关系型数据库")
    rect(slide, Inches(0.8), Inches(1.55), Inches(5.6), Inches(2.5),
         fill=RGBColor(0xFB, 0xEA, 0xE8), radius=0.08)
    tf = textbox(slide, Inches(1.1), Inches(1.75), Inches(5.0), Inches(2.1))
    para(tf, "如果先用 relationalStore", size=17, bold=True,
         color=RGBColor(0xD3, 0x3A, 0x2C), first=True, space_after=10)
    for t in ["三张关系表：行为记录 / 因子库 / 积分流水",
              "第 3 周接入分布式同步时",
              "发现两套存储引擎互不通用",
              "→ 整个数据层需要重写"]:
        para(tf, t, size=13, color=GREY)

    rect(slide, Inches(6.9), Inches(1.55), Inches(5.6), Inches(2.5),
         fill=GREEN_LIGHT, radius=0.08)
    tf = textbox(slide, Inches(7.2), Inches(1.75), Inches(5.0), Inches(2.1))
    para(tf, "实际采用 distributedKVStore", size=17, bold=True,
         color=GREEN_DARK, first=True, space_after=10)
    for t in ["以「主键为 key、JSON 为 value」建模",
              "同步能力从一开始就在同一套引擎上",
              "第 3 周变成「接入一个已有组件」",
              "→ 不用重构数据层"]:
        para(tf, t, size=13, color=GREY)

    tf = textbox(slide, Inches(0.8), Inches(4.3), Inches(11.7), Inches(0.4))
    para(tf, "键设计（同一分布式库内以 carbon: 前缀隔离）", size=17,
         bold=True, color=INK, first=True)

    rows = [
        ("behavior:<id>", "一条低碳行为记录"),
        ("points:<id>", "一条积分流水（只增不改，天然免冲突）"),
        ("profile", "用户档案（单例）"),
        ("platform:account / platform:order:<id>", "碳普惠账户与兑换订单"),
    ]
    y = Inches(4.85)
    for k, v in rows:
        rect(slide, Inches(0.8), y, Inches(11.7), Inches(0.44), fill=GREEN_LIGHT,
             radius=0.16)
        tf = textbox(slide, Inches(1.05), y + Inches(0.04), Inches(4.6), Inches(0.36),
                     anchor=MSO_ANCHOR.MIDDLE)
        para(tf, k, size=12, bold=True, color=GREEN_DARK, first=True, space_after=0)
        tf = textbox(slide, Inches(5.8), y + Inches(0.04), Inches(6.4), Inches(0.36),
                     anchor=MSO_ANCHOR.MIDDLE)
        para(tf, v, size=12, color=GREY, first=True, space_after=0)
        y += Inches(0.5)


def slide_innovation(prs, tag, title, points, extra=None):
    slide = blank(prs)
    header(slide, title, f"创新拓展 {tag}")
    y = Inches(1.7)
    for i, (t, d) in enumerate(points):
        rect(slide, Inches(0.8), y, Inches(11.7), Inches(1.15), fill=GREEN_LIGHT,
             radius=0.1)
        rect(slide, Inches(1.05), y + Inches(0.22), Inches(0.7), Inches(0.7),
             fill=GREEN, shape=MSO_SHAPE.OVAL)
        tf = textbox(slide, Inches(1.05), y + Inches(0.25), Inches(0.7),
                     Inches(0.64), align=PP_ALIGN.CENTER, anchor=MSO_ANCHOR.MIDDLE)
        para(tf, str(i + 1), size=20, bold=True, color=WHITE, first=True,
             align=PP_ALIGN.CENTER, space_after=0)
        tf = textbox(slide, Inches(2.0), y + Inches(0.15), Inches(10.3), Inches(0.9))
        para(tf, t, size=16, bold=True, color=INK, first=True, space_after=4)
        para(tf, d, size=13, color=GREY, space_after=0)
        y += Inches(1.27)
    if extra:
        tf = textbox(slide, Inches(0.8), Inches(6.35), Inches(11.7), Inches(0.6))
        para(tf, extra, size=13, bold=True, color=GREEN_DARK, first=True)


def slide_factor(prs):
    slide = blank(prs)
    header(slide, "碳排放因子库：每个数字都能追溯", "答辩重点")
    rect(slide, Inches(0.8), Inches(1.5), Inches(11.7), Inches(0.85),
         fill=GREEN, radius=0.12)
    tf = textbox(slide, Inches(0.8), Inches(1.58), Inches(11.7), Inches(0.7),
                 align=PP_ALIGN.CENTER, anchor=MSO_ANCHOR.MIDDLE)
    para(tf, "ER = AD × ( EF基准 − EF实际 )      减排量 = 活动量 × 基准与实际排放因子之差",
         size=17, bold=True, color=WHITE, first=True, align=PP_ALIGN.CENTER,
         space_after=0)

    srcs = [
        ("CPCD", "中国产品全生命周期\n温室气体排放系数库", "出行类、回收塑料"),
        ("生态环境部\n公告 2025 年第 47 号", "2023 年电力二氧化碳排放因子\n（河南省 0.5897）", "节约用电、少开空调"),
        ("DEFRA 2025", "英国环境食品与农村事务部\n（中国无官方对应值时）", "回收废纸/铝/旧衣物、供水"),
        ("中科院地理所\n+ WWF + FAO", "《中国城市餐饮食物浪费报告》\n《Food Wastage Footprint》", "光盘行动"),
    ]
    for i, (a, b, c) in enumerate(srcs):
        x = Inches(0.8 + i * 2.98)
        rect(slide, x, Inches(2.6), Inches(2.78), Inches(2.45), fill=GREEN_LIGHT,
             radius=0.1)
        tf = textbox(slide, x + Inches(0.2), Inches(2.78), Inches(2.38), Inches(2.1))
        para(tf, a, size=14, bold=True, color=GREEN_DARK, first=True, space_after=6)
        para(tf, b, size=11, color=GREY, space_after=8)
        para(tf, "用于：" + c, size=11, bold=True, color=GREEN, space_after=0)

    tf = textbox(slide, Inches(0.8), Inches(5.25), Inches(11.7), Inches(1.4))
    para(tf, "力求严谨的三点处理：", size=15, bold=True, color=INK, first=True,
         space_after=6)
    for t in ["回收类、节水类、光盘类因子采用 DEFRA 口径，因为中国官方尚未发布对应值——应用内逐条标注「英国口径」，不做模糊处理。",
              "「少开空调」按「节约的电量（度）」计量而非「小时」：每小时耗电量随匹数、能效、环温差异极大，按小时计量会引入不可控误差。",
              "《大型活动碳中和实施指南》不含因子数值（只给标准对照），《省级温室气体清单编制指南》无「每人公里」口径——两者都不能误用。"]:
        para(tf, "· " + t, size=11.5, color=GREY, space_after=3)


def slide_test(prs):
    slide = blank(prs)
    header(slide, "测试与验证", "HarmonyOS 7.0.0 模拟器实测，非推断")
    rows = [
        ("低碳行为核算", "录入 12 公里步行", "12 × 0.19567 ≈ 2.35 kg CO₂e，积分 235", "通过"),
        ("数据持久化", "重新安装应用后查看", "数据仍在", "通过"),
        ("数据可视化看板", "切粒度 + 看四类图", "折线与柱状横轴显示日期/类目名，环形图中心显示总量", "通过"),
        ("分类占比与图例", "核对环形图与图例", "百分比合计 100%（修复曾出现的 2841% 显示缺陷）", "通过"),
        ("减排日历热力图", "查看连续天数与色阶", "12 周 × 7 天网格，色阶按当日减排量分档，连续天数正确", "通过"),
        ("我的年度碳迹", "从看板进入报告页", "全年汇总、减排构成与看板数据一致", "通过"),
        ("碳积分体系", "1,462 分下检查兑换可用性", "勋章墙 4 枚全部达成，权益兑换可用性判断正确", "通过"),
        ("科普专栏", "按标签筛选与展开", "8 篇文章分类与展开正常", "通过"),
        ("数据管理", "备份 JSON / 导出 CSV", "文件写入沙箱并回显路径", "通过"),
        ("智能任务推荐", "当日记录出行后查看", "剩余三类成为待办（短板优先）", "通过"),
        ("分享图生成", "点击「生成分享图」", "沙箱内生成 PNG（约 97 KB）", "通过"),
        ("桌面服务卡片", "长按图标 → 卡片", "卡片入口出现，实时渲染今日数据", "通过"),
        ("端侧 AI 自检", "运行自检", "模型加载成功，输出 [1,500] 与 Top-5 候选", "通过"),
    ]
    y = Inches(1.34)
    rh = Inches(0.34)
    # 表头
    rect(slide, Inches(0.8), y, Inches(11.7), rh, fill=GREEN, radius=0.1)
    for x, w, t in [(0.95, 2.3, "测试项"), (3.3, 2.3, "操作"),
                    (5.7, 5.5, "预期 / 结果"), (11.3, 1.0, "结论")]:
        tf = textbox(slide, Inches(x), y + Inches(0.02), Inches(w), Inches(0.32),
                     anchor=MSO_ANCHOR.MIDDLE)
        para(tf, t, size=11.5, bold=True, color=WHITE, first=True, space_after=0)
    y += Inches(0.40)
    for i, (a, b, c, d) in enumerate(rows):
        bg = GREEN_LIGHT if i % 2 == 0 else RGBColor(0xF5, 0xF7, 0xFA)
        rect(slide, Inches(0.8), y, Inches(11.7), rh, fill=bg, radius=0.1)
        for x, w, t, bold, col in [
            (0.95, 2.3, a, True, INK), (3.3, 2.3, b, False, GREY),
            (5.7, 5.5, c, False, GREY), (11.3, 1.0, d, True, GREEN)]:
            tf = textbox(slide, Inches(x), y + Inches(0.02), Inches(w), Inches(0.32),
                         anchor=MSO_ANCHOR.MIDDLE)
            para(tf, t, size=10.5, bold=bold, color=col, first=True, space_after=0)
        y += Inches(0.375)

    tf = textbox(slide, Inches(0.8), Inches(6.6), Inches(11.7), Inches(0.6))
    para(tf, "另有 40 项纯逻辑单元断言（因子算术自洽性、任务推荐、生活建议、工具函数）全部通过；"
             "开发中据此发现并修复了 2 处缺陷。",
         size=12, color=GREEN_DARK, bold=True, first=True)


def slide_limit(prs):
    slide = blank(prs)
    header(slide, "已知限制", "如实说明能力边界")
    items = [
        ("创新拓展 1  多设备同步",
         "界面与业务逻辑已完成，同步面板可正常展示状态；尚未在两台真机间做端到端验证。",
         "测试所用模拟器不具备分布式软总线能力，且分布式数据同步权限需真机授权弹窗。"),
        ("创新拓展 2  端侧 AI 的类目标定",
         "视觉推理链路已实测可用；但「输出索引 → 业务类目」的标定表仍为空，文字识别通路未在设备上验证。",
         "标定必须用团队自己拍摄的真实照片；文字识别能力不支持模拟器运行。"),
        ("因子库部分条目",
         "回收类、节水类与光盘行动类采用英国 DEFRA 口径。",
         "中国官方尚未发布对应因子，已在应用内明确标注。"),
    ]
    y = Inches(1.7)
    for a, b, c in items:
        rect(slide, Inches(0.8), y, Inches(11.7), Inches(1.5),
             fill=RGBColor(0xFF, 0xF8, 0xE8), radius=0.1)
        tf = textbox(slide, Inches(1.1), y + Inches(0.16), Inches(11.1), Inches(1.25))
        para(tf, a, size=16, bold=True, color=AMBER, first=True, space_after=5)
        para(tf, b, size=13, color=INK, space_after=3)
        para(tf, "原因：" + c, size=12, color=GREY, space_after=0)
        y += Inches(1.65)
    tf = textbox(slide, Inches(0.8), Inches(6.6), Inches(11.7), Inches(0.5))
    para(tf, "原则：把每一个数字都算清楚，把每一个来源都标明白，把每一点能力边界都如实说明。",
         size=14, bold=True, color=GREEN_DARK, first=True)


def slide_summary(prs):
    slide = blank(prs)
    rect(slide, 0, 0, SW, SH, fill=GREEN, shape=MSO_SHAPE.RECTANGLE)
    tf = textbox(slide, Inches(1.0), Inches(1.1), Inches(11.3), Inches(0.8),
                 align=PP_ALIGN.CENTER)
    para(tf, "总结", size=34, bold=True, color=WHITE, first=True,
         align=PP_ALIGN.CENTER)

    cards = [
        ("5 / 5", "主要功能全部实现"),
        ("4 / 4", "创新拓展全部实现"),
        ("14 条", "因子全部标注权威出处"),
        ("全程离线", "数据不出设备"),
    ]
    for i, (a, b) in enumerate(cards):
        x = Inches(1.4 + i * 2.7)
        rect(slide, x, Inches(2.3), Inches(2.4), Inches(1.5),
             fill=RGBColor(0x17, 0x83, 0x42), radius=0.12)
        tf = textbox(slide, x, Inches(2.45), Inches(2.4), Inches(1.2),
                     align=PP_ALIGN.CENTER, anchor=MSO_ANCHOR.MIDDLE)
        para(tf, a, size=26, bold=True, color=WHITE, first=True,
             align=PP_ALIGN.CENTER, space_after=4)
        para(tf, b, size=12, color=RGBColor(0xD7, 0xE8, 0xDC),
             align=PP_ALIGN.CENTER, space_after=0)

    tf = textbox(slide, Inches(1.4), Inches(4.2), Inches(10.5), Inches(1.6),
                 align=PP_ALIGN.CENTER)
    para(tf, "「这个功能在其它平台上做不到，因为……」", size=18, bold=True,
         color=WHITE, first=True, align=PP_ALIGN.CENTER, space_after=12)
    for t in ["桌面服务卡片让碳数据常驻桌面，安卓与小程序没有等价机制",
              "分布式数据同步依赖鸿蒙分布式软总线，设备间直连而不经云端",
              "端侧 AI 推理与端侧文字识别均为系统级能力，图片不出设备",
              "全量本地存储、完全离线可用，演示不依赖任何网络条件"]:
        para(tf, t, size=13, color=RGBColor(0xD7, 0xE8, 0xDC),
             align=PP_ALIGN.CENTER, space_after=4)


def build():
    prs = Presentation()
    prs.slide_width = SW
    prs.slide_height = SH

    slide_cover(prs)
    slide_agenda(prs)
    slide_background(prs)
    slide_approach(prs)
    slide_features(prs)

    slide_shots(prs, "功能演示 · 低碳行为核算",
                "主要功能 1：录入 → 自动折算减排量 → 发放积分",
                [(f"{SHOT_DIR}/01-记一笔-初始.jpeg", "记一笔：英雄区 + 目标环 + 智能识图"),
                 (f"{SHOT_DIR}/02-记一笔-最近记录.jpeg", "填写数量与日期 · 最近记录")],
                note="实测：录入 12 公里步行 → 减排 2.35 kg CO₂e，发放 235 积分；"
                     "未保存前「本次减排」保持待计算状态。")

    slide_shots(prs, "功能演示 · 数据可视化看板",
                "主要功能 2：日 / 周 / 月 / 年四种统计粒度，数字全部来自真实录入",
                [(f"{SHOT_DIR}/03-看板-总览.jpeg",
                  "看板总览：英雄区 + 年度报告入口 + 统计粒度 + 减排日历")],
                note="累计减排 14.62 kg CO₂e、共 6 条记录；首屏新增「我的年度碳迹」入口横幅，"
                     "点开即进入全屏年度报告。")

    slide_heatmap(prs)

    slide_shots(prs, "数据可视化 · 趋势与分类对比",
                "折线看趋势、柱状看类目，横轴显示业务标签而非索引",
                [(f"{SHOT_DIR}/04-看板-减排日历.jpeg",
                  "减排趋势（本周）：实线为本期，灰色虚线为上期"),
                 (f"{SHOT_DIR}/05-看板-折线趋势.jpeg",
                  "分类减排对比与分类占比环形图")],
                note="折线新增「上期」幽灵线，柱顶直接标注数值；环形图中心显示累计总量 14.62 kg，"
                     "图例改用「色点 + 百分比 + 进度条」的原生样式。")

    slide_shots(prs, "智能服务 · 任务、建议与分享",
                "创新拓展 4：短板优先推荐 + 数据事实驱动的建议 + 一键分享",
                [(f"{SHOT_DIR}/06-看板-柱状对比.jpeg", "今日低碳任务与给你的低碳建议"),
                 (f"{SHOT_DIR}/07-看板-饼图与图例.jpeg",
                  "减排成果分享卡与「生成分享图 / 保存图片」入口")],
                note="任务规则为「短板优先」：先选今日未记录的类目，再按历史条数从少到多排序；"
                     "分享卡通过组件快照导出为图片。")

    slide_shots(prs, "新增页面 · 我的年度碳迹",
                "本次视觉改造新增的第 6 个页面，从看板一键进入（全屏年度报告）",
                [(f"{SHOT_DIR}/17-年度报告-封面.jpeg",
                  "报告封面：年度、低碳称号、活跃天数与核心数字"),
                 (f"{SHOT_DIR}/18-年度报告-细节.jpeg",
                  "碳积分、减排构成（四色条形）与写在最后")],
                note="全年汇总口径与看板完全一致：14.62 kg CO₂e、6 条记录、活跃 6 天、1,462 碳积分；"
                     "减排构成的四色条形与看板环形图一一对应。")

    slide_shots(prs, "功能演示 · 积分激励与碳普惠",
                "主要功能 3 + 创新拓展 3：碳积分、成就勋章与真实权益兑换",
                [(f"{SHOT_DIR}/09-积分-碳普惠.jpeg",
                  "积分英雄区（1,462 分 / 权益解锁 100%）与城市碳普惠平台"),
                 (f"{SHOT_DIR}/10-积分-权益与勋章.jpeg",
                  "可兑换权益（植树证书 / 碳中和达人证书）与积分流水")],
                note="勋章墙 4 枚成就全部达成（低碳新芽 / 绿色先锋 / 减碳达人 / 碳中和之星）；"
                     "积分流水逐条可追溯，与记录一一对应。")

    slide_shots(prs, "功能演示 · 双碳科普专栏",
                "主要功能 4：8 篇图文科普，按政策 / 概念 / 数据 / 技巧分类",
                [(f"{SHOT_DIR}/13-科普专栏.jpeg",
                  "科普专栏：英雄区 + 分类标签 + 带图标块的文章卡")],
                note="文章卡按分类使用不同颜色的图标块；内容以独立数据文件组织，"
                     "后续扩充无需改动界面代码。")

    slide_shots(prs, "功能演示 · 我的：同步、AI 自检与数据管理",
                "主要功能 5 + 创新拓展 1、2：档案、超级终端同步面板、端侧 AI 自检",
                [(f"{SHOT_DIR}/14-我的-档案.jpeg",
                  "我的：低碳称号英雄区 + 我的档案 + 超级终端同步"),
                 (f"{SHOT_DIR}/15-我的-同步面板.jpeg",
                  "同步状态、端侧 AI 自检与本地数据管理")],
                note="同步面板如实呈现本机标识、可信设备、同步结果与冲突计数；"
                     "备份 JSON / 导出 CSV 均写入沙箱并回显路径。")

    slide_visual(prs)

    slide_card(prs)
    slide_arch(prs)
    slide_datadecision(prs)

    slide_innovation(prs, 1, "超级终端多设备同步", [
        ("跨设备自动同步", "手机与平板登录同一账号、完成设备认证后，行为记录与积分流水自动同步。"),
        ("时间戳冲突处理", "写入以 { payload, ts, origin } 信封落库，冲突时以最新时间戳为准，保证最终一致性。"),
        ("同步状态可视化面板", "展示本机标识、可信设备、上次同步时间、同步结果、冲突记录数与远端写入数。"),
    ], extra="家庭碳积分合并：通过用户档案中的「家庭 ID」实现，同 ID 设备同步后自然形成合并视图。")

    slide_innovation(prs, 2, "端侧 AI 图片识别", [
        ("双通路设计", "视觉通路用 MindSpore Lite 端侧推理 MobileNetV2；文字通路用端侧 OCR 读文字后按关键词映射。"),
        ("推理链路已实测通过", "模型 11.4 MB 加载成功，输入 [1,224,224,3]、输出 [1,500]，"
                          "Top-5 分数区分度明显——端侧推理确实跑得起来。"),
        ("只预填不判定", "仅当置信度达阈值且映射到的因子确实存在时才自动填表，其余交给用户确认。"),
    ], extra="全程离线：模型随包内置，图片不会离开设备。作品还内置了「端侧 AI 自检」，"
             "用内置测试图打印张量形状与 Top-5 候选，既是验证手段，也是后续做类目标定的第一步。")

    slide_innovation(prs, 3, "模拟城市碳普惠接口", [
        ("完整业务链路", "账户绑定 → 积分上报 → 权益查询 → 权益兑换 → 订单查询，五个环节全部实现。"),
        ("保留真实接口语义", "异步调用、网络延迟、业务错误码、库存扣减、幂等与账户状态校验一应俱全。"),
        ("业务层只依赖契约", "未来对接真实平台时只需替换通信层，业务逻辑无需改动。"),
    ], extra="内置权益：地铁乘车券、共享单车券、环保购物袋、公园门票、电费红包——定价阶梯化，"
             "演示中既能展示兑换成功，也能展示积分不足分支。")

    slide_innovation(prs, 4, "智能服务与社交分享", [
        ("个性化低碳任务", "每天 3 条，规则为「短板优先」：先选今日未记录的类目，再按历史条数从少到多排序。"),
        ("数据事实驱动的建议", "每条建议都对应一个具体事实，例如「本周比上周多减排 X kg」「还没记录过旧物回收」。"),
        ("减排成果分享图", "一键生成低碳成绩单（累计减排、等效植树、记录天数），通过组件快照导出为图片。"),
    ], extra="推荐逻辑采用可解释规则而非黑盒模型——答辩时能指着代码说清「智能」体现在哪里。")

    slide_factor(prs)
    slide_test(prs)
    slide_limit(prs)
    slide_summary(prs)

    # 清理文档属性：python-pptx 默认会写入 last_modified_by="Steve Canny"、
    # comments="generated using python-pptx"，必须清掉（同上）。
    cp = prs.core_properties
    cp.author = ""
    cp.last_modified_by = ""
    cp.title = "碳迹 —— 碳足迹·全民绿色生活碳积分与减排指南"
    cp.subject = "赛题二"
    cp.comments = ""
    cp.category = ""
    cp.keywords = ""

    prs.save(OUT)
    slides = list(prs.slides)
    pics = sum(1 for s in slides for sh in s.shapes if sh.shape_type == 13)
    missing = [sh.name for s in slides for sh in s.shapes
               if sh.shape_type == 13 and sh.image is None]
    print(f"已生成：{os.path.abspath(OUT)}")
    print(f"共 {len(slides)} 页，插图 {pics} 张")
    if missing:
        print(f"  ⚠️ 有 {len(missing)} 张图片异常：{missing}")


if __name__ == "__main__":
    build()
