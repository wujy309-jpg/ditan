#!/usr/bin/env python3
"""把真实录屏片段合成为 16:9 功能演示视频（旁白：晓晓）。"""
import json, os, subprocess, sys
from PIL import Image, ImageDraw, ImageFont

W, H, FPS = 1920, 1080, 30
OUT = "交付物/演示视频_碳迹.mp4"
VIS = "/tmp/carbon-visuals"
REC = "/tmp/record"
AUD = "/tmp/carbon-real/audio"
SERIF = "/System/Library/Fonts/Supplemental/Songti.ttc"
INK=(32,29,23); INK2=(76,70,58); INK3=(133,124,106); RULE=(214,205,186); SEAL=(171,58,40); PAPER=(242,237,225)
def f(s,b=True): return ImageFont.truetype(SERIF,s,index=0 if b else 1)
F_T=font = f(54); F_K=f(22,False); F_B=f(30,False); F_S=f(21,False); F_N=f(110)

# (id, clip, trim, title, kicker, steps)
SEG = [
 ("int", None, 8.0, "真实操作录屏", "碳迹 · 功能演示", ["记一笔 → 看板 → 积分 → 科普 → 我的", "下面全部是应用的真实操作"]),
 ("s1", "seg1", 33.5, "选类目、填数量、保存", "01 / 记一笔", ["出行 → 步行", "6 公里 · 1.17 kg", "保存即入账", "因子标基准与出处"]),
 ("s2", "s2", 15.7, "日历与趋势", "02 / 看板", ["12 周日历", "连续记录天数", "上期对比曲线"]),
 ("s6", "s6", 10.4, "占比、任务与凭证", "03 / 看板", ["分类占比", "今日任务", "减排凭证"]),
 ("s3", "s3", 10.9, "余额与权益", "04 / 积分", ["五档可兑换权益", "勋章与证书", "积分流水"]),
 ("s4", "s4", 6.2, "八篇图文", "05 / 科普", ["四类标签", "展开阅读"]),
 ("s5", "s5", 11.5, "同步与数据", "06 / 我的", ["同步面板", "端侧 AI 自检", "JSON / CSV"]),
 ("s8", "s8", 10.8, "一页读完一年", "07 / 年度报告", ["记录与天数", "累计减排", "主力贡献"]),
 ("out", None, 5.0, "数据留在本机，离线可用", "结束", ["不上传云端", "碳迹 · 个人碳账本"]),
]
PH_X, PH_Y, PH_W, PH_H = 1110, 30, 604, 1020

def paper():
    return Image.open(f"{VIS}/paper-bg.png").convert("RGB").resize((W,H))

def base(seg):
    sid, clip, dur, title, kick, steps = seg
    im = paper(); d = ImageDraw.Draw(im)
    d.text((110, 70), kick, font=F_K, fill=INK3)
    if sid not in ("int", "out"):
        d.text((90, 150), kick[:2], font=F_N, fill=(228,219,202))
    d.text((110, 300), title, font=f(44), fill=INK)
    d.line([(110, 382),(1020,382)], fill=INK, width=3)
    d.line([(110, 390),(1020,390)], fill=RULE, width=2)
    y=430
    for i, st in enumerate(steps):
        d.text((110, y+4), f"0{i+1}", font=F_S, fill=(200,190,172))
        d.text((168, y), st, font=F_B, fill=INK2)
        y += 62
    if sid not in ("int", "out"):
        d.ellipse([1600, 84, 1614, 98], fill=SEAL)
        d.text((1626, 76), "实时录屏", font=F_S, fill=INK3)
    return im

def frame_iter(path, dur):
    cmd=["ffmpeg","-v","error","-ss","0.4","-t",str(max(0.1,dur-0.8)),"-i",path,
         "-f","rawvideo","-pix_fmt","rgb24","-r","30","-"]
    p=subprocess.Popen(cmd, stdout=subprocess.PIPE)
    fs=760*1284*3
    while True:
        b=b""
        while len(b)<fs:
            chunk=p.stdout.read(fs-len(b))
            if not chunk: break
            b+=chunk
        if len(b)<fs: break
        yield Image.frombytes("RGB",(760,1284),b)
    p.stdout.close(); p.wait()

def build():
    durations={r[0]:r[1] for r in json.load(open(f"{AUD}/durations.json"))}
    # 时间轴
    starts=[]; t=0.0
    for seg in SEG:
        starts.append(t); t += seg[2]
    total=t
    # 音轨
    order=[("r0",starts[0]),("r1",starts[1]+1.5),("r2",starts[2]+0.3),("r3",starts[3]+0.3),
           ("r4",starts[4]+0.3),("r5",starts[5]+0.2),("r6",starts[6]+0.3),
           ("r8",starts[7]+0.3),("r7",starts[8]+0.3)]
    inputs=[]; filters=[]; labs=[]
    for i,(rid,st) in enumerate(order):
        inputs += ["-i", f"{AUD}/{rid}.mp3"]
        ms=int(st*1000)
        filters.append(f"[{i}]adelay={ms}|{ms}[a{i}]")
        labs.append(f"[a{i}]")
    fc=";".join(filters)+";"+"".join(labs)+f"amix=inputs={len(labs)}:normalize=0,apad=pad_dur=1.5[aout]"
    audio=f"{AUD}/mix.m4a"
    subprocess.run(["ffmpeg","-y","-hide_banner","-loglevel","error"]+inputs+
                   ["-filter_complex",fc,"-map","[aout]","-c:a","aac","-b:a","128k",audio],check=True)
    # 编码
    cmd=["ffmpeg","-y","-hide_banner","-loglevel","error","-f","rawvideo","-pix_fmt","rgb24",
         "-s",f"{W}x{H}","-r",str(FPS),"-i","-","-i",audio,"-c:v","libx264",
         "-preset","veryfast","-crf","17","-pix_fmt","yuv420p","-c:a","aac","-b:a","128k",
         "-t",str(total),"-movflags","+faststart",OUT]
    proc=subprocess.Popen(cmd, stdin=subprocess.PIPE)
    pg=paper()
    # 预取首帧/末帧
    s1_first=next(frame_iter(f"{REC}/seg1.mp4", 33.5))
    s8_last=None
    for fr in frame_iter(f"{REC}/s8.mp4", 10.8): s8_last=fr
    def emit(im):
        proc.stdin.write(im.tobytes())

    for si, seg in enumerate(SEG):
        sid, clip, dur, title, kick, steps = seg
        canvas = base(seg)
        n = int(round(dur * FPS))
        if sid == "int":
            lay = s1_first.resize((PH_W, PH_H), Image.LANCZOS)
            canvas = canvas.copy(); canvas.paste(lay, (PH_X, PH_Y))
            d = ImageDraw.Draw(canvas); d.rectangle([PH_X, PH_Y, PH_X+PH_W-1, PH_Y+PH_H-1], outline=RULE, width=2)
            for k in range(n):
                im = canvas.copy()
                if k < 8: im = Image.blend(pg, im, k/8)
                emit(im)
        elif sid == "out":
            lay = s8_last.resize((PH_W, PH_H), Image.LANCZOS)
            canvas = canvas.copy(); canvas.paste(lay, (PH_X, PH_Y))
            d = ImageDraw.Draw(canvas); d.rectangle([PH_X, PH_Y, PH_X+PH_W-1, PH_Y+PH_H-1], outline=RULE, width=2)
            for k in range(n):
                im = canvas.copy()
                if k < 8: im = Image.blend(pg, im, k/8)
                emit(im)
        else:
            path = f"{REC}/{clip}.mp4"
            k = 0
            for fr in frame_iter(path, dur):
                im = canvas.copy()
                im.paste(fr.resize((PH_W, PH_H), Image.LANCZOS), (PH_X, PH_Y))
                d = ImageDraw.Draw(im); d.rectangle([PH_X, PH_Y, PH_X+PH_W-1, PH_Y+PH_H-1], outline=RULE, width=2)
                if k < 8: im = Image.blend(pg, im, k/8)
                # 进度
                tt = starts[si] + k / FPS
                d.line([(110,1048),(1810,1048)], fill=RULE, width=2)
                d.line([(110,1048),(110+(tt/total)*1700,1048)], fill=SEAL, width=3)
                emit(im); k += 1
                if k >= n: break
            # 若解码帧不足，补最后一帧
            while k < n:
                emit(im); k += 1
        print("seg", sid, "done", flush=True)
    proc.stdin.close(); proc.wait()
    print("saved",OUT,os.path.getsize(OUT)/1e6)

if __name__=="__main__":
    build()
