#!/usr/bin/env python3
"""录制 v3.4 功能演示的分段画面（模拟器真实操作 + 宿主端 AVFoundation 抓屏）。

为什么分段录：整段 2 分 20 秒一次过，任何一步点歪就得整条重来；
分段之后每段单独重录，最后按 `参考资料/旁白对齐.json` 的锚点伸缩到旁白窗口即可。

用法：
    python3 tools/docs/record_v34.py s2      # 只录某一段
    python3 tools/docs/record_v34.py         # 按顺序录全部
片段落在 /tmp/rec34/<name>.mp4（774×1309，30fps）。
"""
import os
import signal
import subprocess
import sys
import time

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "docs"))
sys.path.insert(0, "tools/docs")
import ui  # noqa: E402

OUT = "/tmp/rec34"
CROP = "crop=774:1309:135:115"
FPS = 30


def log(msg):
    print(msg, flush=True)


def focus_emulator():
    """录屏前把别的窗口藏起来：WeChat 抢过活动空间、DSH 会自己升到最前，都会污染画面。"""
    subprocess.run(["osascript", "-e", 'tell application "System Events"',
                    "-e", 'set visible of process "DeepSeek Harness" to false',
                    "-e", 'try', "-e", 'set visible of process "WeChat" to false', "-e", "end try",
                    "-e", 'tell process "Emulator" to set frontmost to true', "-e", "end tell"],
                   capture_output=True)


def restore_windows():
    subprocess.run(["osascript", "-e", 'tell application "System Events"',
                    "-e", 'set visible of process "DeepSeek Harness" to true',
                    "-e", 'try', "-e", 'set visible of process "WeChat" to true', "-e", "end try"],
                   capture_output=True)


def start(name):
    os.makedirs(OUT, exist_ok=True)
    focus_emulator()
    time.sleep(1.0)
    path = f"{OUT}/{name}.mp4"
    cmd = ["ffmpeg", "-y", "-hide_banner", "-loglevel", "error",
           "-f", "avfoundation", "-framerate", str(FPS), "-capture_cursor", "0", "-i", "2",
           "-vf", CROP, "-c:v", "libx264", "-preset", "ultrafast", "-crf", "16",
           "-pix_fmt", "yuv420p", path]
    p = subprocess.Popen(cmd, stderr=subprocess.DEVNULL)
    time.sleep(1.0)
    return p, path


def stop(p, path):
    p.send_signal(signal.SIGINT)
    try:
        p.wait(timeout=15)
    except subprocess.TimeoutExpired:
        p.kill()
    log("saved %s %.1fMB" % (path, os.path.getsize(path) / 1e6))


def hold(sec):
    time.sleep(sec)


def tap_text(text, wait=0.8, contains=False):
    ui.tap_text(text, wait=wait, contains=contains)


def scroll_to(text, max_drag=6, dy=500, align_y=None):
    """滚到某段文字可见（找不到就一路往下拖）。"""
    for _ in range(max_drag):
        a = ui.find_any([text])
        if a:
            if align_y is not None:
                y = ui.center(a)[1]
                d = y - align_y
                if abs(d) > 40:
                    ui.m_drag(max(-450, min(450, d)))
                    time.sleep(0.4)
            return a
        ui.m_drag(dy)
        time.sleep(0.5)
    return None


def tap_after(text, wait=0.8, contains=False, max_drag=6, dy=500):
    a = scroll_to(text, max_drag=max_drag, dy=dy)
    if a is None:
        raise LookupError(text)
    x, y = ui.center(a)
    ui.tap(x, y, wait)


# ---------------------------------------------------------------- 分段动作
def tap(text, wait=0.7, contains=False, tries=3, drag=320):
    """点一个可见控件；找不到就先往下滚一点再试——比一次 find 崩掉实用。"""
    for i in range(tries):
        try:
            ui.tap_text(text, wait=wait, contains=contains)
            return
        except LookupError:
            if i == tries - 1:
                raise
            ui.m_drag(drag); time.sleep(0.4)


def need(text, max_drag=5, dy=460, align_y=None):
    """滚到文字出现；align_y 给了就把它拖到该高度附近。"""
    for _ in range(max_drag):
        a = ui.find_any([text])
        if a:
            if align_y is not None:
                d = ui.center(a)[1] - align_y
                if abs(d) > 45:
                    ui.m_drag(max(-450, min(450, d)))
                    time.sleep(0.45)
            return a
        ui.m_drag(dy)
        time.sleep(0.45)
    raise LookupError(text)


def inputs():
    return [n["attributes"] for n in ui.nodes(ui.dump())
            if n.get("attributes", {}).get("type") == "TextInput"]


def s2_entry():
    """记一笔：类目 → 行为 → 数量 6 → 保存 → 最近记录。"""
    ui.m_to_top(); time.sleep(0.5)
    need("选 择 类 目"); tap("出行", 0.9); time.sleep(0.5)
    need("选 择 行 为"); ui.m_drag(260); time.sleep(0.3); tap("步行", 0.9); time.sleep(0.7)
    need("数 量 与 日 期")
    ins = inputs()
    x, y = ui.center(ins[0]); ui.tap(x, y, 0.7)
    ui.tap(930, 1670, 0.35)     # 键盘 6
    time.sleep(2.2)             # 1.17 kg 停一拍
    ui.tap(1180, 1985, 0.6)     # 完成
    need("保 存"); tap("保 存", 1.5)
    time.sleep(1.0)
    ui.m_drag(420); time.sleep(2.0)     # 最近记录


def s3_records():
    """记录页：全部 → 出行 → 删掉重复的一条 → 返回。"""
    a = ui.find_any(["全部 ›"]) or ui.find_any(["全部"], contains=False)
    if a is None:
        ui.m_drag(380); time.sleep(0.5)
        a = ui.find_any(["全部 ›"]) or ui.find_any(["全部"])
    x, y = ui.center(a); ui.tap(x, y, 2.0)
    time.sleep(1.4)
    tap("出行", 1.3); time.sleep(1.4)
    rows = [n["attributes"] for n in ui.nodes(ui.dump())
            if (n["attributes"].get("text") or "").strip() == "删"]
    rows.sort(key=lambda a: a["_rect"][1])
    log("删 buttons: %d" % len(rows))
    if len(rows) >= 2:
        x, y = ui.center(rows[1]); ui.tap(x, y, 1.4)
    time.sleep(1.0)
    ui.sh("hdc shell uitest uiInput keyEvent Back"); time.sleep(0.8)


def s4_dashboard():
    """看板：树 → 日历 → 统计粒度 日/月/年 → 三图。"""
    tap("看板", 1.4); time.sleep(1.8)
    need("减排日历", align_y=430); time.sleep(1.6)
    need("统 计 粒 度", align_y=330); time.sleep(0.6)
    tap("月", 1.2); time.sleep(1.2)
    tap("年", 1.2); time.sleep(0.8)
    ui.m_drag(600); time.sleep(2.4)


def s5_legend():
    """看板下半：任务/建议/凭证 → 点分类占比「出行」进记录页。"""
    need("分 类 占 比", align_y=380, max_drag=7); time.sleep(1.6)
    try:
        tap("出行", 2.4)
    except LookupError:
        log("legend 出行 not found")
    time.sleep(1.2)


def s6_points():
    """积分：余额 → 徽章与证书 → 已获得。"""
    ui.sh("hdc shell uitest uiInput keyEvent Back"); time.sleep(0.6)
    tap("积分", 1.4); time.sleep(2.0)
    need("徽 章 与 证 书", align_y=400, max_drag=8); time.sleep(0.8)
    tap("已 获 得", 1.4); time.sleep(3.0)


def s7_knowledge():
    """科普：一页八行 → 展开第一行。"""
    tap("科普", 1.3); time.sleep(1.2)
    tap("什么是碳达峰与碳中和", 1.2, contains=True); time.sleep(2.0)


def s8_profile():
    """我的：同步面板 → AI 自检 → 数据管理。"""
    tap("我的", 1.3); time.sleep(1.2)
    need("同 步 面 板", align_y=400, max_drag=5); time.sleep(1.4)
    need("端 侧 AI 自 检", align_y=400, max_drag=4); time.sleep(1.2)
    need("本 地 数 据 管 理", align_y=400, max_drag=4); time.sleep(1.4)


def s9_year():
    """年报：看板 → 年度报告 → 全年数字。"""
    tap("看板", 1.3)
    ui.m_to_top(); time.sleep(0.5)
    need("年 度 报 告", max_drag=2); tap("年 度 报 告", 1.8); time.sleep(1.4)
    ui.m_drag(600); time.sleep(1.8)


SEG = {"s2": s2_entry, "s3": s3_records, "s4": s4_dashboard, "s5": s5_legend,
       "s6": s6_points, "s7": s7_knowledge, "s8": s8_profile, "s9": s9_year}


def run(name):
    fn = SEG[name]
    p, path = start(name)
    try:
        fn()
        hold(0.8)
    finally:
        stop(p, path)


if __name__ == "__main__":
    names = sys.argv[1:] or list(SEG)
    for n in names:
        log("=== %s ===" % n)
        run(n)
