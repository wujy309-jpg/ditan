#!/usr/bin/env python3
"""按对齐 JSON 生成 srt/ass（画面与字幕共用同一份时间码）。

用法：python3 tools/docs/subtitles_from_alignment.py [对齐.json]
"""
import json
import os
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
sys.path.insert(0, os.path.join(ROOT, "tools", "docs"))
import make_subtitles as ms  # noqa: E402

src = sys.argv[1] if len(sys.argv) > 1 else os.path.join(ROOT, "参考资料/旁白对齐.json")
d = json.load(open(src, encoding="utf-8"))
f = ms.font()
cues = d["cues"]
wrapped = [ms.wrap(c["text"], f) for c in cues]

srt = []
for n, (c, ls) in enumerate(zip(cues, wrapped), 1):
    srt.append("%d\n%s --> %s\n%s\n" % (n, ms.srt_ts(c["start"]), ms.srt_ts(c["end"]), "\n".join(ls)))
open(os.path.join(ROOT, "交付物/字幕_碳迹.srt"), "w", encoding="utf-8").write("\n".join(srt))

body = ["Dialogue: 0,%s,%s,Ledger,,0,0,0,,%s" % (ms.ass_ts(c["start"]), ms.ass_ts(c["end"]), "\\N".join(ls))
        for c, ls in zip(cues, wrapped)]
open(os.path.join(ROOT, "交付物/字幕_碳迹.ass"), "w", encoding="utf-8").write(ms.ASS_HEAD + "\n".join(body) + "\n")
print("cues=%d last=%.2fs" % (len(cues), cues[-1]["end"]))
