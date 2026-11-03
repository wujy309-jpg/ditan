#!/usr/bin/env python3
"""生成功能演示视频的旁白（晓晓，+3%），并输出每段时长。

依赖：edge-tts（pip install --target /tmp/ttsdeps edge-tts）
运行：PYTHONPATH=/tmp/ttsdeps python3 tools/docs/demo_voice.py
"""
import asyncio, json, os, subprocess
import edge_tts

VOICE = "zh-CN-XiaoxiaoNeural"
RATE = "+2%"
OUT = "/tmp/carbon-demo/audio"

SCENES = [
("d0", "碳迹，一款跑在鸿蒙上的个人碳账本。接下来四分钟，把它的功能完整走一遍。"),
("d1", "打开应用就是记一笔。四个类目，十四种常见行为。点出行，选步行，填六公里，减排量实时算出来：一点一七公斤，一百一十七积分。点保存，这笔账立刻进入最近记录；类目、数量、减排量，逐条列出来。每一条因子都标着基准情景和数据出处，随时可以核对。"),
("d2", "看板把账变成趋势。这棵树随累计减排长大，现在累计二十点五八公斤，树冠已经很密。十二周日历记录连续五天；折线带上了上期对比，柱状直接标数值，环形看四类占比。再往下是分类对比和今日任务，按短板优先，推荐今天还没记的类目。日、周、月、年，四种粒度随时切换。"),
("d3", "点进年度报告，一年收成一页：十一条记录、十一天、二十点五八公斤、两千零五十八积分。"),
("d4", "积分不是摆设。每一公斤换一百分，绑定城市碳普惠账户后，可以上报、兑换地铁券、单车券、公园门票。现在账户里有两千零五十八分，平台待上报也是两千零五十八，点一下就能上报。库存、余额、幂等，都按真实接口的语义做。"),
("d5", "八篇科普，按政策、概念、数据、技巧分类，点开就能读。"),
("d6", "我的页面：同步面板把本机标识、可信设备、上次同步时间、冲突数都摊开；端侧 AI 自检确认模型能加载；数据可以备份成 JSON，也可以导出 CSV。"),
("d7", "最后一键生成减排凭证：累计减排、记录条数、坚持天数、主力贡献，落款盖一枚朱印，保存到相册就能分享。"),
("d8", "三个鸿蒙特色能力：分布式同步让数据在设备之间直接走；端侧 AI 用双通路识图，图片不出设备，自检会打印模型输入输出形状和候选索引；碳普惠按真实接口的五个环节实现，换通信层就能接真实平台。"),
("d9", "数据全部留在本机，不上传云端，离线也能用。碳迹，把每一笔低碳，记成看得见的改变。"),
]

async def main():
    os.makedirs(OUT, exist_ok=True)
    rows = []
    for sid, text in SCENES:
        out = f"{OUT}/{sid}.mp3"
        await edge_tts.Communicate(text, VOICE, rate=RATE, volume="+0%", pitch="+0Hz").save(out)
        p = subprocess.run(["ffprobe", "-v", "error", "-show_entries", "format=duration",
                            "-of", "csv=p=0", out], capture_output=True, text=True)
        dur = float(p.stdout.strip() or 0)
        rows.append((sid, round(dur, 2), text))
        print(sid, round(dur, 2), flush=True)
    json.dump(rows, open(f"{OUT}/durations.json", "w"), ensure_ascii=False, indent=1)
    print("total speech", round(sum(r[1] for r in rows), 1))

if __name__ == "__main__":
    asyncio.run(main())
