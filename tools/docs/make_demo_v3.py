#!/usr/bin/env python3
"""《碳迹》功能演示视频（UI 为主，1920×1080，约 3 分钟）。

与旧版的区别：不再用「左侧大段文字 + 右侧手机」的 PPT 式版式，
改成「手机占主画面 + 左侧步骤标注 + 点击涟漪」，旁白只讲操作与结果。
"""
import json, math, os, subprocess
from PIL import Image, ImageDraw, ImageFont

W, H, FPS = 1920, 1080, 24
SHOT = "素材/截图/v3.3"
VIS = "/tmp/carbon-visuals"
AUD = "/tmp/carbon-demo/audio"
OUT = "交付物/演示视频_碳迹.mp4"
SERIF = "/System/Library/Fonts/Supplemental/Songti.ttc"
HEI = "/System/Library/Fonts/STHeiti Medium.ttc"

INK = (32, 29, 23); INK2 = (76, 70, 58); INK3 = (133, 124, 106)
RULE = (214, 205, 186); SEAL = (171, 58, 40); PAPER = (242, 237, 225)

def font(s, b=True):
    return ImageFont.truetype(SERIF, s, index=0 if b else 1)

F_TITLE = font(52); F_BODY = font(30, False); F_SMALL = font(21, False)
F_KICK = font(22, False); F_BIG = font(120)

def wrap(d, text, f, width):
    lines, cur = [], ""
    for ch in text:
        if ch == "\n": lines.append(cur); cur = ""; continue
        if d.textlength(cur + ch, font=f) > width and cur:
            lines.append(cur); cur = ch
        else:
            cur += ch
    if cur: lines.append(cur)
    return lines

def bg():
    return Image.open(f"{VIS}/paper-bg.png").convert("RGB").resize((W, H))

class Phone:
    def __init__(self, path, h=1020):
        im = Image.open(path).convert("RGB").crop((0, 117, 1320, 2232))
        self.w = int(h * im.width / im.height); self.h = h
        self.big = im.resize((int(self.w*1.05), int(self.h*1.05)), Image.LANCZOS)
    def layer(self, zoom=1.0):
        bw, bh = self.big.size
        cw, ch = int(bw/zoom), int(bh/zoom)
        cx, cy = (bw-cw)//2, (bh-ch)//2
        return self.big.crop((cx, cy, cx+cw, cy+ch)).resize((self.w, self.h), Image.LANCZOS)

def paste(canvas, ph, x, y, zoom=1.0, alpha=1.0):
    lay = ph.layer(zoom)
    if alpha < 1:
        lay = Image.blend(Image.new("RGB", lay.size, PAPER), lay, alpha)
    canvas.paste(lay, (x, y))
    d = ImageDraw.Draw(canvas)
    d.rectangle([x, y, x+ph.w-1, y+ph.h-1], outline=(200,190,172), width=2)

def base(kicker, num, title, lines=None, metric=None, metric_label=None, steps=None, step_at=None):
    im = bg(); d = ImageDraw.Draw(im)
    d.text((70, 150), num, font=F_BIG, fill=(228, 219, 202))
    d.text((110, 60), kicker, font=F_KICK, fill=INK3)
    d.text((110, 300), title, font=F_TITLE, fill=INK)
    d.line([(110, 380), (1020, 380)], fill=INK, width=3)
    d.line([(110, 388), (1020, 388)], fill=RULE, width=2)
    y = 430
    if steps:
        for i, st in enumerate(steps):
            d.text((110, y-2), f"0{i+1}", font=font(24, True), fill=(214, 206, 191))
            d.text((165, y-8), st, font=font(31, True), fill=(205, 196, 180))
            y += 62
    else:
        for line in (lines or []):
            d.ellipse([110, y+12, 118, y+20], fill=SEAL)
            d.text((134, y), line, font=F_BODY, fill=INK2)
            y += 58
    if metric:
        d.text((110, 790), metric, font=font(64, True), fill=INK)
        d.text((110, 868), metric_label or "", font=F_SMALL, fill=INK3)
    return im

PH_X, PH_Y, PH_H = 1100, 40, 990
phones = {}

def tap_ring(d, x, y, p):
    if p < 0 or p > 1: return
    r = 8 + 70 * p
    a = int(210 * (1-p))
    for k in (0, 0.45, 0.9):
        rr = r + k*18
        aa = max(0, a - int(120*k))
        d.ellipse([x-rr, y-rr, x+rr, y+rr], outline=SEAL+(aa,), width=3)
    d.ellipse([x-5, y-5, x+5, y+5], fill=SEAL)

def build():
    durations = {r[0]: r[1] for r in json.load(open(f"{AUD}/durations.json"))}
    scenes = [
        ("d0", dict(kicker="碳迹 · 功能演示", num="", title="四分钟，走完一本碳账本",
                    lines=["记录 → 折算 → 看见 → 激励 → 回馈", "全部数据留在本机"],
                    metric="20.58 kg", metric_label="累计减排 · 11 条记录"),
         [(f"{SHOT}/10-看板-总览.jpeg", 0, 99)], []),
        ("d1", dict(kicker="01 / 记一笔", num="01", title="选类目、填数量、保存",
                    steps=["选类目 · 四个类目", "点行为 · 十四种行为", "填数量 · 6 公里", "保存 · 1.17 kg / +117 分"],
                    step_at=[0, 5, 10, 17],
                    metric="1.17 kg", metric_label="一笔 6 公里步行"),
         [(f"{SHOT}/00-记一笔-总览.jpeg", 0, 7.5), (f"{SHOT}/01-记一笔-填写.jpeg", 7.5, 19.0),
          (f"{SHOT}/02-记一笔-最近记录.jpeg", 19.0, 99)],
         [(3.0, 660, 1680), (10.0, 660, 270), (17.0, 660, 810)]),
        ("d2", dict(kicker="02 / 看板", num="02", title="树、日历、四条趋势",
                    steps=["总览 · 我的树", "日历 · 连续 5 天", "趋势 · 上期对比", "占比 · 四类构成"],
                    step_at=[0, 8.5, 19, 24],
                    metric="20.58 kg", metric_label="累计减排 · 折合 1.1 棵树·年"),
         [(f"{SHOT}/10-看板-总览.jpeg", 0, 8.5), (f"{SHOT}/11-看板-日历.jpeg", 8.5, 19.0),
          (f"{SHOT}/12-看板-分类与任务.jpeg", 19.0, 99)], []),
        ("d3", dict(kicker="03 / 年度报告", num="03", title="一页读完一年",
                    steps=["封面 · 2026 / 低碳生活家", "数字 · 11 条 / 11 天", "构成 · 与看板同口径"],
                    step_at=[0, 5, 9],
                    metric="2,058", metric_label="全年碳积分"),
         [(f"{SHOT}/50-年度报告-封面.jpeg", 0, 5.0), (f"{SHOT}/51-年度报告-构成.jpeg", 5.0, 99)], []),
        ("d4", dict(kicker="04 / 积分与碳普惠", num="04", title="从数字到权益",
                    steps=["余额 · 2,058 分", "上报 · 绑定碳普惠账户", "兑换 · 地铁券 / 单车券", "流水 · 逐条可追溯"],
                    step_at=[0, 7, 15, 20],
                    metric="2,058", metric_label="当前碳积分 · 待上报"),
         [(f"{SHOT}/20-积分-碳普惠.jpeg", 0, 11.0), (f"{SHOT}/21-积分-权益与流水.jpeg", 11.0, 99)],
         [(5.0, 660, 1405)]),
        ("d5", dict(kicker="05 / 双碳科普", num="05", title="八篇图文，四类标签",
                    steps=["四类标签", "8 篇图文", "展开即读"], step_at=[0, 2, 4],
                    metric="8", metric_label="篇科普"),
         [(f"{SHOT}/30-科普-专栏.jpeg", 0, 99)], []),
        ("d6", dict(kicker="06 / 我的", num="06", title="同步、自检、数据管理",
                    steps=["档案 · 称号与家庭 ID", "同步 · 设备 / 冲突数", "自检 · 端侧 AI", "数据 · JSON / CSV"],
                    step_at=[0, 6, 14, 20],
                    metric="0", metric_label="冲突记录数（模拟器无其它设备）"),
         [(f"{SHOT}/40-我的-档案.jpeg", 0, 6.0), (f"{SHOT}/41-我的-同步与数据.jpeg", 6.0, 99)],
         [(9.0, 660, 1260)]),
        ("d7", dict(kicker="07 / 减排凭证", num="07", title="分享不是海报，是凭证",
                    steps=["抬头 · 累计减排", "明细 · 记录 / 天数 / 贡献", "落款 · 朱印骑缝", "保存 · 生成 PNG"],
                    step_at=[0, 4, 8, 12],
                    metric="1 张", metric_label="一键生成 PNG"),
         [(f"{SHOT}/15-看板-分享凭证.jpeg", 0, 99)], [(4.0, 660, 1900)]),
        ("d8", dict(kicker="08 / 鸿蒙能力", num="08", title="三个能力，离线可用",
                    steps=["同步 · 设备之间直接走", "AI · 图片不出设备", "碳普惠 · 五环节", "数据 · 全部本机"],
                    step_at=[0, 8, 15, 20],
                    metric="0", metric_label="云端依赖"),
         [(f"{SHOT}/41-我的-同步与数据.jpeg", 0, 8.0), (f"{SHOT}/20-积分-碳普惠.jpeg", 8.0, 15.0),
          (f"{SHOT}/15-看板-分享凭证.jpeg", 15.0, 99)], []),
        ("d9", dict(kicker="结束", num="", title="把每一笔低碳，记成看得见的改变",
                    lines=["数据留在本机 · 可离线演示"], metric="", metric_label=""),
         [(f"{SHOT}/10-看板-总览.jpeg", 0, 99)], []),
    ]

    order = []; t = 0.0
    for sid, meta, plist, taps in scenes:
        dur = max(durations[sid] + 1.6, 8.0)
        order.append((sid, meta, plist, taps, dur, t)); t += dur
    total = t + 1.0
    for _, _, plist, _, _, _ in order:
        for p in plist:
            if p[0] not in phones:
                phones[p[0]] = Phone(p[0], PH_H)
    bases = {sid: base(**meta) for sid, meta, *_ in order}

    # 音轨
    inputs, filters, labs = [], [], []
    for i, (sid, meta, plist, taps, dur, st) in enumerate(order):
        inputs += ["-i", f"{AUD}/{sid}.mp3"]
        ms = int(st*1000)
        filters.append(f"[{i}]adelay={ms}|{ms}[a{i}]")
        labs.append(f"[a{i}]")
    fc = ";".join(filters) + ";" + "".join(labs) + f"amix=inputs={len(labs)}:normalize=0,apad=pad_dur=1.5[aout]"
    audio = f"{AUD}/mix.m4a"
    subprocess.run(["ffmpeg","-y","-hide_banner","-loglevel","error"] + inputs +
                   ["-filter_complex", fc, "-map", "[aout]", "-c:a", "aac", "-b:a", "128k", audio], check=True)

    cmd = ["ffmpeg","-y","-hide_banner","-loglevel","error",
           "-f","rawvideo","-pix_fmt","rgb24","-s",f"{W}x{H}","-r",str(FPS),"-i","-",
           "-i",audio,"-c:v","libx264","-preset","veryfast","-crf","16",
           "-pix_fmt","yuv420p","-c:a","aac","-b:a","128k","-shortest",
           "-movflags","+faststart",OUT]
    proc = subprocess.Popen(cmd, stdin=subprocess.PIPE)
    paper = Image.new("RGB", (W, H), PAPER)
    frames = int(total*FPS)
    for fi in range(frames):
        tt = fi/FPS
        sc = order[-1]
        for item in order:
            if item[5] <= tt < item[5] + item[4]:
                sc = item; break
        sid, meta, plist, taps, dur, st = sc
        local = tt - st
        im = bases[sid].copy()
        # 手机
        for path, a, b in plist:
            b = min(b, dur)
            if a <= local <= b:
                alpha = 1.0
                if local < a + 0.5 and a > 0:
                    alpha = (local - a)/0.5
                zoom = 1.0 + 0.02*(local-a)/max(0.1, b-a)
                paste(im, phones[path], PH_X, PH_Y, zoom, alpha)
        # 当前步骤高亮
        d = ImageDraw.Draw(im)
        if meta.get("steps"):
            idx = 0
            for i, ts in enumerate(meta.get("step_at", [])):
                if local >= ts:
                    idx = i
            for i, stx in enumerate(meta["steps"]):
                yy = 430 + 62 * i
                if i > idx:
                    continue
                d.rectangle([100, yy - 10, 1020, yy + 40], fill=PAPER)
                if i < idx:
                    d.text((110, yy - 2), "✓", font=font(24, True), fill=INK3)
                    d.text((165, yy - 8), stx, font=font(31, True), fill=INK2)
                else:
                    d.text((110, yy - 2), f"0{i+1}", font=font(24, True), fill=SEAL)
                    d.text((165, yy - 8), stx, font=font(31, True), fill=SEAL)
        for (ts, sx, sy) in taps:
            p = (local - ts)/0.9
            if 0 <= p <= 1:
                scale = PH_H/2115
                x = PH_X + sx*scale
                y = PH_Y + (sy-117)*scale
                tap_ring(d, x, y, p)
        # 进度
        d.line([(110, 1048), (1810, 1048)], fill=RULE, width=2)
        d.line([(110, 1048), (110 + (tt/total)*1700, 1048)], fill=SEAL, width=3)
        # 转场
        fade = 0.28
        if local < fade:
            im = Image.blend(paper, im, local/fade)
        elif dur - local < fade:
            im = Image.blend(paper, im, (dur-local)/fade)
        proc.stdin.write(im.tobytes())
        if fi % 240 == 0:
            print("frame", fi, "/", frames, flush=True)
    proc.stdin.close(); proc.wait()
    print("saved", OUT, os.path.getsize(OUT)/1e6, "MB")

if __name__ == "__main__":
    build()
