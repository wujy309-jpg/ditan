#!/usr/bin/env python3
"""用 22 页 PPT 的渲染图 + 讲稿旁白，生成 PPT 讲解视频（≤10 分钟）。"""
import json, os, subprocess
from PIL import Image, ImageDraw

W,H,FPS=1920,1080,24
AUD="/tmp/ppt-video/audio"; SLIDES="/tmp/ppt-slides"
OUT="交付物/演示文稿_讲解视频.mp4"
INK=(32,29,23); RULE=(214,205,186); SEAL=(171,58,40); PAPER=(242,237,225)

def build():
    rows=json.load(open(f"{AUD}/durations.json"))
    starts=[]; t=0.0
    for sid,dur,text in rows:
        starts.append(t); t += max(dur+1.0, 3.0)
    total=t
    # audio mix
    inputs=[]; filters=[]; labs=[]
    for i,(sid,dur,text) in enumerate(rows):
        inputs += ["-i", f"{AUD}/{sid}.mp3"]
        ms=int(starts[i]*1000)
        filters.append(f"[{i}]adelay={ms}|{ms}[a{i}]")
        labs.append(f"[a{i}]")
    fc=";".join(filters)+";"+"".join(labs)+f"amix=inputs={len(labs)}:normalize=0,apad=pad_dur=1.2[aout]"
    audio=f"{AUD}/mix.m4a"
    subprocess.run(["ffmpeg","-y","-hide_banner","-loglevel","error"]+inputs+
                   ["-filter_complex",fc,"-map","[aout]","-c:a","aac","-b:a","128k",audio],check=True)
    cmd=["ffmpeg","-y","-hide_banner","-loglevel","error","-f","rawvideo","-pix_fmt","rgb24",
         "-s",f"{W}x{H}","-r",str(FPS),"-i","-","-i",audio,"-c:v","libx264",
         "-preset","veryfast","-crf","18","-pix_fmt","yuv420p","-c:a","aac","-b:a","128k",
         "-t",str(total),"-movflags","+faststart",OUT]
    proc=subprocess.Popen(cmd,stdin=subprocess.PIPE)
    paper=Image.new("RGB",(W,H),PAPER)
    for i,(sid,dur,text) in enumerate(rows):
        im=Image.open(f"{SLIDES}/slide-{i+1:02d}.png").convert("RGB").resize((W,H),Image.LANCZOS)
        n=int(round(max(dur+1.0,3.0)*FPS))
        for k in range(n):
            fr=im.copy(); d=ImageDraw.Draw(fr)
            # 进度
            tt=starts[i]+k/FPS
            d.line([(60,1050),(1860,1050)],fill=RULE,width=2)
            d.line([(60,1050),(60+(tt/total)*1800,1050)],fill=SEAL,width=3)
            if k<8: fr=Image.blend(paper,fr,k/8)
            if n-k<8: fr=Image.blend(paper,fr,(n-k)/8)
            proc.stdin.write(fr.tobytes())
        print("slide",i+1,"done",flush=True)
    proc.stdin.close(); proc.wait()
    print("saved",OUT,os.path.getsize(OUT)/1e6,"MB",round(total,1),"s")

if __name__=="__main__":
    build()
