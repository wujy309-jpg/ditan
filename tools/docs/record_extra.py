import sys, time
sys.path.insert(0,'tools/docs')
import ui, record_demo as rd

def find_visible(t):
    a=ui.find_any([t])
    return a

# 年报
ui.tab('看板'); ui.m_to_top(); time.sleep(0.5)
for _ in range(8):
    a=find_visible('年 度 报 告')
    if a and 150 < ui.center(a)[1] < 700:
        break
    ui.m_drag(450,0.5)
a=find_visible('年 度 报 告')
print('year row', a['_rect'] if a else None)
x,y=ui.center(a)
p,path=rd.start('s8')
try:
    time.sleep(0.8)
    ui.tap(x,y,0)
    time.sleep(2.2)
    for i in range(3):
        ui.swipe(660,1700,660,800,500,0); time.sleep(1.7)
    time.sleep(1.0)
finally:
    rd.stop(p,path)

# 凭证
ui.tab('看板'); ui.m_to_top(); time.sleep(0.5)
for _ in range(14):
    a=find_visible('减 排 凭 证')
    if a and 150 < ui.center(a)[1] < 500:
        break
    ui.m_drag(450,0.45)
a=find_visible('减 排 凭 证')
print('voucher', a['_rect'] if a else None)
# 生成分享图按钮
b=find_visible('生成分享图')
print('share btn', b['_rect'] if b else None)
if b:
    x,y=ui.center(b)
    p,path=rd.start('s9')
    try:
        time.sleep(0.8)
        ui.tap(x,y,0)
        time.sleep(2.8)
    finally:
        rd.stop(p,path)
