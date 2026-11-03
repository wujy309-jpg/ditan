import sys, time
sys.path.insert(0,'tools/docs')
import ui, record_demo as rd

def seg(name, before, action):
    before()
    time.sleep(1.0)
    p, path = rd.start(name)
    try:
        action()
    finally:
        rd.stop(p, path)

def s2_before():
    ui.tab('看板'); ui.m_to_top(); time.sleep(1)
def s2_action():
    time.sleep(1.2)
    for i in range(6):
        ui.swipe(660,1700,660,800,500,0)
        time.sleep(1.6)
    time.sleep(1.5)

def s3_before():
    ui.tab('积分'); ui.m_to_top(); time.sleep(1)
def s3_action():
    time.sleep(1.2)
    ui.tap(660,1405,0)          # 上报
    time.sleep(2.6)
    for i in range(3):
        ui.swipe(660,1700,660,800,500,0); time.sleep(1.4)
    time.sleep(1.2)

def s4_before():
    ui.tab('科普'); ui.m_to_top(); time.sleep(1)
def s4_action():
    time.sleep(1.2)
    ui.tap(660,1470,0)          # 展开第一篇
    time.sleep(2.2)
    ui.swipe(660,1700,660,900,500,0); time.sleep(1.4)
    time.sleep(1.0)

def s5_before():
    ui.tab('我的'); ui.m_to_top(); time.sleep(1)
def s5_action():
    time.sleep(1.2)
    for i in range(3):
        ui.swipe(660,1700,660,800,500,0); time.sleep(1.2)
    ui.tap(660,1260,0)          # 运行 AI 自检
    time.sleep(4.0)
    time.sleep(1.0)

def s6_before():
    ui.tab('看板'); ui.m_to_top()
    for i in range(3): ui.swipe(660,1700,660,800,450,0.8)
    time.sleep(1)
def s6_action():
    time.sleep(1.0)
    ui.tap(660,1620,0)          # 年度报告
    time.sleep(2.2)
    for i in range(3):
        ui.swipe(660,1700,660,800,500,0); time.sleep(1.5)
    time.sleep(1.0)

if __name__ == '__main__':
    which = sys.argv[1:] or ['s2','s3','s4','s5','s6']
    fns = {'s2':(s2_before,s2_action),'s3':(s3_before,s3_action),'s4':(s4_before,s4_action),
           's5':(s5_before,s5_action),'s6':(s6_before,s6_action)}
    for k in which:
        b,a = fns[k]
        print('REC',k,flush=True)
        seg(k,b,a)
