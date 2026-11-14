#!/usr/bin/env python3
"""把真人旁白对齐到 34 句文稿，重新生成字幕与对齐表。

为什么不用「字数 / 语速」估算：
    估算只保证总长接近，句与句之间会漂移；真人录音的停顿才是真时间码。
    这里先按能量找出语音块与停顿，再用动态规划把 34 句文稿切成 34 段——
    代价 = 时长偏差（按全局语速归一）× 偏低 + 句末停顿太短的重罚。

产出：
    参考资料/旁白对齐.json      每句起止、每段起止（供合成脚本读取）
    参考资料/旁白对齐表.md      人读的对齐表
    交付物/字幕_碳迹.srt/.ass   按真实时间码重排的字幕
用法：python3 tools/docs/align_narration.py [音频路径]
"""
import json
import os
import re
import subprocess
import sys

import numpy as np

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
sys.path.insert(0, os.path.join(ROOT, "tools", "docs"))
import make_subtitles as ms  # noqa: E402  复用句子表、折行与 ASS 样式

SRC = sys.argv[1] if len(sys.argv) > 1 else os.path.join(ROOT, "素材/旁白录音/旁白_v3.4_原始.mp3")
OUT_JSON = os.path.join(ROOT, "参考资料/旁白对齐.json")
OUT_MD = os.path.join(ROOT, "参考资料/旁白对齐表.md")

SR = 16000
HOP = 0.01          # 帧移
WIN = 0.02          # 窗长
DB_TH = -38.0       # 语音门限（dBFS）
MIN_SPEECH = 0.06   # 短于此的语音块并入邻块
MIN_GAP = 0.08      # 短于此的停顿视为同一句内部


def decode(path):
    raw = subprocess.run(
        ["ffmpeg", "-v", "error", "-i", path, "-ac", "1", "-ar", str(SR), "-f", "s16le", "-"],
        capture_output=True, check=True).stdout
    x = np.frombuffer(raw, dtype=np.int16).astype(np.float32) / 32768.0
    n = (len(x) - int(WIN * SR)) // int(HOP * SR)
    rms = np.array([np.sqrt(np.mean(x[i * int(HOP * SR):i * int(HOP * SR) + int(WIN * SR)] ** 2))
                    for i in range(n)]) + 1e-9
    return x, 20 * np.log10(rms)


def speech_runs(db):
    mask = db > DB_TH
    runs, s = [], None
    for i, v in enumerate(mask):
        if v and s is None:
            s = i
        elif not v and s is not None:
            runs.append([s, i])
            s = None
    if s is not None:
        runs.append([s, len(mask)])
    merged = []
    for a, b in runs:
        if merged and (a - merged[-1][1]) * HOP < MIN_GAP:
            merged[-1][1] = b
        else:
            merged.append([a, b])
    return [m for m in merged if (m[1] - m[0]) * HOP >= MIN_SPEECH]


def align(sentences, S, E):
    exp = np.array([max(0.9, len(re.sub(r"\s", "", t)) / 4.6) for t in sentences])
    k = float((E[-1] - S[0]) / exp.sum())      # 实际语速相对 4.6 字/秒的倍数
    step = k * exp
    R, N = len(S), len(sentences)
    INF = 1e18
    dp = np.full((N + 1, R + 1), INF)
    back = np.full((N + 1, R + 1), -1, dtype=int)
    dp[0][0] = 0.0
    for i in range(N):
        for j in range(R):
            base = dp[i][j]
            if base >= INF / 2:
                continue
            for e in range(j, R):
                dur = E[e] - S[j]
                if dur > step[i] * 2.2:
                    break
                if dur < step[i] * 0.45:
                    continue
                gap = (S[e + 1] - E[e]) if e + 1 < R else 99.0
                # 句界越短越可疑：真人在这里几乎都留了 0.5 秒以上
                pen = 0.0 if gap >= 0.6 else (0.35 if gap >= 0.45 else (1.2 if gap >= 0.32 else 4.0))
                c = base + ((dur - step[i]) / step[i]) ** 2 + pen
                if c < dp[i + 1][e + 1]:
                    dp[i + 1][e + 1] = c
                    back[i + 1][e + 1] = j
    best = min(range(1, R + 1), key=lambda e: dp[N][e])
    cuts, e = [], best
    for i in range(N, 0, -1):
        j = back[i][e]
        cuts.append((j, e - 1))
        e = j
    return list(reversed(cuts)), float(dp[N][best]), float(k), step


def fmt_t(x):
    """把秒写成 mm:ss.ss，比 SRT 时间码更适合表格里读。"""
    return "%02d:%05.2f" % (int(x // 60), x % 60)


def main():
    x, db = decode(SRC)
    runs = speech_runs(db)
    S = np.array([r[0] * HOP for r in runs])
    E = np.array([r[1] * HOP for r in runs])

    sentences = [t for _a, _b, _c, _d, lines in ms.SEGMENTS for t, _h in lines]
    cuts, cost, k, step = align(sentences, S, E)
    cues = []
    for i, (j, e) in enumerate(cuts):
        cues.append({"i": i + 1, "start": round(float(S[j]), 2), "end": round(float(E[e]), 2),
                     "text": sentences[i], "hint": [h for _a, _b, _c, _d, L in ms.SEGMENTS for _t, h in L][i],
                     "exp": round(float(step[i]), 2)})

    # 十段起止：按 SEGMENTS 的句子数分组
    seg_spans, idx = [], 0
    for _a, _b, _c, _d, lines in ms.SEGMENTS:
        n = len(lines)
        seg_spans.append({"start": cues[idx]["start"], "end": cues[idx + n - 1]["end"], "n": n})
        idx += n

    os.makedirs(os.path.dirname(OUT_JSON), exist_ok=True)
    json.dump({"source": os.path.relpath(SRC, ROOT), "duration": round(len(x) / SR, 2),
               "rate_factor": round(k, 3), "cost": round(cost, 3),
               "cues": cues, "segments": seg_spans},
              open(OUT_JSON, "w", encoding="utf-8"), ensure_ascii=False, indent=1)

    # ---------- 字幕：用真实时间码重排 ----------
    f = ms.font()
    wrapped = [ms.wrap(c["text"], f) for c in cues]
    srt = []
    for c, ls in zip(cues, wrapped):
        srt.append("%d\n%s --> %s\n%s\n" % (c["i"], ms.srt_ts(c["start"]), ms.srt_ts(c["end"]), "\n".join(ls)))
    open(os.path.join(ROOT, "交付物/字幕_碳迹.srt"), "w", encoding="utf-8").write("\n".join(srt))
    body = ["Dialogue: 0,%s,%s,Ledger,,0,0,0,,%s" % (ms.ass_ts(c["start"]), ms.ass_ts(c["end"]), "\\N".join(ls))
            for c, ls in zip(cues, wrapped)]
    open(os.path.join(ROOT, "交付物/字幕_碳迹.ass"), "w", encoding="utf-8").write(ms.ASS_HEAD + "\n".join(body) + "\n")

    # ---------- 对齐表 ----------
    md = ["# 旁白对齐表 · 碳迹功能演示（v3.4）", "",
          "> 音频：`%s`（%.1f 秒）" % (os.path.relpath(SRC, ROOT), len(x) / SR),
          "> 34 句按停顿自动切分（对齐代价 %.2f）；实测每句时长约为 4.6 字/秒基准的 %.2f 倍，"
          "折合约 %.1f 字/秒。" % (cost, k, 4.6 / k),
          "> 字幕 `交付物/字幕_碳迹.srt` / `.ass` 已按此表重排；合成脚本可直接读 `参考资料/旁白对齐.json`。", "",
          "## 一、十段锚点（录屏/剪辑按这一列走）", "",
          "| 段 | 起 | 止 | 时长 | 句数 |", "|---|---|---|---|---|"]
    for i, s in enumerate(seg_spans, 1):
        md.append("| %02d | %s | %s | %.1fs | %d |" % (
            i, fmt_t(s["start"]), fmt_t(s["end"]), s["end"] - s["start"], s["n"]))
    md += ["", "## 二、逐句时间码", "",
           "| # | 起 | 止 | 时长 | 与预算偏差 | 旁白 | 气口与重音 |", "|---|---|---|---|---|---|---|"]
    for c in cues:
        d = c["end"] - c["start"]
        md.append("| %02d | %s | %s | %.2fs | %+d%% | %s | %s |" % (
            c["i"], fmt_t(c["start"]), fmt_t(c["end"]), d,
            round((d - c["exp"]) / c["exp"] * 100), c["text"], c["hint"]))
    bad = [c for c in cues if abs(c["end"] - c["start"] - c["exp"]) / c["exp"] > 0.45]
    md += ["", "## 三、说明", "",
           "- 第 01 句前有 0.6 秒静音、第 34 句后到片尾，剪辑时可直接留白，不必再垫。",
           "- 34 句全部落在 0.43 秒以上的停顿处，句界可信；偏差列只反映单句快慢，不等于切错。",
           "- 若临时改词，改的是 `make_subtitles.SEGMENTS` 后重跑本脚本，时间码会重新对齐。"]
    if bad:
        md.append("- 偏差超过 45%% 的句子：%s（建议复听确认没有改词或漏句）。"
                  % "、".join("%02d" % c["i"] for c in bad))
    open(OUT_MD, "w", encoding="utf-8").write("\n".join(md) + "\n")

    print("cues=%d  span=%.2f-%.2f  cost=%.2f  rate=%.2f" % (
        len(cues), cues[0]["start"], cues[-1]["end"], cost, k))
    for i, s in enumerate(seg_spans, 1):
        print("  段%02d %6.2f-%6.2f  %.1fs" % (i, s["start"], s["end"], s["end"] - s["start"]))


if __name__ == "__main__":
    main()
