#!/usr/bin/env python3
"""真实录屏：启动 ffmpeg 抓取模拟器窗口，执行操作，停止。"""
import os, signal, subprocess, sys, time
sys.path.insert(0, "tools/docs")
import ui

CROP = "crop=760:1285:822:78"
OUT = "/tmp/record"

def start(name):
    path = f"{OUT}/{name}.mp4"
    cmd = ["ffmpeg","-y","-hide_banner","-loglevel","error","-f","avfoundation",
           "-framerate","30","-capture_cursor","0","-i","2","-vf",CROP,
           "-c:v","libx264","-preset","ultrafast","-crf","18","-pix_fmt","yuv420p",path]
    p = subprocess.Popen(cmd, stderr=subprocess.DEVNULL)
    time.sleep(0.8)
    return p, path

def stop(p, path):
    p.send_signal(signal.SIGINT)
    p.wait()
    print("saved", path, os.path.getsize(path), flush=True)

def reset_app():
    ui.sh(f"{ui.HDC} shell aa force-stop com.henan.carbonfootprint")
    time.sleep(1)
    ui.sh(f"{ui.HDC} shell aa start -a EntryAbility -b com.henan.carbonfootprint")
    time.sleep(5)

if __name__ == "__main__":
    reset_app()
    p, path = start("seg1")
    try:
        import seed_fast
        seed_fast.add("出行", "步行", "6", "2026-10-30")
        time.sleep(2.2)
    finally:
        stop(p, path)
