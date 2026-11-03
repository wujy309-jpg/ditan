#!/usr/bin/env python3
"""在 v3 界面上追加演示记录（走应用自己的表单，不碰数据库）。

为什么不用 tools/seed-demo-data.py：那份脚本靠颜色找控件，v3 把填充式输入框
换成了下划线、把绿色按钮换成了墨色，颜色判据全部失效。这里改用 uitest dumpLayout
按文本/类型找控件，和视觉样式解耦。
"""
import sys, time
sys.path.insert(0, "tools/docs")
import ui

DEL = 2055

def hide_kb():
    ui.sh(f"{ui.HDC} shell uinput -K -d 2 -u 2")
    time.sleep(1.0)

def top():
    for _ in range(5):
        ui.swipe(660, 600, 660, 1750, 260, 0.25)

def bottom():
    for _ in range(5):
        ui.swipe(660, 1750, 660, 600, 260, 0.25)

def tap_when(text, contains=False, tries=6):
    for _ in range(tries):
        try:
            ui.tap_text(text, contains=contains, wait=0.8)
            return True
        except LookupError:
            ui.swipe(660, 1750, 660, 700, 300, 0.4)
    raise LookupError(text)

def add(cat, behavior, amount, date):
    ui.tab("记一笔", 1.0)
    top()
    for _ in range(4):
        try:
            ui.tap_text(cat, wait=0.8)
            break
        except LookupError:
            ui.swipe(660, 1850, 660, 1450, 300, 0.4)
    else:
        raise LookupError(cat)
    # 行为区在类目下面
    for _ in range(3):
        try:
            ui.tap_text(behavior, wait=0.8, last=True)
            break
        except LookupError:
            ui.swipe(660, 1700, 660, 800, 360, 0.5)
    else:
        raise LookupError(behavior)
    bottom()
    ins = [n["attributes"] for n in ui.nodes(ui.dump())
           if n.get("attributes", {}).get("type") == "TextInput"]
    if len(ins) < 2:
        raise RuntimeError(f"inputs={len(ins)}")
    ax, ay = ui.center(ins[0]); ui.tap(ax, ay, 0.8)
    for _ in range(8):
        ui.sh(f"{ui.HDC} shell uinput -K -d {DEL} -u {DEL}"); time.sleep(0.05)
    ui.sh(f'{ui.HDC} shell uinput -K -t "{amount}"'); time.sleep(0.6)
    hide_kb()
    # 日期
    ins = [n["attributes"] for n in ui.nodes(ui.dump())
           if n.get("attributes", {}).get("type") == "TextInput"]
    dx, dy = ui.center(ins[-1]); ui.tap(dx, dy, 0.8)
    for _ in range(12):
        ui.sh(f"{ui.HDC} shell uinput -K -d {DEL} -u {DEL}"); time.sleep(0.05)
    ui.sh(f'{ui.HDC} shell uinput -K -t "{date}"'); time.sleep(0.8)
    hide_kb()
    # 保存
    for _ in range(4):
        try:
            ui.tap_text("保 存", wait=2.0)
            return
        except LookupError:
            ui.swipe(660, 1700, 660, 700, 300, 0.5)
    raise LookupError("保存")

if __name__ == "__main__":
    rows = [
        ("出行", "公交出行", "14", "2026-10-26"),
        ("节水节电", "节约用电", "3", "2026-10-27"),
        ("旧物回收", "回收塑料（PET）", "2", "2026-10-28"),
        ("光盘行动", "光盘行动", "2", "2026-10-29"),
        ("出行", "步行", "6", "2026-10-30"),
    ]
    for r in rows:
        print("add", r)
        add(*r)
        time.sleep(1.0)
        print("  ok")
