import sys, time
sys.path.insert(0, "tools/docs")
import ui

def safesh(cmd, t=15):
    try:
        return ui.sh(cmd, timeout=t)
    except Exception:
        return ""

def back():
    safesh(f'{ui.HDC} shell uitest uiInput keyEvent Back'); time.sleep(1.0)

def tap(text, last=False):
    for _ in range(4):
        try:
            ui.tap_text(text, wait=0.8, last=last); return True
        except LookupError:
            ui.m_drag(350, 0.5)
    raise LookupError(text)

def add(cat, behavior, amount, date, log=print):
    ui.tab("记一笔", 1.0)
    ui.m_to_top()
    log("  form top")
    tap(cat)
    log("  cat")
    # 行为区在下面；滚动到可见
    for _ in range(4):
        try:
            ui.tap_text(behavior, wait=0.8, last=True); break
        except LookupError:
            ui.m_drag(600, 0.6)
    log("  behavior")
    # 到数量/日期
    for _ in range(5):
        ins = [n["attributes"] for n in ui.nodes(ui.dump())
               if n.get("attributes", {}).get("type") == "TextInput"]
        if len(ins) >= 2:
            break
        ui.m_drag(600, 0.6)
    if len(ins) < 2:
        raise RuntimeError("no inputs")
    x, y = ui.center(ins[0]); ui.tap(x, y, 0.7)
    safesh(f'{ui.HDC} shell uitest uiInput text "{amount}"'); time.sleep(0.5)
    back()
    ins = [n["attributes"] for n in ui.nodes(ui.dump())
           if n.get("attributes", {}).get("type") == "TextInput"]
    x, y = ui.center(ins[-1]); ui.tap(x, y, 0.7)
    for _ in range(10):
        safesh(f'{ui.HDC} shell uitest uiInput keyEvent 2055'); time.sleep(0.05)
    time.sleep(0.4)
    safesh(f'{ui.HDC} shell uitest uiInput text "{date}"'); time.sleep(0.8)
    back()
    log("  amount/date")
    tap("保 存")
    time.sleep(1.5)
    log("  saved")
