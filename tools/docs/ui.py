"""极简 HarmonyOS 模拟器 UI 驱动：dumpLayout 找文本 → uinput 点击 → snapshot 截图。"""
import json, os, re, subprocess, time
from PIL import Image

HDC = "/Applications/DevEco-Studio.app/Contents/sdk/default/openharmony/toolchains/hdc"
BUNDLE = "com.henan.carbonfootprint"
TMP = "/tmp/carbon-ui"

def sh(cmd, timeout=30):
    return subprocess.run(cmd, shell=True, capture_output=True, text=True, timeout=timeout).stdout

def dump():
    os.makedirs(TMP, exist_ok=True)
    sh(f"{HDC} shell 'uitest dumpLayout -p /data/local/tmp/_l.json'")
    sh(f"{HDC} file recv /data/local/tmp/_l.json {TMP}/layout.json")
    return json.load(open(f"{TMP}/layout.json", encoding="utf-8"))

def nodes(n, out=None):
    out = [] if out is None else out
    a = n.get("attributes", {})
    r = re.findall(r"-?\d+", a.get("bounds", ""))
    if len(r) == 4:
        a["_rect"] = tuple(map(int, r))
    out.append(n)
    for c in n.get("children", []):
        nodes(c, out)
    return out

def visible(a):
    r = a.get("_rect")
    if not r:
        return False
    x1, y1, x2, y2 = r
    return y2 > 130 and y1 < 2210 and x2 > 0 and x1 < 1320

def find(text, root=None, contains=False, last=False, only_visible=True):
    root = dump() if root is None else root
    hits = []
    for n in nodes(root):
        a = n.get("attributes", {})
        t = (a.get("text") or "").strip()
        if ((text in t) if contains else (t == text)) and (visible(a) or not only_visible):
            hits.append(a)
    if not hits:
        raise LookupError(f"not found: {text!r}")
    return hits[-1] if last else hits[0]

def center(a):
    x1, y1, x2, y2 = a["_rect"]
    return (x1 + x2) // 2, (y1 + y2) // 2

def tap_text(text, contains=False, wait=1.0, last=False):
    a = find(text, contains=contains, last=last)
    x, y = center(a)
    tap(x, y, wait)
    return x, y

def tap(x, y, wait=0.8):
    sh(f"{HDC} shell uinput -T -c {x} {y}")
    time.sleep(wait)

def swipe(x1, y1, x2, y2, ms=420, wait=0.6):
    sh(f"{HDC} shell uinput -T -m {x1} {y1} {x2} {y2} {ms}")
    time.sleep(wait)

def shot(path):
    os.makedirs(os.path.dirname(path) or ".", exist_ok=True)
    sh(f"{HDC} shell snapshot_display -f /data/local/tmp/_s.jpeg")
    sh(f"{HDC} file recv /data/local/tmp/_s.jpeg {path}")
    return Image.open(path)

def start_app(wait=6):
    sh(f"{HDC} shell aa start -a EntryAbility -b {BUNDLE}")
    time.sleep(wait)

def tab(name, wait=1.0):
    tap_text(name, wait=wait)

def find_any(texts, contains=False):
    """返回第一个可见的命中文本节点。"""
    root = dump()
    for n in nodes(root):
        a = n.get("attributes", {})
        t = (a.get("text") or "").strip()
        if not visible(a):
            continue
        for s in texts:
            if (s in t) if contains else (t == s):
                return a
    return None

def align(text, target_y=150, tries=4, contains=False):
    """滚动到让 text 出现在 target_y 附近。"""
    for _ in range(tries):
        a = find_any([text] if isinstance(text, str) else text, contains=contains)
        if a is None:
            return False
        x, y = center(a)
        dy = y - target_y
        if abs(dy) <= 40:
            return True
        y0 = 1500 if dy > 0 else 700
        ui_swipe = globals()["swipe"]
        ui_swipe(660, y0, 660, y0 - dy, 380, 0.6)
    return True

def scroll_to(text, step=700, max_swipes=10, target_y=150):
    """向下滚动直到 text 出现，再对齐到 target_y。"""
    for _ in range(max_swipes):
        a = find_any([text] if isinstance(text, str) else text)
        if a is not None:
            return align(text, target_y)
        swipe(660, 1700, 660, 1700 - step, 380, 0.7)
    return False

def scroll_to_precise(text, target_y=150, max_steps=25, tol=25):
    """小步慢滑，把 text 精确对齐到 target_y，避免 fling 惯性。"""
    for _ in range(max_steps):
        a = find_any([text] if isinstance(text, str) else text)
        if a is None:
            swipe(660, 1500, 660, 1200, 900, 0.55)
            continue
        y = center(a)[1]
        dy = y - target_y
        if abs(dy) <= tol:
            return True
        step = max(-320, min(320, dy))
        swipe(660, 1200, 660, 1200 - step, 900, 0.55)
    return False

def m_drag(dy, wait=0.45):
    """在屏幕右边缘拖动，避开卡片/图表对手势的拦截。dy>0 = 内容上移（向下翻）。"""
    dy = max(-500, min(500, dy))
    y0 = 1400 if dy > 0 else 800
    sh(f"{HDC} shell uitest uiInput drag 1305 {y0} 1305 {y0 - dy} 500")
    time.sleep(wait)

def m_align(text, target_y=150, max_steps=20, tol=20):
    for _ in range(max_steps):
        a = find_any([text] if isinstance(text, str) else text)
        if a is None:
            m_drag(400)
            continue
        y = center(a)[1]
        dy = y - target_y
        if abs(dy) <= tol:
            return True
        m_drag(max(-450, min(450, dy)))
    return False

def m_to_top(max_drags=12):
    for _ in range(max_drags):
        if find_any(['碳 迹 · 减 排 账']):
            return True
        m_drag(-500)
    return bool(find_any(['碳 迹 · 减 排 账']))
