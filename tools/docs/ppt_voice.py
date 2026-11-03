import asyncio, json, os, re, subprocess
import edge_tts
from pptx import Presentation
VOICE="zh-CN-XiaoxiaoNeural"; RATE="+2%"; OUT="/tmp/ppt-video/audio"
prs=Presentation("交付物/演示文稿_碳迹.pptx")
texts=[]
for i,s in enumerate(prs.slides,1):
    t=s.notes_slide.notes_text_frame.text.strip()
    t=re.sub(r'^(开场\s*)?\d+\s*秒[：:]\s*','',t)
    t=t.replace('\n',' ')
    texts.append((f"p{i:02d}",t))
async def main():
    os.makedirs(OUT,exist_ok=True); rows=[]
    for sid,t in texts:
        p=f"{OUT}/{sid}.mp3"
        await edge_tts.Communicate(t,VOICE,rate=RATE,volume="+0%",pitch="+0Hz").save(p)
        d=float(subprocess.run(["ffprobe","-v","error","-show_entries","format=duration","-of","csv=p=0",p],capture_output=True,text=True).stdout.strip() or 0)
        rows.append((sid,round(d,2),t)); print(sid,round(d,2),t[:30])
    json.dump(rows,open(f"{OUT}/durations.json","w"),ensure_ascii=False,indent=1)
    print("total",round(sum(r[1] for r in rows),1))
asyncio.run(main())
