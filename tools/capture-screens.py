#!/usr/bin/env python3
"""碳迹 —— 重拍演示截图（带"这一屏真的是本应用吗"的自检）。

为什么不用纯 bash + 固定坐标：
    实测踩过坑 —— 某一步点空之后，后续的点击会落到**电话应用**上，
    于是一整批截图全是拨号盘（而且因为内容相同，几张文案的字节数完全一样）。
    所以这里每次截图前都先确认应用在前台、并且真的切到了目标页签。

用法：python3 tools/capture-screens.py
"""

import os
import re
import subprocess
import sys
import time

from PIL import Image

WS = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(WS, "素材", "截图")
HDC = "/Applications/DevEco-Studio.app/Contents/sdk/default/openharmony/toolchains/hdc"
EMU = "/Applications/DevEco-Studio.app/Contents/tools/emulator/Emulator"
INSTANCE = "carbon"
LAYOUT = os.path.expanduser(f"~/.Huawei/Emulator/deployed/{INSTANCE}/uiLayout/analysis.md")
BUNDLE = "com.henan.carbonfootprint"

TABS = [("记一笔", 132), ("看板", 396), ("积分", 660), ("科普", 924), ("我的", 1188)]
TAB_Y = 2075


def sh(cmd: str) -> str:
    return subprocess.run(cmd, shell=True, capture_output=True, text=True).stdout


def dump() -> str:
    sh(f"{EMU} -instance {INSTANCE} -uiLayout")
    try:
        return open(LAYOUT, encoding="utf-8").read()
    except OSError:
        return ""


def app_foreground() -> bool:
    t = dump()
    return "记一笔" in t and "看板" in t and "积分" in t


def launch_from_home() -> None:
    """从桌面图标启动。
    为什么要绕这一步：用 `aa start` 直接拉起来时，状态栏会留着系统给的
    「◀ 上一个应用」悬浮指示（因为之前误开过电话应用），截图里很扎眼。
    先回桌面再点图标，这个指示就没了。
    """
    sh(f"{HDC} shell uinput -K -d 1 -u 1")   # KEYCODE_HOME
    time.sleep(3)
    sh(f"{HDC} shell uinput -T -c 505 330")  # 桌面上的「碳迹」图标
    time.sleep(6)


def ensure_app() -> bool:
    for _ in range(3):
        if app_foreground():
            return True
        sh(f"{HDC} shell aa start -a EntryAbility -b {BUNDLE}")
        time.sleep(6)
    return app_foreground()


def snap(name: str) -> Image.Image:
    sh(f"{HDC} shell snapshot_display -f /data/local/tmp/_c.jpeg")
    sh(f"{HDC} file recv /data/local/tmp/_c.jpeg /tmp/_c.jpeg")
    img = Image.open("/tmp/_c.jpeg").convert("RGB")
    img.save(os.path.join(OUT, f"{name}.jpeg"), quality=92)
    print(f"  ✓ {name}")
    return img


def tap(x: int, y: int, wait: float = 1.8) -> None:
    sh(f"{HDC} shell uinput -T -c {x} {y}")
    time.sleep(wait)


def down(n: int = 1) -> None:
    for _ in range(n):
        sh(f"{HDC} shell uinput -T -m 660 1700 660 500 450")
        time.sleep(0.55)


def up(n: int = 1) -> None:
    for _ in range(n):
        sh(f"{HDC} shell uinput -T -m 660 500 660 1750 450")
        time.sleep(0.55)


def goto_tab(name: str) -> bool:
    """切页签，并验证真的切过去了（页签文字会出现在 uiLayout 里且带选中态）。"""
    x = dict((n, x) for n, x in TABS)[name]
    for _ in range(3):
        tap(x, TAB_Y)
        if app_foreground():
            return True
        ensure_app()
    return False


def main() -> None:
    os.makedirs(OUT, exist_ok=True)
    launch_from_home()
    if not app_foreground():
        ensure_app()

    seen = {}

    def capture(name: str, retries: int = 3) -> None:
        """截图，并确保内容与上一张不同。

        ⚠️ 最初这里只打印一句警告就继续，结果留下了 3 组**完全相同**的截图
           （07=08、10=11=12、15=16）—— 因为 down() 的步长没能翻动页面。
           更糟的是文件内容与文件名对不上，做 PPT 的人只能按画面猜图注。
           现在改成"内容没变就再翻一屏重拍"，最多重试 retries 次。
        """
        for i in range(retries + 1):
            img = snap(name)
            h = hash(img.tobytes())
            if h not in seen:
                seen[h] = name
                return
            if i == retries:
                print(f"     ⚠️ 重试 {retries} 次后仍与「{seen[h]}」相同，"
                      f"可能已到页面底部")
                return
            down(1)
            time.sleep(0.8)

    print("重拍演示截图…")

    # ---- 记一笔 ----
    goto_tab("记一笔"); up(6); time.sleep(0.8)
    capture("01-记一笔-初始")
    down(3); time.sleep(0.6)
    capture("02-记一笔-最近记录")

    # ---- 看板 ----
    if goto_tab("看板"):
        up(6); time.sleep(0.8)
        # 切「月」粒度：演示数据横跨三周，周视图会是一条平线
        tap(536, 1017)
        capture("03-看板-总览")
        for i, name in enumerate(["04-看板-减排日历", "05-看板-折线趋势",
                                  "06-看板-柱状对比", "07-看板-饼图与图例",
                                  "08-看板-分享卡"]):
            down(1); time.sleep(0.6); capture(name)

    # ---- 积分 ----
    if goto_tab("积分"):
        up(6); time.sleep(0.8)
        capture("09-积分-碳普惠")
        for name in ["10-积分-权益与勋章", "11-积分-成就与流水", "12-积分-流水明细"]:
            down(2); time.sleep(0.6); capture(name)

    # ---- 科普 ----
    if goto_tab("科普"):
        up(6); time.sleep(0.8)
        capture("13-科普专栏")

    # ---- 我的 ----
    if goto_tab("我的"):
        up(6); time.sleep(0.8)
        capture("14-我的-档案")
        for name in ["15-我的-同步面板", "16-我的-AI自检与数据管理"]:
            down(2); time.sleep(0.6); capture(name)

    print(f"\n完成，输出目录：{OUT}")


if __name__ == "__main__":
    main()
