import sys, time
sys.path.insert(0,'tools/docs')
import ui, record_demo as rd

ui.tab('看板'); ui.m_to_top(); time.sleep(1)
p, path = rd.start('s7')
try:
    time.sleep(1.0)
    for i in range(3):
        ui.swipe(660,1700,660,800,600,0.6)
    ui.tap_text('年 度 报 告', wait=2.2)
    for i in range(3):
        ui.swipe(660,1700,660,800,600,0.6)
        time.sleep(1.8)
    time.sleep(1.0)
finally:
    rd.stop(p, path)
