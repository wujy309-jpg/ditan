#!/usr/bin/env python3
"""生成《碳迹》演示视频（1920×1080，约 3'45"，H.264 + AAC）。

画面由已验证截图合成；旁白用 macOS 中文语音（Tingting）。
用法：python3 tools/docs/make_video_v3.py
"""
import json, math, os, subprocess, sys
from PIL import Image, ImageDraw, ImageFont, ImageFilter

W, H, FPS = 1920, 1080, 24
SHOT = "素材/截图/v3.3"
VIS = "/tmp/carbon-visuals"
AUD = "/tmp/carbon-video/audio"
OUT = "交付物/演示视频_碳迹.mp4"
SERIF = "/System/Library/Fonts/Supplemental/Songti.ttc"
HEI = "/System/Library/Fonts/STHeiti Medium.ttc"

INK = (32, 29, 23)
INK2 = (76, 70, 58)
INK3 = (133, 124, 106)
RULE = (214, 205, 186)
SEAL = (171, 58, 40)
PAPER = (242, 237, 225)
PAPER_L = (251, 248, 241)

def font(size, bold=True, hei=False):
    return ImageFont.truetype(HEI if hei else SERIF, size, index=0 if bold else 1)

F_TITLE = font(58)
F_SUB = font(30, False)
F_BODY = font(30, False)
F_SMALL = font(22, False)
F_KICK = font(22, False)
F_BIG = font(110)
F_NUM = font(72)
F_STEP = font(54)

def text_w(d, text, f):
    return d.textlength(text, font=f)

def wrap(d, text, f, width):
    lines, cur = [], ""
    for ch in text:
        if ch == "\n":
            lines.append(cur); cur = ""; continue
        if text_w(d, cur + ch, f) > width and cur:
            lines.append(cur); cur = ch
        else:
            cur += ch
    if cur:
        lines.append(cur)
    return lines

def draw_lines(d, x, y, lines, f, color=INK, lh=None, max_w=None):
    lh = lh or int(f.size * 1.55)
    for line in lines:
        d.text((x, y), line, font=f, fill=color)
        y += lh
    return y

def kicker(d, text):
    xx = 110
    for ch in text:
        d.text((xx, 66), ch, font=F_KICK, fill=INK3)
        xx += text_w(d, ch, F_KICK) + 5

def title(d, text, sub=None):
    d.text((110, 116), text, font=F_TITLE, fill=INK)
    d.line([(110, 206), (1080, 206)], fill=INK, width=4)
    d.line([(110, 216), (1080, 216)], fill=RULE, width=2)
    if sub:
        d.text((110, 242), sub, font=F_SUB, fill=INK3)

def bullet_block(d, x, y, items, width=980, f=F_BODY, gap=18):
    for head, body in items:
        d.ellipse([x, y + 14, x + 9, y + 23], fill=SEAL)
        d.text((x + 26, y), head, font=font(f.size + 2, True), fill=INK)
        y += int(f.size * 1.55)
        for line in wrap(d, body, f, width - 26):
            d.text((x + 26, y), line, font=f, fill=INK2)
            y += int(f.size * 1.52)
        y += gap
    return y

def footer(d, n, total):
    d.line([(110, 1032), (1810, 1032)], fill=RULE, width=2)
    d.text((110, 1044), "碳迹 · 赛题二", font=F_SMALL, fill=INK3)
    d.text((1740, 1044), f"{n:02d} / {total:02d}", font=F_SMALL, fill=INK3)

# ---------------------------------------------------------------- 手机层
class Phone:
    def __init__(self, path, h=860):
        self.im = Image.open(path).convert("RGB")
        self.w = int(h * self.im.width / self.im.height)
        self.h = h
        # 预放大 6%，留出推近余量
        self.big = self.im.resize((int(self.w * 1.06), int(self.h * 1.06)), Image.LANCZOS)
        self.path = path

    def layer(self, zoom=1.0, dx=0, dy=0):
        bw, bh = self.big.size
        cw, ch = int(bw / zoom), int(bh / zoom)
        cx = (bw - cw) // 2 + int(dx * bw)
        cy = (bh - ch) // 2 + int(dy * bh)
        cx = max(0, min(bw - cw, cx)); cy = max(0, min(bh - ch, cy))
        return self.big.crop((cx, cy, cx + cw, cy + ch)).resize((self.w, self.h), Image.LANCZOS)

def paste_phone(canvas, ph, x, y, zoom=1.0, dx=0, dy=0, alpha=1.0):
    layer = ph.layer(zoom, dx, dy)
    if alpha < 1.0:
        layer = Image.blend(Image.new("RGB", layer.size, PAPER), layer, alpha)
    canvas.paste(layer, (x, y))
    d = ImageDraw.Draw(canvas)
    d.rectangle([x, y, x + ph.w - 1, y + ph.h - 1], outline=RULE, width=2)

# ---------------------------------------------------------------- 场景背景
def bg():
    return Image.open(f"{VIS}/paper-bg.png").convert("RGB").resize((W, H))

def scene_cover():
    im = bg(); d = ImageDraw.Draw(im)
    d.text((110, 250), "碳　迹", font=font(150, True), fill=INK)
    d.text((116, 430), "个人碳账本", font=font(44, False), fill=INK2)
    d.line([(116, 510), (720, 510)], fill=INK, width=4)
    d.text((116, 548), "记录 → 折算 → 看见 → 激励 → 回馈", font=font(30, False), fill=INK2)
    d.text((116, 600), "一份可核对、可追溯、可离线运行的个人减排记录", font=font(26, False), fill=INK3)
    seal = Image.open(f"{VIS}/seal.png").convert("RGBA").resize((430, 430), Image.LANCZOS)
    im.paste(seal, (1320, 230), seal)
    d.text((1320, 690), "碳 账 本", font=font(26, False), fill=INK3)
    d.line([(110, 960), (1810, 960)], fill=RULE, width=2)
    d.text((110, 980), "2026 · 河南省高等学校信息技术应用创新大赛", font=font(24, False), fill=INK3)
    return im

def scene_problem():
    im = bg(); d = ImageDraw.Draw(im)
    kicker(d, "选题背景")
    title(d, "低碳生活，卡在三件事上")
    cols = [("算不清", "同一件事，不同口径\n能差出几倍。"),
            ("坚持难", "今天少开一次车，\n明天不会有任何变化。"),
            ("换不到", "减排量停在数字上，\n兑换不到真实权益。")]
    for i, (h, b) in enumerate(cols):
        x = 110 + i * 580
        d.text((x, 330), h, font=font(76, True), fill=INK)
        d.line([(x, 440), (x + 500, 440)], fill=RULE, width=2)
        y = 470
        for line in b.split("\n"):
            d.text((x, y), line, font=font(30, False), fill=INK2); y += 52
    d.text((110, 760), "碳迹把这三件事，连成一条能走通的闭环。", font=font(38, True), fill=INK)
    footer(d, 2, 15)
    return im

def scene_loop():
    im = bg(); d = ImageDraw.Draw(im)
    kicker(d, "设计思路")
    title(d, "一条闭环，五个动作")
    loop = Image.open(f"{VIS}/loop-naked.png").convert("RGB").resize((1120, 542), Image.LANCZOS)
    im.paste(loop, (760, 300))
    y = 330
    for h, b in [("记录", "四个类目，十四种行为"), ("折算", "活动量 × 因子，标出处"),
                 ("看见", "树、日历、四条趋势"), ("激励", "积分、徽章、证书"),
                 ("回馈", "上报碳普惠，兑换权益")]:
        d.text((110, y), h, font=font(34, True), fill=INK)
        d.text((110 + 120, y + 6), b, font=font(24, False), fill=INK2)
        y += 92
    footer(d, 3, 15)
    return im

def scene_entry():
    im = bg(); d = ImageDraw.Draw(im)
    kicker(d, "功能演示 · 记一笔")
    title(d, "记一笔：选、填、算、存", "六公里步行 → 1.17 kg CO₂e → 117 积分")
    bullet_block(d, 110, 330, [
        ("选类目", "四行账目行，不是四宫格色块"),
        ("点行为", "十四种常见行为，方角标签"),
        ("填数量", "下划线输入，减排量实时回显"),
        ("保存", "写入行为与积分两条键，立即入账"),
        ("可核对", "每条因子标基准情景与数据出处"),
    ], width=1050)
    footer(d, 4, 15)
    return im

def scene_dashboard():
    im = bg(); d = ImageDraw.Draw(im)
    kicker(d, "功能演示 · 看板")
    title(d, "看板：让坚持看得见")
    bullet_block(d, 110, 320, [
        ("我的树", "树冠密度 = 累计减排，0 条只有一根芽"),
        ("减排日历", "12 周 × 7 天，四档色阶 + 连续天数"),
        ("趋势", "折线带「上期」虚线；柱顶标数值；环形看占比"),
        ("同一份数据", "日 / 周 / 月 / 年，四种粒度共用一套口径"),
    ], width=1000)
    footer(d, 5, 15)
    return im

def scene_points():
    im = bg(); d = ImageDraw.Draw(im)
    kicker(d, "功能演示 · 积分与碳普惠")
    title(d, "积分：从数字到权益")
    bullet_block(d, 110, 330, [
        ("100 积分 / kg", "每减排 1 kg 得 100 分"),
        ("四枚勋章", "100 / 300 / 500 / 1000 分依次解锁"),
        ("五档权益", "地铁券、单车券、购物袋、门票、电费红包"),
        ("真实语义", "异步、错误码、库存扣减、幂等"),
        ("可替换", "换通信层即可对接真实平台"),
    ], width=1030)
    footer(d, 6, 15)
    return im

def scene_know():
    im = bg(); d = ImageDraw.Draw(im)
    kicker(d, "功能演示 · 科普与我的")
    title(d, "内容与数据，都能带走")
    bullet_block(d, 110, 340, [
        ("科普 8 篇", "政策 / 概念 / 数据 / 技巧，宋体标题 + 朱砂分类"),
        ("同步面板", "本机标识、可信设备、冲突数，全部可见"),
        ("数据管理", "JSON 备份、CSV 报表、清空；默认不上传云端"),
    ], width=1030)
    footer(d, 7, 15)
    return im

def scene_year():
    im = bg(); d = ImageDraw.Draw(im)
    kicker(d, "延伸页面 · 年度报告")
    title(d, "年度报告：一页读完一年")
    bullet_block(d, 110, 350, [
        ("封面", "2026、低碳生活家、活跃 11 天、11 条记录"),
        ("正文", "累计减排 20.58 kg、等效植树 1.1 棵·年"),
        ("一致", "减排构成与看板同源、同口径，合计 100%"),
    ], width=1030)
    footer(d, 8, 15)
    return im

def scene_voucher():
    im = bg(); d = ImageDraw.Draw(im)
    kicker(d, "功能演示 · 减排凭证")
    title(d, "分享：不是海报，是凭证")
    bullet_block(d, 110, 350, [
        ("小票式排版", "抬头、账簿双线、引导点线明细、落款"),
        ("朱印骑缝", "印章压住细线，像真的盖上去"),
        ("同形", "确定性种子，屏幕与分享图逐像素同形"),
    ], width=1000)
    footer(d, 9, 15)
    return im

def scene_sync():
    im = bg(); d = ImageDraw.Draw(im)
    kicker(d, "创新拓展 · 超级终端")
    title(d, "数据在设备之间直接走")
    d.text((110, 300), "不经过云端。", font=font(72, True), fill=INK)
    bullet_block(d, 110, 430, [
        ("时间戳信封", "写入 { payload, ts, origin }，逐键比较，较新者胜出"),
        ("只增不改", "积分流水是追加型数据，天然免冲突"),
        ("可见", "冲突数、远端写入数在面板中如实展示"),
    ], width=900)
    # 两台设备
    for i, x in enumerate((1240, 1560)):
        d.rectangle([x, 360, x + 210, 640], outline=INK2, width=3, fill=PAPER_L)
        d.rectangle([x + 10, 390, x + 200, 610], outline=RULE, width=2)
        d.text((x + 55, 420), "碳 迹", font=font(28, True), fill=INK2)
        d.text((x + 45, 480), "11 条记录", font=font(20, False), fill=INK3)
        d.text((x + 55, 580), "设备" + str(i + 1), font=font(20, False), fill=INK3)
    d.line([(1455, 500), (1555, 500)], fill=SEAL, width=3)
    d.polygon([(1555, 500), (1538, 490), (1538, 510)], fill=SEAL)
    d.text((1420, 520), "同步", font=font(22, False), fill=SEAL)
    footer(d, 10, 15)
    return im

def scene_ai():
    im = bg(); d = ImageDraw.Draw(im)
    kicker(d, "创新拓展 · 端侧 AI")
    title(d, "图片不出设备，只做预填")
    ai = Image.open(f"{VIS}/ai-path.png").convert("RGB").resize((1180, 590), Image.LANCZOS)
    im.paste(ai, (650, 300))
    d.text((110, 320), "两条通路", font=font(40, True), fill=INK)
    for i, t in enumerate(["视觉：MobileNetV2 端侧推理", "文字：Core Vision Kit 读字",
                           "融合：一致加分，冲突取高", "克制：只预填，不判定"]):
        d.text((110, 390 + i * 62), t, font=font(26, False), fill=INK2)
    footer(d, 11, 15)
    return im

def scene_platform():
    im = bg(); d = ImageDraw.Draw(im)
    kicker(d, "创新拓展 · 城市碳普惠")
    title(d, "五个环节，按真实接口的语义实现")
    steps = ["绑定", "上报", "查询", "兑换", "订单"]
    for i, st in enumerate(steps):
        x = 140 + i * 350
        d.ellipse([x, 340, x + 88, 428], outline=SEAL, width=3)
        d.text((x + 22, 355), f"0{i+1}", font=font(26, True), fill=SEAL)
        d.text((x, 460), st, font=font(40, True), fill=INK)
        if i < 4:
            d.line([(x + 120, 384), (x + 300, 384)], fill=RULE, width=3)
    d.text((110, 620), "异步与延迟 · 业务错误码 · 库存原子扣减 · 幂等请求", font=font(28, False), fill=INK2)
    d.text((110, 690), "业务层只依赖接口契约：换通信层，业务逻辑一行不改。", font=font(30, True), fill=INK)
    footer(d, 12, 15)
    return im

def scene_visual():
    im = bg(); d = ImageDraw.Draw(im)
    kicker(d, "视觉体系")
    title(d, "界面：碳账本，不是模板")
    cmp = Image.open("素材/改造前后对比-v3账本.png").convert("RGB")
    cmp.thumbnail((1260, 760), Image.LANCZOS)
    im.paste(cmp, (610, 280))
    d.text((110, 330), "为什么推翻 v2", font=font(36, True), fill=INK)
    for i, t in enumerate(["不是配色问题，是模板感", "纸、墨、细线、宋体、朱印",
                           "双线表头 / 引导点线 / 朱印", "圆角 2、阴影全透明"]):
        d.text((110, 400 + i * 64), t, font=font(26, False), fill=INK2)
    footer(d, 13, 15)
    return im

def scene_test():
    im = bg(); d = ImageDraw.Draw(im)
    kicker(d, "测试与验证")
    title(d, "用可复现，代替「应该可以」")
    nums = [("55", "项纯逻辑断言，0 失败"), ("24", "个图标，重量极差 0.34%"),
            ("5", "从构建到能力的五层验证")]
    for i, (n, lab) in enumerate(nums):
        x = 130 + i * 560
        d.text((x, 330), n, font=font(110, True), fill=INK)
        for j, line in enumerate(wrap(d, lab, font(24, False), 430)):
            d.text((x, 470 + j * 36), line, font=font(24, False), fill=INK3)
    d.text((110, 650), "修过，才算测过：环形图 2841% / 按钮胶囊 / 柱子纯黑 / 印章不同形", font=font(26, False), fill=INK2)
    d.text((110, 710), "构建 → 安装 → 五页签逐页截图，一条命令可复现。", font=font(26, False), fill=INK2)
    footer(d, 14, 15)
    return im

def scene_close():
    im = bg(); d = ImageDraw.Draw(im)
    d.text((110, 280), "把每一笔低碳，", font=font(76, True), fill=INK)
    d.text((110, 390), "都记成看得见的改变。", font=font(76, True), fill=INK)
    d.line([(110, 540), (820, 540)], fill=INK, width=4)
    d.text((110, 580), "碳迹 · 个人碳账本　|　HarmonyOS · ArkTS / ArkUI · API 12", font=font(26, False), fill=INK2)
    d.text((110, 640), "数据全部保存在本机 · 不上传云端 · 可离线演示", font=font(24, False), fill=INK3)
    seal = Image.open(f"{VIS}/seal.png").convert("RGBA").resize((380, 380), Image.LANCZOS)
    im.paste(seal, (1320, 260), seal)
    return im

# ---------------------------------------------------------------- 组装
def build():
    durations = {r[0]: r[1] for r in json.load(open(f"{AUD}/durations.json"))}
    scenes = [
        ("s00", scene_cover, []),
        ("s01", scene_problem, []),
        ("s02", scene_loop, []),
        ("s03", scene_entry, [("phone", f"{SHOT}/00-记一笔-总览.jpeg", 0.0, 11.0, (0, 0)),
                              ("phone", f"{SHOT}/01-记一笔-填写.jpeg", 7.5, 99, (0, 0))]),
        ("s04", scene_dashboard, [("phone", f"{SHOT}/10-看板-总览.jpeg", 0.0, 10.0, (0, 0)),
                                  ("phone", f"{SHOT}/11-看板-日历.jpeg", 10.0, 20.0, (0, 0)),
                                  ("phone", f"{SHOT}/12-看板-分类与任务.jpeg", 20.0, 99, (0, 0))]),
        ("s05", scene_points, [("phone", f"{SHOT}/20-积分-碳普惠.jpeg", 0.0, 11.0, (0, 0)),
                               ("phone", f"{SHOT}/21-积分-权益与流水.jpeg", 11.0, 99, (0, 0))]),
        ("s06", scene_know, [("phone", f"{SHOT}/30-科普-专栏.jpeg", 0.0, 7.0, (0, 0)),
                             ("phone", f"{SHOT}/41-我的-同步与数据.jpeg", 7.0, 99, (0, 0))]),
        ("s07", scene_year, [("phone", f"{SHOT}/50-年度报告-封面.jpeg", 0.0, 6.0, (0, 0)),
                             ("phone", f"{SHOT}/51-年度报告-构成.jpeg", 6.0, 99, (0, 0))]),
        ("s08", scene_voucher, [("phone", f"{SHOT}/15-看板-分享凭证.jpeg", 0.0, 99, (0, 0))]),
        ("s09", scene_sync, []),
        ("s10", scene_ai, []),
        ("s11", scene_platform, []),
        ("s12", scene_visual, []),
        ("s13", scene_test, []),
        ("s14", scene_close, []),
    ]
    PH_X, PH_Y, PH_H = 1310, 118, 860
    phones = {}
    for sid, fn, plist in scenes:
        for p in plist:
            if p[1] not in phones:
                phones[p[1]] = Phone(p[1], PH_H)

    # 计算每场景时长
    order = []
    t = 0.0
    for sid, fn, plist in scenes:
        dur = max(durations[sid] + 1.5, 6.0)
        order.append((sid, fn, plist, dur, t))
        t += dur
    total = t + 1.0
    bases = {sid: fn() for sid, fn, plist, dur, st in order}

    # 音轨
    audio = f"{AUD}/mix.m4a"
    inputs, filters, labs = [], [], []
    for i, (sid, fn, plist, dur, st) in enumerate(order):
        inputs += ["-i", f"{AUD}/{sid}.aiff"]
        ms = int(st * 1000)
        filters.append(f"[{i}]adelay={ms}|{ms}[a{i}]")
        labs.append(f"[a{i}]")
    fc = ";".join(filters) + ";" + "".join(labs) + f"amix=inputs={len(labs)}:normalize=0,apad=pad_dur=1.5[aout]"
    subprocess.run(["ffmpeg", "-y", "-hide_banner", "-loglevel", "error"] + inputs +
                   ["-filter_complex", fc, "-map", "[aout]", "-c:a", "aac", "-b:a", "128k", audio], check=True)
    print("audio", round(total, 1))

    # 视频
    os.makedirs("/tmp/carbon-video", exist_ok=True)
    cmd = ["ffmpeg", "-y", "-hide_banner", "-loglevel", "error",
           "-f", "rawvideo", "-pix_fmt", "rgb24", "-s", f"{W}x{H}", "-r", str(FPS), "-i", "-",
           "-i", audio, "-c:v", "libx264", "-preset", "veryfast", "-crf", "16",
           "-pix_fmt", "yuv420p", "-c:a", "aac", "-b:a", "128k", "-shortest",
           "-movflags", "+faststart", OUT]
    proc = subprocess.Popen(cmd, stdin=subprocess.PIPE)
    paper = Image.new("RGB", (W, H), PAPER)
    frames = int(total * FPS)
    for fi in range(frames):
        tt = fi / FPS
        # 找场景
        sc = order[-1]
        for item in order:
            if item[4] <= tt < item[4] + item[3]:
                sc = item; break
        sid, fn, plist, dur, st = sc
        local = tt - st
        im = bases[sid].copy()
        # 手机
        for p in plist:
            _, path, a, b, _ = p
            if b > dur:
                b = dur
            if a <= local <= b:
                alpha = 1.0
                # 交叉淡入
                if local < a + 0.7 and a > 0:
                    alpha = (local - a) / 0.7
                zoom = 1.0 + 0.035 * (local - a) / max(0.1, b - a)
                paste_phone(im, phones[path], PH_X, PH_Y, zoom=zoom, alpha=alpha)
        # 进度条
        d = ImageDraw.Draw(im)
        if sid not in ("s00", "s14"):
            d.line([(110, 1006), (1810, 1006)], fill=RULE, width=2)
            prog = (tt / total) * 1700
            d.line([(110, 1006), (110 + prog, 1006)], fill=SEAL, width=3)
        # 场景淡入/淡出
        fade = 0.28
        if local < fade:
            a = local / fade
            im = Image.blend(paper, im, a)
        elif dur - local < fade:
            a = (dur - local) / fade
            im = Image.blend(paper, im, a)
        proc.stdin.write(im.tobytes())
        if fi % 240 == 0:
            print("frame", fi, "/", frames, f"{fi/frames*100:.0f}%", flush=True)
    proc.stdin.close()
    proc.wait()
    print("saved", OUT, os.path.getsize(OUT) / 1e6, "MB")

if __name__ == "__main__":
    build()
