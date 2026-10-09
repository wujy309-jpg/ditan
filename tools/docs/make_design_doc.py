#!/usr/bin/env python3
"""生成《碳迹 —— 设计说明书》Word 文档。

规格要求（来自大赛通知）：
  · .docx 格式
  · 正文统一宋体、小四号（12pt）、1.5 倍行距
  · 内容包含：设计思路、功能实现逻辑、技术架构、软硬件选型、测试结果
  · ⚠️ 不得出现参赛团队、指导老师、院校信息

用法：python3 tools/docs/make_design_doc.py

截图说明（2026-09-30 前端视觉美化后重拍）：
  · 取图目录仍是 素材/截图/，文件名与旧版不同，旧图已备份到 素材/截图/旧版-改造前/。
  · 「界面设计」相关章节（3.2 / 3.11 / 3.12）使用新版截图；
    3.11 新增「改造前后对比」小节，用 素材/改造前后对比-前端美化.png。
  · 热力图用构建期裁剪的派生图（见 fig()），不修改素材文件本身。
"""
import math
import os

from docx import Document
from docx.enum.table import WD_ALIGN_VERTICAL, WD_TABLE_ALIGNMENT
from docx.enum.text import WD_ALIGN_PARAGRAPH
from docx.oxml.ns import qn
from docx.shared import Inches, Pt, RGBColor
from PIL import Image

BODY_FONT = "宋体"
BODY_SIZE = Pt(12)          # 小四
LINE_SPACING = 1.5
OUT = "交付物/设计方案_碳迹.docx"   # 与 make_video.py 一致：从仓库根目录运行
SHOT_DIR = "素材/截图"
ASSET_DIR = "素材"
FIG_DIR = "/tmp/carbon-doc-figs"    # 构建期裁剪出的派生图
CROP_BASE = (1320, 2232)            # 手机截图基准分辨率


def fig(path, crop=None):
    """裁剪截图（crop 单位是基准分辨率 1320×2232 下的像素），返回可插入的路径。"""
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


def set_run_font(run, name=BODY_FONT, size=BODY_SIZE, bold=False, color=None):
    """设置中英文字体。中文必须额外指定 w:eastAsia，否则不会生效。"""
    run.font.name = name
    run.font.size = size
    run.font.bold = bold
    if color is not None:
        run.font.color.rgb = color
    rpr = run._element.get_or_add_rPr()
    rfonts = rpr.find(qn("w:rFonts"))
    if rfonts is None:
        rfonts = rpr.makeelement(qn("w:rFonts"), {})
        rpr.append(rfonts)
    rfonts.set(qn("w:ascii"), name)
    rfonts.set(qn("w:hAnsi"), name)
    rfonts.set(qn("w:eastAsia"), name)


def add_runs(p, text, size=BODY_SIZE, bold=False):
    """把一行文本切成若干 run，支持两种行内标记。

    为什么需要：`body()` 原先把整段当作**单个 run** 写进去，
    于是 `**加粗**` 和反引号会字面出现在文档里。这里做最小解析：
      · `**文字**`  → 加粗
      · `` `文字` `` → 等宽字体（用于文件名、代码标识符）
    其余按普通文本处理。
    """
    import re
    tokens = re.split(r"(\*\*.+?\*\*|`[^`]+`)", text)
    for tk in tokens:
        if not tk:
            continue
        if len(tk) > 4 and tk.startswith("**") and tk.endswith("**"):
            r = p.add_run(tk[2:-2])
            set_run_font(r, size=size, bold=True)
        elif len(tk) > 2 and tk.startswith("`") and tk.endswith("`"):
            r = p.add_run(tk[1:-1])
            set_run_font(r, size=Pt(size.pt - 0.5), bold=False)
            r.font.name = "Consolas"
            rPr = r._element.get_or_add_rPr()
            for tag in ("w:rFonts",):
                el = rPr.find(qn(tag))
                if el is None:
                    el = rPr.makeelement(qn(tag), {})
                    rPr.append(el)
                el.set(qn("w:eastAsia"), "Consolas")
        else:
            r = p.add_run(tk)
            set_run_font(r, size=size, bold=bold)
    return p


def body(doc, text, indent=True, bold=False, size=BODY_SIZE, align=None, space_after=6):
    p = doc.add_paragraph()
    pf = p.paragraph_format
    pf.line_spacing = LINE_SPACING
    pf.space_after = Pt(space_after)
    if indent:
        pf.first_line_indent = size * 2
    if align is not None:
        p.alignment = align
    add_runs(p, text, size=size, bold=bold)
    return p


def bullet(doc, text, size=BODY_SIZE):
    p = doc.add_paragraph(style="List Bullet")
    pf = p.paragraph_format
    pf.line_spacing = LINE_SPACING
    pf.space_after = Pt(3)
    add_runs(p, text, size=size)
    return p


def heading(doc, text, level=1):
    sizes = {1: Pt(16), 2: Pt(14), 3: Pt(12.5)}
    p = doc.add_paragraph()
    pf = p.paragraph_format
    pf.line_spacing = LINE_SPACING
    pf.space_before = Pt(14 if level == 1 else 10)
    pf.space_after = Pt(8)
    run = p.add_run(text)
    set_run_font(run, name="黑体" if level == 1 else BODY_FONT,
                 size=sizes.get(level, BODY_SIZE), bold=True,
                 color=GREEN if level == 1 else None)
    return p


# 正文可用宽度：页宽 8.5in − 左右页边距各 1.25in = 6in = 432pt
USABLE_WIDTH_PT = 432.0


def _set_repeat_header(row):
    """让表头在跨页时重复出现。"""
    tr_pr = row._tr.get_or_add_trPr()
    el = tr_pr.makeelement(qn("w:tblHeader"), {})
    tr_pr.append(el)


def _set_cant_split(row):
    """禁止单行跨页断开。"""
    tr_pr = row._tr.get_or_add_trPr()
    el = tr_pr.makeelement(qn("w:cantSplit"), {})
    tr_pr.append(el)


def table(doc, headers, rows, widths=None):
    t = doc.add_table(rows=1, cols=len(headers))
    t.style = "Table Grid"
    t.alignment = WD_TABLE_ALIGNMENT.CENTER
    t.autofit = False

    hdr = t.rows[0].cells
    for i, h in enumerate(headers):
        hdr[i].text = ""
        p = hdr[i].paragraphs[0]
        p.alignment = WD_ALIGN_PARAGRAPH.CENTER
        p.paragraph_format.line_spacing = 1.25
        p.paragraph_format.space_after = Pt(2)
        run = p.add_run(h)
        set_run_font(run, size=Pt(10), bold=True)

    for row in rows:
        cells = t.add_row().cells
        for i, v in enumerate(row):
            cells[i].text = ""
            p = cells[i].paragraphs[0]
            p.paragraph_format.line_spacing = 1.25
            p.paragraph_format.space_after = Pt(2)
            add_runs(p, str(v), size=Pt(10))

    # 列宽：按传入比例归一化到可用宽度，避免超出页边距
    if widths:
        total = sum(w.pt for w in widths)
        scaled = [Pt(w.pt / total * USABLE_WIDTH_PT) for w in widths]
        for r in t.rows:
            for i, w in enumerate(scaled):
                r.cells[i].width = w

    _set_repeat_header(t.rows[0])
    for r in t.rows:
        _set_cant_split(r)

    doc.add_paragraph().paragraph_format.space_after = Pt(2)
    return t


def caption(doc, text, keep_next=False):
    p = doc.add_paragraph()
    if keep_next:
        p.paragraph_format.keep_with_next = True
    p.alignment = WD_ALIGN_PARAGRAPH.CENTER
    p.paragraph_format.line_spacing = 1.3
    p.paragraph_format.space_after = Pt(10)
    run = p.add_run(text)
    set_run_font(run, size=Pt(10.5), color=RGBColor(0x60, 0x60, 0x60))


def image_grid(doc, items, cols=2, img_w_in=2.25, cap_size=Pt(9.5)):
    """把若干张截图排成无边框网格，每张图下方跟一行图注。

    items = [(图片路径, 图注), ...]；路径可以是 fig() 裁出来的派生图。
    图与图注放在**同一个单元格**里，并把整行标记为「禁止跨页断行」——
    否则当某一行恰好落在页底时，渲染器会把图注的第二行裁掉（实测踩到过）。
    """
    rows = math.ceil(len(items) / cols)
    t = doc.add_table(rows=rows, cols=cols)
    t.alignment = WD_TABLE_ALIGNMENT.CENTER
    t.autofit = False
    for idx, (path, cap) in enumerate(items):
        r, c = divmod(idx, cols)
        cell = t.cell(r, c)
        cell.vertical_alignment = WD_ALIGN_VERTICAL.TOP
        p = cell.paragraphs[0]
        p.alignment = WD_ALIGN_PARAGRAPH.CENTER
        p.paragraph_format.line_spacing = 1.0
        p.paragraph_format.space_after = Pt(3)
        if os.path.exists(path):
            p.add_run().add_picture(path, width=Inches(img_w_in))
        else:
            p.add_run("（缺少截图：" + path + "）")
        cp = cell.add_paragraph()
        cp.alignment = WD_ALIGN_PARAGRAPH.CENTER
        cp.paragraph_format.line_spacing = 1.05
        cp.paragraph_format.space_after = Pt(10)
        run = cp.add_run(cap)
        set_run_font(run, size=cap_size, color=RGBColor(0x60, 0x60, 0x60))
    col_w = Pt(USABLE_WIDTH_PT / cols)
    for row in t.rows:
        for i in range(cols):
            row.cells[i].width = col_w
        _set_cant_split(row)
    return t


def figure(doc, path, cap, img_w_in=5.4):
    """整幅插图 + 图注（用于横向的对比图、宽幅截图）。"""
    p = doc.add_paragraph()
    p.alignment = WD_ALIGN_PARAGRAPH.CENTER
    p.paragraph_format.line_spacing = 1.0
    p.paragraph_format.space_before = Pt(6)
    p.paragraph_format.space_after = Pt(4)
    if os.path.exists(path):
        im = Image.open(path)
        w = min(img_w_in, USABLE_WIDTH_PT / 72.0)
        p.add_run().add_picture(path, width=Inches(w),
                                height=Inches(w * im.height / im.width))
    else:
        p.add_run("（缺少素材：" + path + "）")
    caption(doc, cap)
    return p


# ===========================================================================
def build():
    doc = Document()

    # 全局默认字体
    style = doc.styles["Normal"]
    style.font.name = BODY_FONT
    style.font.size = BODY_SIZE
    style.element.rPr.rFonts.set(qn("w:eastAsia"), BODY_FONT)

    # ---------------- 封面 ----------------
    for _ in range(4):
        doc.add_paragraph()
    p = doc.add_paragraph()
    p.alignment = WD_ALIGN_PARAGRAPH.CENTER
    run = p.add_run("碳  迹")
    set_run_font(run, name="黑体", size=Pt(36), bold=True, color=GREEN)

    p = doc.add_paragraph()
    p.alignment = WD_ALIGN_PARAGRAPH.CENTER
    run = p.add_run("碳足迹 · 全民绿色生活碳积分与减排指南")
    set_run_font(run, name="黑体", size=Pt(16))

    doc.add_paragraph()
    p = doc.add_paragraph()
    p.alignment = WD_ALIGN_PARAGRAPH.CENTER
    run = p.add_run("设 计 说 明 书")
    set_run_font(run, name="黑体", size=Pt(20), bold=True)

    for _ in range(6):
        doc.add_paragraph()
    p = doc.add_paragraph()
    p.alignment = WD_ALIGN_PARAGRAPH.CENTER
    run = p.add_run("参赛赛题：赛题二  碳足迹·全民绿色生活碳积分与减排指南")
    set_run_font(run, size=Pt(12))

    doc.add_page_break()

    # ---------------- 一、作品概述 ----------------
    heading(doc, "一、作品概述", 1)
    heading(doc, "1.1 设计思路", 2)
    body(doc, "本作品面向国家「双碳」战略中的公众参与环节，试图回答一个具体问题："
              "普通人每天的低碳行为，究竟减了多少碳？这些减排量又能换来什么？")
    body(doc, "围绕这个问题，作品把「量化—激励—回馈」做成了一条完整闭环：")
    bullet(doc, "量化：把出行、节水节电、旧物回收、光盘行动四类日常行为，"
                "乘以内置的碳排放因子，折算成可比较的减排量（kg CO₂e）。")
    bullet(doc, "激励：按减排量发放碳积分，配合每日低碳任务、虚拟徽章与电子证书，形成正反馈。")
    bullet(doc, "回馈：积分可上报到「城市碳普惠平台」，兑换地铁乘车券、共享单车券等真实权益。")
    body(doc, "设计过程中有三处刻意的取舍，也是本作品与同类作品的主要区别：")
    body(doc, "第一，数据全部留在本机。赛题将本作品定位为「单机版」，我们没有把它当成限制，"
              "而是当成隐私优势：碳账本属于个人数据，全量本地存储、完全离线可用，"
              "既契合信创语境下的数据主权诉求，也让演示环节不依赖现场网络。")
    body(doc, "第二，AI 用来「预填」而不是「判定」。端侧图像识别只在高置信度时预填表单，"
              "低置信度交给用户确认。原因是通用分类模型天然分不清「新能源车与燃油车」"
              "「地铁与公交」这类细分类别，强行自动判定只会污染用户的碳账本。"
              "这一取舍既保证了体验，也避免了对「AI 是否可靠」的过度承诺。")
    body(doc, "第三，每个因子都必须能追溯到出处。应用内每条碳排放因子都标注了数据来源与"
              "基准情景，用户可以随时查看。这既是功能要求，也是本作品在严谨性上的立足点。")

    heading(doc, "1.2 与赛题要求的对应关系", 2)
    table(doc,
          ["赛题要求", "实现情况", "对应模块"],
          [
              ["主要功能 1  低碳行为核算", "已实现", "记一笔、数据仓储、碳排放因子库"],
              ["主要功能 2  数据可视化看板", "已实现", "看板（折线图／柱状图／饼图，日周月年切换）"],
              ["主要功能 3  碳积分激励体系", "已实现", "积分（任务、兑换、流水）"],
              ["主要功能 4  双碳科普专栏", "已实现", "科普（8 篇图文，支持分类筛选）"],
              ["主要功能 5  本地数据管理", "已实现", "我的（备份为 JSON、导出 CSV 报表）"],
              ["创新拓展 1  超级终端多设备同步", "已实现", "超级终端同步面板（家庭碳积分合并）"],
              ["创新拓展 2  端侧 AI 图片识别", "已实现", "端侧 AI 识图（MindSpore Lite ＋ 端侧 OCR）"],
              ["创新拓展 3  模拟城市碳普惠接口", "已实现", "积分页「城市碳普惠平台」专区"],
              ["创新拓展 4  智能服务与社交分享", "已实现", "今日任务、低碳建议、减排成果分享图"],
              ["（延伸页面）我的年度碳迹", "已实现", "看板 → 全屏年度报告页，全年汇总与减排构成"],
          ],
          widths=[Pt(180), Pt(70), Pt(200)])
    caption(doc, "表 1  赛题要求与实现情况对照")

    heading(doc, "1.3 开发与运行环境", 2)
    table(doc,
          ["项目", "选型"],
          [
              ["开发工具", "DevEco Studio"],
              ["操作系统", "OpenHarmony／HarmonyOS"],
              ["API 版本", "compatibleSdkVersion 5.0.0(12)，满足赛题「API 12 及以上」要求"],
              ["开发语言", "ArkTS（ArkUI 声明式开发）"],
              ["硬件要求", "纯北向应用类赛题，使用鸿蒙手机、平板或模拟器即可，无需额外采购硬件"],
          ],
          widths=[Pt(110), Pt(340)])
    caption(doc, "表 2  开发与运行环境")

    doc.add_page_break()

    # ---------------- 二、技术架构 ----------------
    heading(doc, "二、技术架构", 1)
    heading(doc, "2.1 总体架构", 2)
    body(doc, "工程采用四层结构，自上而下依次为表现层、业务层、数据层与能力层：")
    table(doc,
          ["层次", "职责", "主要模块"],
          [
              ["表现层", "界面与交互，五个功能页签",
               "EntryPage、DashboardPage、Charts、PointsPage、"
               "KnowledgePage、SmartService、ProfilePage"],
              ["业务层", "领域逻辑：减排计算、积分规则、任务推荐、碳普惠业务流程",
               "Models、TaskEngine、CarbonInclusiveApi"],
              ["数据层", "统一数据存取与跨设备同步",
               "CarbonRepository（仓储层）、DistributedStore（分布式 KV 封装）"],
              ["能力层", "鸿蒙系统能力",
               "distributedKVStore、distributedDeviceManager、MindSpore Lite、"
               "Core Vision Kit、ArkUI 组件快照、Image Kit、MediaLibraryKit"],
          ],
          widths=[Pt(60), Pt(170), Pt(220)])
    caption(doc, "表 3  分层架构")

    heading(doc, "2.2 数据层设计（关键决策）", 2)
    body(doc, "数据层没有采用关系型数据库（relationalStore），而是直接建立在"
              "分布式键值库（distributedKVStore）之上。这是一处影响全局的取舍。")
    body(doc, "原因在于创新拓展 1「超级终端多设备同步」需要复用分布式存储能力，"
              "而分布式数据服务与关系型数据库是两套互不通用的存储引擎。"
              "如果先用关系型数据库建表、后期再接入分布式同步，整个数据层需要重写。"
              "因此在项目起步阶段就把存储建立在 KV 之上，"
              "使后续的同步功能成为「接入一个已有组件」而不是「重构数据层」。")
    body(doc, "键设计如下（同一分布式库内以 carbon: 作为业务前缀，便于与其它模块隔离）：")
    table(doc,
          ["键", "值结构", "说明"],
          [
              ["behavior:<id>", "BehaviorRecord 的 JSON",
               "一条低碳行为记录；id 由时间戳、进程内序号与随机数共同保证唯一"],
              ["points:<id>", "PointsEntry 的 JSON",
               "一条积分流水，只增不改，天然免冲突"],
              ["profile", "Profile 的 JSON", "用户档案（单例）"],
              ["platform:account", "PlatformAccount 的 JSON", "碳普惠平台账户（创新拓展 3）"],
              ["platform:order:<id>", "ExchangeOrder 的 JSON", "权益兑换订单"],
          ],
          widths=[Pt(120), Pt(150), Pt(180)])
    caption(doc, "表 4  分布式 KV 键设计")
    body(doc, "查询策略：KV 没有 where 子句，本作品采用「取全量后内存排序筛选」。"
              "个人级碳数据的量级为每天数条至数十条，远未达到需要索引的程度，"
              "因此没有为查询性能引入额外复杂度。")

    heading(doc, "2.3 冲突处理与最终一致性", 2)
    body(doc, "所有写入都以「信封」形式落库，结构为 { payload, ts, origin }，"
              "其中 payload 是业务负载、ts 是写入时间戳、origin 是写入方设备标识。"
              "当多设备同时离线编辑产生冲突时，以时间戳更新的一方为准，"
              "并在本地维护影子副本用于冲突判定，冲突次数会在同步面板中如实展示。"
              "这对应赛题所要求的「以最新时间戳的版本为准，确保数据最终一致性」。")

    doc.add_page_break()

    # ---------------- 三、功能实现逻辑 ----------------
    heading(doc, "三、功能实现逻辑", 1)

    heading(doc, "3.1 主要功能 1：低碳行为核算", 2)
    body(doc, "录入流程为：选择类目 → 选择具体行为 → 填写数量 → 选择日期 → 保存。"
              "保存时按「减排量 ＝ 活动量 × 因子」计算，其中因子已经是对基准情景的差值"
              "（详见第五章）。计算结果实时回显，并同步发放碳积分。")
    body(doc, "内置 14 条因子，覆盖出行、节水节电、旧物回收、光盘行动四个类目。"
              "每条因子在界面上展示三个信息：因子数值与单位、基准情景、数据出处，"
              "用户可以随时核对。")
    image_grid(doc, [
        (f"{SHOT_DIR}/01-记一笔-初始.jpeg",
         "图 1  记一笔首页：渐变英雄区（累计减排 14.62 kg CO₂e）＋ 今日目标环 ＋ "
         "端侧 AI 识图入口 ＋ 四个类目卡"),
        (f"{SHOT_DIR}/02-记一笔-最近记录.jpeg",
         "图 2  录入表单与最近记录：填写数量与日期后保存，记录按类目色块与减排量列出"),
    ])

    heading(doc, "3.2 主要功能 2：数据可视化看板", 2)
    body(doc, "看板支持日、周、月、年四种统计粒度切换，并同时提供四种可视化表达：")
    bullet(doc, "折线图：展示减排量随时间的变化趋势，采用平滑曲线与渐变面积填充；"
                "**本期数据用实线、上一周期用灰色虚线**——这条「上期幽灵线」让"
                "「这周比上周好还是差」不需要再靠记忆判断。")
    bullet(doc, "柱状图：展示四个类目之间的减排量对比，柱体带竖向渐变，**柱顶直接标注数值**。")
    bullet(doc, "环形图：展示各类目的占比构成，**中心显示累计总量**；"
                "图例改用「色点 ＋ 百分比 ＋ 进度条」的原生样式，不再依赖悬浮提示。")
    bullet(doc, "减排日历热力图（本次新增）：最近 12 周 × 7 天的格子，"
                "按当日减排量分四档着色，并给出连续记录天数。")
    body(doc, "四条数据表达共用同一份数据源与同一套类目配色，因此读图时不需要在不同图之间"
              "重新建立对应关系。图表基于 OpenHarmony-TPC 官方图表组件库实现，"
              "该库为纯 ArkTS 源码形式，可完整离线运行，不依赖任何网络资源。"
              "横轴标签经过格式化处理，折线图显示日期、柱状图显示类目名称，"
              "而不是原始索引值。")
    body(doc, "**本次修复的一处显示缺陷**：改造前环形图的百分比曾出现 2841% 这类明显异常值。"
              "原因是百分比被重复换算了一次（先按总量取百分比，又在渲染时乘了 100）。"
              "修复后中心显示总量、图例显示正确的百分比与进度条，四类合计 100%。"
              "这个问题也写进了功能测试用例（见表 8）。")
    image_grid(doc, [
        (f"{SHOT_DIR}/03-看板-总览.jpeg",
         "图 3  看板总览：深墨绿英雄区 ＋「我的年度碳迹」入口 ＋ 统计粒度 ＋ 减排日历"),
        (f"{SHOT_DIR}/04-看板-减排日历.jpeg",
         "图 4  减排趋势（本周）：实线为本期，灰色虚线为「上期」对比"),
        (f"{SHOT_DIR}/05-看板-折线趋势.jpeg",
         "图 5  分类减排对比与分类占比：柱顶数值、环形图中心总量与原生图例"),
    ], cols=3, img_w_in=1.85)
    figure(doc, fig(f"{SHOT_DIR}/03-看板-总览.jpeg", (40, 1395, 1280, 1972)),
           "图 6  减排日历热力图：最近 12 周 × 7 天，连续记录天数与四档色阶", img_w_in=4.6)
    caption(doc, "（色阶图例：少 → 多，每格 = 一天；没有记录的日子为浅灰。）")


    heading(doc, "3.3 主要功能 3：碳积分激励体系", 2)
    body(doc, "积分规则为：每减排 1 kg CO₂e 获得 100 积分。积分可用于两个方向：")
    bullet(doc, "本地兑换：虚拟徽章与电子证书（低碳新芽徽章、绿色先锋徽章、植树证书、碳中和达人证书）。")
    bullet(doc, "平台兑换：上报到城市碳普惠平台后，兑换地铁乘车券、共享单车券等真实权益。")
    body(doc, "兑换按钮会根据当前积分余额自动置灰或点亮，避免无效操作。"
              "此外另设「成就勋章墙」，把连续记录、累计减排等里程碑固化成可见的徽章。")
    image_grid(doc, [
        (f"{SHOT_DIR}/09-积分-碳普惠.jpeg",
         "图 7  积分页：英雄区（1,462 分 / 权益解锁 100%）、城市碳普惠平台与低碳成就勋章墙"),
        (f"{SHOT_DIR}/10-积分-权益与勋章.jpeg",
         "图 8  可兑换权益（植树证书 / 碳中和达人证书）与积分流水明细"),
    ])

    heading(doc, "3.4 主要功能 4：双碳科普专栏", 2)
    body(doc, "内置 8 篇图文科普，按「政策／概念／技巧／数据」四类标签组织，支持分类筛选与"
              "展开阅读。内容涵盖碳达峰碳中和目标、碳足迹计算方法、"
              "电网排放因子的地域差异、出行与居家的低碳技巧、回收的减排原理、"
              "食物浪费与碳排放、以及碳普惠机制。"
              "科普内容以独立数据文件组织，便于后续扩充而无需改动界面代码。")
    image_grid(doc, [
        (f"{SHOT_DIR}/13-科普专栏.jpeg",
         "图 9  科普专栏：清爽绿英雄区、分类标签与带图标块的文章卡"),
    ], cols=1, img_w_in=2.7)

    heading(doc, "3.5 主要功能 5：本地数据管理", 2)
    body(doc, "提供两种导出方式：")
    bullet(doc, "备份数据：把用户档案、全部行为记录与积分流水导出为结构化 JSON 文件。")
    bullet(doc, "导出报表：把行为记录导出为 CSV 表格，便于在电脑上做进一步统计。")
    body(doc, "两者均写入应用沙箱目录，并在界面上回显完整路径。此外提供「清空全部数据」入口，"
              "执行前需用户主动确认。")
    image_grid(doc, [
        (f"{SHOT_DIR}/14-我的-档案.jpeg",
         "图 10  「我的」页：低碳称号英雄区、我的档案与超级终端同步面板"),
        (f"{SHOT_DIR}/15-我的-同步面板.jpeg",
         "图 11  同步状态、端侧 AI 自检入口与本地数据管理（备份 JSON / 导出 CSV）"),
    ])

    heading(doc, "3.6 创新拓展 1：超级终端多设备同步", 2)
    body(doc, "基于鸿蒙分布式数据服务实现。用户在手机与平板等设备上登录同一账号、"
              "完成设备认证并处于同一局域网后，行为记录与积分流水可在设备间自动同步。"
              "作品提供了一个同步状态可视化面板，展示本机标识、可信设备列表、"
              "上次同步时间、同步结果、冲突记录数与远端写入数，"
              "让数据流转过程对用户完全可见。")
    body(doc, "家庭碳积分合并统计通过在用户档案中引入「家庭 ID」实现："
              "同一家庭 ID 的设备在同步后即自然形成合并视图。")

    heading(doc, "3.7 创新拓展 2：端侧 AI 图片识别", 2)
    body(doc, "用户在录入页拍照或从相册选图，应用在本机完成识别并预填表单，"
              "图片不会上传到任何服务器。实现上采用双通路设计：")
    bullet(doc, "视觉通路：使用 MindSpore Lite 在端侧加载 MobileNetV2 模型进行图像分类，"
                "模型文件随应用打包内置，推理完全离线。")
    bullet(doc, "文字通路：使用 Core Vision Kit 的端侧文字识别能力读取图片中的文字，"
                "再通过关键词规则映射到具体行为（例如识别到「地铁」「号线」即判定为地铁出行）。")
    body(doc, "两路结果按置信度融合：一致时提升置信度，冲突时取较高者并降低置信度。"
              "仅当置信度达到阈值且映射到的因子确实存在时，才自动预填表单。")
    body(doc, "需要如实说明的是：通用分类模型对「回收类」「餐饮类」识别效果较好，"
              "但对「节约用电」「步行」这类行为或账单语义的类别天然无能为力。"
              "因此作品的设计目标是「减少输入成本」，而不是「替代用户判断」，"
              "这一点在界面文案与设计文档中都做了明确说明。")

    heading(doc, "3.8 创新拓展 3：模拟城市碳普惠接口", 2)
    body(doc, "作品实现了一套完整的碳普惠平台对接层，包含账户绑定、积分上报、"
              "权益查询、权益兑换与订单查询五个环节。")
    body(doc, "由于城市碳普惠平台没有对个人开发者开放的公开接口，且演示环境需要离线可用，"
              "该平台为本地模拟实现。但模拟保留了真实接口的全部语义："
              "异步调用、网络延迟、业务错误码、库存扣减、幂等与账户状态校验。"
              "业务层只依赖接口契约、不依赖具体实现，"
              "因此未来对接真实平台时只需替换通信层，业务逻辑无需改动。")
    body(doc, "内置权益包括地铁乘车券、共享单车免费券、环保购物袋、城市公园门票与电费红包，"
              "定价阶梯化设计，使演示中既能展示兑换成功，也能展示积分不足的分支。")

    heading(doc, "3.9 创新拓展 4：智能服务与社交分享", 2)
    body(doc, "包含三部分：")
    bullet(doc, "个性化低碳任务：每天生成 3 条任务。推荐规则为「短板优先」——"
                "先选出今天尚未记录的类目，再按历史记录条数从少到多排序，"
                "优先推送用户最薄弱的环节；已完成的事项会被标记并排到末尾。")
    bullet(doc, "个性化生活建议：每条建议都对应一个具体的数据事实，"
                "例如「本周比上周多减排 X kg」「你还没有记录过旧物回收类的行为」。"
                "推荐逻辑采用可解释的规则而非黑盒模型，便于说明与追溯。")
    bullet(doc, "减排成果分享：生成一张低碳成绩单卡片，包含累计减排量、"
                "等效植树量、记录条数与坚持天数，可导出为图片并保存到相册。"
                "分享图通过 ArkUI 组件快照能力生成，不需要引入额外绘图库。")
    image_grid(doc, [
        (f"{SHOT_DIR}/06-看板-柱状对比.jpeg",
         "图 12  今日低碳任务（短板优先）与数据事实驱动的低碳建议"),
        (f"{SHOT_DIR}/07-看板-饼图与图例.jpeg",
         "图 13  减排成果分享卡与「生成分享图 / 保存图片」入口"),
    ])

    heading(doc, "3.10 鸿蒙特色能力：桌面服务卡片", 2)
    body(doc, "除赛题列出的四项创新拓展外，作品还实现了一项鸿蒙特有的系统级能力——"
              "桌面服务卡片（万能卡片）。用户把卡片添加到桌面后，"
              "**不必打开应用**即可看到今日减排量、碳积分、近 7 日趋势与个性化提示；"
              "点击卡片直接进入应用。")
    body(doc, "卡片支持 2×2、2×4、4×4 三种尺寸，并随应用内数据变化自动刷新："
              "用户在应用里新增一条记录后，主应用会主动通知卡片更新；"
              "系统也会按配置定期拉取。卡片数据直接读取与应用相同的分布式键值库，"
              "因此显示内容与打开应用所见完全一致。")
    body(doc, "这项能力的价值在于它无法被其它平台复刻：安卓与小程序都没有等价的"
              "桌面常驻卡片机制，而鸿蒙的卡片是系统级一等公民，"
              "可以承载实时数据、响应点击、参与负一屏与桌面布局。"
              "在演示环节，它也是最直观的「鸿蒙感」体现——"
              "评委看到桌面上直接显示着碳数据，不需要任何解释就能理解差异。")
    image_grid(doc, [
        (f"{SHOT_DIR}/14-服务卡片-特写.png",
         "图 14  桌面服务卡片特写：今日减排量、碳积分与近 7 日迷你趋势"),
    ], cols=1, img_w_in=3.2)

    heading(doc, "3.11 界面设计与视觉体系", 2)
    body(doc, "界面不是「好看就行」，而是有依据的工程结果。作品的设计参数全部对齐"
              "《HarmonyOS 设计规范》，并把规范落成一份可复用的设计令牌文件"
              "（`common/Theme.ets`），页面只引用令牌、不写死数值。")
    body(doc, "**本次视觉改造的背景**：工程里本来就有一份质量很高的设计令牌，"
              "但改造前的落地率只有约 15%——渐变只用在 2 个页面，卡片投影全工程只调用了 4 次，"
              "动效令牌定义了却一次都没用（全工程零动画），另有 104 处颜色是手工裸写的。"
              "于是界面呈现的是两套设计语言的拼贴：少数几块地方有质感，大部分还是脚手架。"
              "诊断结论是——问题不在审美，而在「施工完成度」。")
    body(doc, "改造围绕五件事展开，它们共同构成了现在这套界面语言：")
    bullet(doc, "**统一英雄区**：五个页面都用「渐变英雄区」开场，按页面气质分三档绿色，"
                "但每页的主角不同——记一笔是减排总量与目标环，看板是趋势入口，"
                "积分是余额与权益解锁度，科普是内容数量，我的是低碳称号。")
    bullet(doc, "**卡片默认投影**：把「卡片长什么样」从 5 个页面收敛到 1 个公共组件，"
                "投影成为默认行为而不是逐页手写；卡片同时分三级"
                "（主卡渐变 32vp 圆角、次卡白底轻阴影、微卡浅灰 8vp）。")
    bullet(doc, "**列表图标化**：科普、积分、同步等列表一律加图标块，"
                "同一屏里的信息密度与可扫读性都明显提升。")
    bullet(doc, "**弹簧动效**：页签切换、类目选中、保存按钮、展开折叠与环形进度"
                "共 9 处 `animateTo`，全工程从 0 到 9，交互有了「手感」。")
    bullet(doc, "**数据可视化**：折线加「上期」对比线、柱顶标注数值、环形图中心显示总量、"
                "图例改原生样式，并新增减排日历热力图。")
    body(doc, "规范依据具体落到四组官方 Token 上：**圆角**按官方五档收敛"
              "（标签 4 / 图标 8 / 普通卡片 16 / 按钮 20 / 主卡 32，vp），"
              "对应官方「层级越高圆角越大」的原则；**色彩**采用官方文本四级"
              "（85% / 60% / 40% / 20% 黑），让标题、正文、辅助说明、占位符各自归位；"
              "**间距**统一到 8vp 体系（卡片之间 12、卡片内边距 16、屏幕左右 16）；"
              "**字号**则把大数字改用 Normal 字重而非 Bold，避免粗体大数字显得笨重。")
    body(doc, "还有两处细节值得一提。一是**视觉重量**：五个页签图标原先形状差异过大，"
              "实测视觉重量极差达 27.03%，改造中重绘了页签图标（「记一笔」从加号方框"
              "改成铅笔、「积分」从星形改成硬币加叶），压到 0.34%。"
              "二是**图标来源**：官方 Symbol 符号库共 579 个图标，但其中没有环保语义的图标"
              "（没有叶子、树、回收、碳），因此作品按统一 24×24 画布自绘了一套图标，"
              "运行时通过 `fillColor` 一套图标走遍所有配色。")
    table(doc,
          ["指标", "改造前", "改造后"],
          [["裸写颜色字符串", "104 处", "12 处（且均为带注释的装饰性透明白）"],
           ["「孤儿色」（不在规范里）", "12 种", "0 种"],
           ["官方字号令牌采纳", "26 次", "114 次"],
           ["裸写 `.fontSize(数字)`", "135 次", "51 次"],
           ["`animateTo` 动效调用", "0 处", "9 处"],
           ["使用英雄区的页面", "2 个", "5 个"],
           ["页面数", "5 个", "6 个（新增年度报告页）"],
           ["功能回归", "—", "40 项纯逻辑断言全部通过"]],
          widths=[Pt(150), Pt(120), Pt(180)])
    caption(doc, "表 9  视觉改造前后的可复现量化对比")

    heading(doc, "3.12 界面设计：改造前后对比", 2)
    body(doc, "为了让改造效果可核对，作品把同一页面在相同数据下的截图做了并排对比。"
              "下面六组对比覆盖记一笔、看板（含环形图与热力图）、积分、科普、我的"
              "以及本次新增的年度报告页。")
    figure(doc, f"{ASSET_DIR}/改造前后对比-前端美化.png",
           "图 15  六组「改造前 / 改造后」并排对比（含新增的年度报告页）", img_w_in=6.0)
    body(doc, "对比中可以清楚看到三件事：一是改造前界面并非「没有设计」，"
              "而是设计令牌没有被执行——同样的卡片在改造前后用的是同一个品牌绿，"
              "差别在于层次、留白与阴影；二是**信息密度不变而可读性提升**，"
              "改造没有增加功能，只是把已有的信息重新组织；"
              "三是**新增内容都落在已有语言里**，年度报告页与热力图虽然是新页面，"
              "但用的是同一套英雄区、卡片与配色，因此不显得突兀。")
    figure(doc, f"{ASSET_DIR}/图标集-预览.png",
           "图 16  自绘图标集总览：统一 24×24 画布与填充式造型，含本次新绘 / 重绘的 8 个图标",
           img_w_in=5.2)
    body(doc, "图标体系同样是工程化产物：图标由脚本批量生成并带边界自检，"
              "会检测内容是否被画布裁切（实测抓出并修掉了一个底部被裁的火焰图标）。")

    heading(doc, "3.13 新增页面：我的年度碳迹", 2)
    body(doc, "年度报告页是本次改造新增的第 6 个页面，从看板的入口横幅一键进入。"
              "它把分散在四个图表里的全年数据收拢到一页：封面给出年度、低碳称号、"
              "活跃天数与记录条数；正文依次给出全年累计减排、等效植树量、"
              "低碳记录条数、碳积分，以及按类目分解的减排构成条形图。")
    body(doc, "这一页的设计目标是「一页读完一年」，因此口径必须与看板严格一致："
              "减排构成的比例、颜色与看板环形图一一对应，"
              "等效植树量按「1 棵树·年 ≈ 18 kg CO₂e」折算并在页面底部写明口径，"
              "同时明确标注「数据全部保存在本机，不上传云端」。")
    image_grid(doc, [
        (f"{SHOT_DIR}/17-年度报告-封面.jpeg",
         "图 17  年度报告封面：2026 年度、低碳称号、活跃天数与核心数字卡"),
        (f"{SHOT_DIR}/18-年度报告-细节.jpeg",
         "图 18  碳积分 1,462 分、减排构成（四色条形）与「写在最后」"),
    ])

    doc.add_page_break()

    # ---------------- 四、软硬件选型 ----------------
    heading(doc, "四、软硬件选型", 1)
    heading(doc, "4.1 软件选型", 2)
    table(doc,
          ["用途", "选型", "选型理由"],
          [
              ["开发框架", "ArkTS ＋ ArkUI 声明式开发",
               "鸿蒙原生开发语言，类型安全，声明式 UI 有利于状态管理"],
              ["数据存储", "distributedKVStore（分布式键值库）",
               "为创新拓展 1 的多设备同步预留通道，避免后期重构数据层"],
              ["设备发现与同步", "distributedDeviceManager ＋ 分布式数据服务",
               "鸿蒙原生分布式能力，无需自建服务端"],
              ["图表绘制", "OpenHarmony-TPC 官方图表组件库",
               "纯 ArkTS 源码、可离线运行、支持折线／柱状／饼图，"
               "且源码可读可改，遇到问题不依赖第三方修复"],
              ["端侧推理", "MindSpore Lite ＋ MobileNetV2",
               "鸿蒙原生端侧推理框架，模型随包内置，推理全程离线"],
              ["文字识别", "Core Vision Kit（端侧文字识别）",
               "系统内置能力，无需联网，作为视觉通路的保底方案"],
              ["图片处理与分享", "Image Kit ＋ ArkUI 组件快照 ＋ MediaLibraryKit",
               "系统原生能力，保存到相册通过安全控件授权，无需申请敏感权限"],
          ],
          widths=[Pt(75), Pt(150), Pt(225)])
    caption(doc, "表 5  软件选型")

    heading(doc, "4.2 硬件选型", 2)
    body(doc, "本作品属于赛题分类中的「纯北向应用开发类」，"
              "按赛题说明「使用鸿蒙手机、平板或模拟器即可完成开发，无需额外采购硬件」，"
              "因此硬件需求仅为运行鸿蒙系统的手机或平板一台（开发阶段可使用模拟器）。"
              "若要完整体验创新拓展 1 的多设备同步能力，建议准备两台设备。")
    body(doc, "作品未使用任何开源鸿蒙开发板、传感器模组或通信模组，"
              "在硬件成本与部署复杂度上具有明显优势。")

    doc.add_page_break()

    # ---------------- 五、因子库 ----------------
    heading(doc, "五、碳排放因子库数据来源与折算方法", 1)
    body(doc, "本章是作品严谨性的核心，也是答辩时的重点说明内容。")

    heading(doc, "5.1 折算公式", 2)
    body(doc, "减排量按「基准情景与实际情景的差值」计算，公式为：", indent=False)
    p = doc.add_paragraph()
    p.alignment = WD_ALIGN_PARAGRAPH.CENTER
    p.paragraph_format.line_spacing = LINE_SPACING
    run = p.add_run("ER = AD × ( EF基准 − EF实际 )")
    set_run_font(run, size=Pt(13), bold=True)
    body(doc, "其中：ER 为减排量（kg CO₂e）；AD 为活动量（公里／度／立方米／公斤／餐次）；"
              "EF基准 为被替代的高碳行为的排放因子；EF实际 为实际低碳行为的排放因子。")
    body(doc, "需要特别强调：应用内所有因子的数值都已经是「基准情景与实际情景的差值」，"
              "即减排量而非排放量。每条因子的基准情景都在应用界面与下表中有明确标注。")

    heading(doc, "5.2 数据来源", 2)
    body(doc, "因子数据来自以下四类来源，按可信度与适用性排序：")
    bullet(doc, "中国产品全生命周期温室气体排放系数库（CPCD）：中国本土数据，"
                "用于出行类与回收塑料。")
    bullet(doc, "生态环境部、国家统计局《关于发布 2023 年电力二氧化碳排放因子的公告》"
                "（公告 2025 年第 47 号）：用于节约用电类。")
    bullet(doc, "英国环境、食品和农村事务部（DEFRA）温室气体换算因子："
                "用于中国官方尚未发布对应因子的条目，包括回收废纸、回收铝、"
                "回收旧衣物以及供水与污水处理。")
    bullet(doc, "中国科学院地理科学与资源研究所与世界自然基金会《中国城市餐饮食物浪费报告》"
                "（2018），结合联合国粮农组织《Food Wastage Footprint》（2013）折算："
                "用于光盘行动类。")

    heading(doc, "5.3 因子明细", 2)
    table(doc,
          ["类目", "行为", "单位", "因子值\n(kg CO₂e/单位)", "基准情景", "数据出处"],
          [
              ["出行", "步行", "公里", "0.19567", "燃油小汽车", "CPCD（2023）"],
              ["出行", "骑行", "公里", "0.19567", "燃油小汽车", "CPCD（2023）"],
              ["出行", "地铁出行", "公里", "0.15253", "燃油小汽车", "CPCD（2023）差值"],
              ["出行", "公交出行", "公里", "0.14267", "燃油小汽车", "CPCD（2023）差值"],
              ["出行", "新能源车出行", "公里", "0.02567", "燃油小汽车", "CPCD（2023）差值"],
              ["节水节电", "节约用电", "度", "0.5897", "等量电网供电", "生态环境部公告 2025 年第 47 号（河南省）"],
              ["节水节电", "少开空调", "度", "0.5897", "等量电网供电", "同上"],
              ["节水节电", "节约用水", "立方米", "0.36218", "等量供水与污水处理", "DEFRA 2025（英国口径）"],
              ["旧物回收", "回收塑料（PET）", "公斤", "0.3208", "原生 PET 生产", "CPCD（2022）差值"],
              ["旧物回收", "回收废纸", "公斤", "0.2197", "原生纸浆生产", "DEFRA 2025（英国口径）"],
              ["旧物回收", "回收易拉罐（铝）", "公斤", "8.1208", "原生铝电解生产", "DEFRA 2025（英国口径）"],
              ["旧物回收", "回收旧衣物", "公斤", "22.1578", "新纺织面料生产", "DEFRA 2025（英国口径）"],
              ["光盘行动", "光盘行动", "餐次", "0.19", "按每餐平均浪费量折算", "中科院地理所＋WWF（2018）× FAO（2013）折算"],
              ["光盘行动", "减少食物浪费", "公斤", "2.06", "混合食物碳强度均值", "FAO《Food Wastage Footprint》（2013）折算"],
          ],
          widths=[Pt(50), Pt(78), Pt(38), Pt(60), Pt(88), Pt(136)])
    caption(doc, "表 6  内置碳排放因子明细")

    heading(doc, "5.4 口径说明与局限性", 2)
    body(doc, "为保证数据可追溯，以下三点在设计中做了明确处理，也在此如实说明：")
    body(doc, "其一，出行类的基准情景为「燃油小汽车 0.19567 kgCO₂e/车·公里」，"
              "该数值来自 CPCD 中型汽油轿车「大门到坟墓」全生命周期口径，"
              "并假设为单人驾车（此时车·公里等于人·公里）。若多人共乘，"
              "人均排放应除以乘员数，本作品暂未做此折算，已在应用内说明。")
    body(doc, "其二，回收类、节水类与光盘行动类的部分因子采用英国 DEFRA 口径，"
              "原因是生态环境部等主管部门尚未发布对应的中国官方因子。"
              "此类因子在应用界面中均以「英国口径」明确标注，不做模糊处理。")
    body(doc, "其三，少开空调采用「节约的电量（度）」计量，而不采用「小时」。"
              "原因是每小时耗电量随空调匹数、能效等级与环境温度差异极大，"
              "目前没有权威出处可依，按小时计量会引入不可控误差。")
    body(doc, "此外需要说明两处容易误用的资料：生态环境部《大型活动碳中和实施指南（试行）》"
              "本身不含任何排放因子数值，它给出的是「排放源对应哪份标准」的对照关系，"
              "本作品将其作为合规性依据而非数值来源；"
              "《省级温室气体清单编制指南》属于区域清单方法学，"
              "其中并无「每人公里」口径的交通因子，不能直接用作个人出行因子。")

    doc.add_page_break()

    # ---------------- 六、测试结果 ----------------
    heading(doc, "六、测试结果", 1)
    heading(doc, "6.1 测试环境", 2)
    table(doc,
          ["项目", "配置"],
          [
              ["测试设备", "HarmonyOS 7.0.0 手机模拟器（分辨率 1320×2232，RAM 4 GB）"],
              ["开发工具", "DevEco Studio"],
              ["编译目标", "compatibleSdkVersion 5.0.0(12)"],
              ["安装方式", "本地签名后通过 hdc 安装"],
          ],
          widths=[Pt(110), Pt(340)])
    caption(doc, "表 7  测试环境")

    heading(doc, "6.2 功能测试", 2)
    table(doc,
          ["测试项", "操作与预期", "结果"],
          [
              ["低碳行为核算", "录入 12 公里步行，预期减排 12 × 0.19567 ≈ 2.35 kg CO₂e，"
                              "发放 235 积分", "通过（数值完全一致）"],
              ["数据持久化", "录入后重新安装应用，预期数据仍在", "通过"],
              ["看板折线图", "切换日／周／月／年，预期曲线与横轴标签同步更新", "通过"],
              ["看板柱状图", "预期显示四个类目对比，横轴显示类目名称，柱顶标注数值", "通过"],
              ["看板环形图与图例", "预期中心显示累计总量，图例给出百分比与进度条",
               "通过（百分比合计 100%，修复了曾出现的 2841% 异常值）"],
              ["减排日历热力图", "查看 12 周 × 7 天网格与连续记录天数",
               "通过（色阶按当日减排量分档，连续天数与记录一致）"],
              ["我的年度碳迹", "从看板入口进入报告页，核对全年汇总与减排构成",
               "通过（与看板数据完全一致）"],
              ["碳积分体系", "1,462 分下检查勋章与权益兑换可用性", "通过"],
              ["科普专栏", "8 篇文章按标签筛选与展开阅读", "通过"],
              ["数据管理", "备份为 JSON、导出 CSV，文件写入沙箱并回显路径", "通过"],
              ["智能任务推荐", "当日已记录出行后，剩余三类成为待办任务", "通过"],
              ["生活建议", "预期根据数据给出趋势对比与短板提醒", "通过"],
              ["分享图生成", "点击生成后，沙箱内出现 PNG 文件（约 97 KB）", "通过"],
              ["同步面板", "预期显示本机标识、可信设备、同步结果与冲突计数", "通过"],
              ["桌面服务卡片", "长按图标出现卡片入口，卡片渲染今日数据", "通过"],
              ["端侧 AI 自检", "模型加载并输出张量形状与 Top-5 候选", "通过"],
          ],
          widths=[Pt(95), Pt(250), Pt(105)])
    caption(doc, "表 8  功能测试结果")

    heading(doc, "6.3 逻辑单元测试", 2)
    body(doc, "除界面测试外，作品把不依赖界面的纯逻辑模块"
              "（因子算术、任务推荐、生活建议、通用工具函数）单独抽出，"
              "编译后在 Node 环境中执行断言测试。该测试无需真机即可运行，"
              "便于在开发过程中快速回归。当前共 40 项断言，全部通过，"
              "覆盖内容包括：")
    bullet(doc, "因子库算术自洽性：逐条验证「减排量 ＝ 基准 − 实际」，"
                "并校验全部因子数值为正、出处与基准情景非空、四个类目均有覆盖。")
    bullet(doc, "任务推荐引擎：新用户任务数、已完成标记、配额补齐、短板优先排序。")
    bullet(doc, "生活建议引擎：空数据引导、周对比趋势判断、未记录类目提醒。")
    bullet(doc, "通用工具函数：数值保留两位小数的边界行为、日期格式化、唯一标识生成。")
    body(doc, "该测试在开发过程中实际发现了两个缺陷，并已修复："
              "一是唯一标识生成函数在短时间内连续调用会产生重复；"
              "二是数据存储组件的读取接口在键不存在时的行为与其自身文档约定不一致，"
              "导致「不存在则写入默认值」的逻辑无法生效。")

    heading(doc, "6.4 已知限制", 2)
    body(doc, "为保持说明的完整性，以下限制如实列出：")
    table(doc,
          ["项目", "当前状态", "原因"],
          [
              ["创新拓展 1  多设备同步",
               "界面与业务逻辑已完成，同步面板可正常展示状态；"
               "尚未在两台真机之间做端到端验证",
               "测试所用模拟器不具备分布式软总线能力，"
               "且分布式数据同步权限需要真机授权弹窗"],
              ["创新拓展 2  端侧 AI 的类目标定",
               "视觉推理链路已实测可用；但「输出索引到业务类目」的标定表仍为空，"
               "因此视觉通路目前不产出建议；文字识别通路亦未在设备上验证",
               "标定必须用团队自己拍摄的真实照片，且文字识别能力不支持模拟器运行"],
              ["因子库部分条目",
               "回收类、节水类与光盘行动类采用英国 DEFRA 口径",
               "中国官方尚未发布对应因子，已在应用内明确标注"],
          ],
          widths=[Pt(105), Pt(200), Pt(145)])
    caption(doc, "表 10  已知限制")

    doc.add_page_break()

    # ---------------- 七、创新点 ----------------
    heading(doc, "七、创新点总结", 1)
    body(doc, "本作品的创新性不在于引入某项前沿技术，而在于针对「碳足迹记录」这一具体场景"
              "做了若干务实且有依据的工程决策。四条创新拓展已在前文分别说明，此处归纳要点：")
    table(doc,
          ["创新点", "核心做法", "解决的问题"],
          [
              ["超级终端多设备同步",
               "基于分布式数据服务的多设备同步，"
               "以时间戳信封处理冲突，并提供同步状态可视化面板",
               "换设备后碳数据断裂；家庭成员的减排量无法合并统计"],
              ["端侧 AI 图片识别",
               "端侧推理 ＋ 端侧文字识别双通路，按置信度融合，高置信才预填",
               "手动录入成本高；同时避免 AI 误判污染碳账本"],
              ["模拟城市碳普惠接口",
               "完整实现账户、上报、权益、兑换、订单五个环节，"
               "保留真实接口的异步、错误码、库存与幂等语义",
               "让「碳积分」从只能兑换虚拟徽章，升级为可对接真实权益"],
              ["智能服务与社交分享",
               "短板优先的任务推荐、数据事实驱动的建议、一键生成分享图",
               "用户难以坚持记录；减排成果缺乏可传播的呈现形式"],
          ],
          widths=[Pt(100), Pt(200), Pt(150)])
    caption(doc, "表 11  四条创新拓展要点")

    body(doc, "在鸿蒙特性体现方面，本作品可以明确回答「为什么不用其它平台」这一问题：")
    bullet(doc, "分布式数据同步依赖鸿蒙分布式软总线与分布式数据服务，"
                "数据在设备间直接流转而不经过云端，这在移动应用与小程序上无法实现。")
    bullet(doc, "端侧 AI 推理与端侧文字识别均为系统级能力，图片不出设备，"
                "契合信创语境下的数据主权要求。")
    bullet(doc, "全量数据本地存储、完全离线可用，演示环节不依赖任何网络条件。")
    body(doc, "除功能层面的创新外，作品在**界面工程**上也做了一次可量化的改造："
              "把《HarmonyOS 设计规范》的官方 Token 从「定义了但没执行」变成"
              "「逐页可核对」，裸写颜色从 104 处降到 12 处、动效从 0 处增加到 9 处、"
              "并新增减排日历热力图与年度报告页（详见 3.11–3.13）。"
              "这部分工作的价值在于：它同时提升了作品的完成度与答辩时的可解释性——"
              "每一个圆角、每一级文字灰度都能指到规范原文。")

    heading(doc, "八、局限与后续改进", 1)
    body(doc, "本作品当前的主要局限集中在验证覆盖度上：多设备同步与端侧图片识别两条通路"
              "受测试设备限制尚未完成端到端验证，其代码与业务逻辑已完成，"
              "待具备真机条件后即可验证。")
    body(doc, "后续改进方向有三个：一是补充真机验证，特别是端侧图片识别通路中"
              "「模型输出索引到业务类目」的标定工作，需要用真实拍摄的照片逐类标定；"
              "二是扩展碳排放因子库，特别是待中国官方发布回收类与节水类因子后及时替换；"
              "三是在数据积累到一定规模后，"
              "引入按周与按月的减排目标设定与达成提醒，进一步强化习惯养成效果。")
    body(doc, "作品的设计原则可以概括为一句话：把每一个数字都算清楚，"
              "把每一个来源都标明白，把每一点能力边界都如实说明。")

    # 清理文档属性 —— 大赛要求材料中不得出现团队/院校信息，
    # 而 python-docx 默认会写入 author="python-docx"、comments="generated by python-docx"，
    # 这类元数据既不专业，也可能被当成不合规来源，必须清掉。
    cp = doc.core_properties
    cp.author = ""
    cp.last_modified_by = ""
    cp.title = "碳迹 —— 设计说明书"
    cp.subject = "赛题二 碳足迹·全民绿色生活碳积分与减排指南"
    cp.comments = ""
    cp.category = ""
    cp.keywords = ""

    # 保存
    doc.save(OUT)
    print(f"已生成：{os.path.abspath(OUT)}")


if __name__ == "__main__":
    build()
