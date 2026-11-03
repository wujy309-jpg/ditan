import asyncio, json, os, subprocess
import edge_tts
VOICE="zh-CN-XiaoxiaoNeural"; RATE="+2%"; OUT="/tmp/carbon-real/audio"
S=[
("r0","下面直接录制应用的实际操作，从记一笔开始，依次走完看板、积分、科普和我的。"),
("r1","记一笔：四个类目、十四种行为，都在一页里选。点出行，选步行，填六公里。减排量实时算出来，一点一七公斤；点保存，这笔账立刻进入最近记录。每条因子都标着基准和数据出处。"),
("r2","看板：这棵树随累计减排长大；十二周日历记录连续天数；折线带上了上期对比。"),
("r3","再往下是分类占比、今日任务，以及一张减排凭证。"),
("r4","积分：当前余额、可兑换的地铁券和单车券，还有勋章与证书。"),
("r5","科普：八篇文章，按政策、概念、数据、技巧分类，点开就能读。"),
("r6","我的：同步面板、端侧 AI 自检，以及 JSON 备份和 CSV 导出。"),
("r8","年度报告把一年收成一页：记录条数、活跃天数、累计减排、主力贡献，还有全年积分。"),
("r7","全部数据留在本机，不上传云端，离线也能用。"),
]
async def main():
    os.makedirs(OUT,exist_ok=True); rows=[]
    for sid,text in S:
        p=f"{OUT}/{sid}.mp3"
        await edge_tts.Communicate(text,VOICE,rate=RATE,volume="+0%",pitch="+0Hz").save(p)
        d=float(subprocess.run(["ffprobe","-v","error","-show_entries","format=duration","-of","csv=p=0",p],capture_output=True,text=True).stdout.strip() or 0)
        rows.append((sid,round(d,2),text)); print(sid,round(d,2))
    json.dump(rows,open(f"{OUT}/durations.json","w"),ensure_ascii=False,indent=1)
    print("total",round(sum(r[1] for r in rows),1))
asyncio.run(main())
