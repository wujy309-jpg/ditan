#!/usr/bin/env python3
"""用已验证的截图生成演示视频。

为什么用截图合成而不是直接录屏：
  模拟器 CLI 没有录屏能力，只能逐帧截图；而且应用交互（改日期等）
  靠命令行的坐标点击不够稳定。这里改用**已经逐页验证过的截图**合成视频，
  画面内容与真机实测一致，只是转场为定帧切换。

输出规格（对齐大赛要求）：mp4 / H.264 / ≤100MB / ≤5 分钟

截图版本（2026-09-30 前端视觉美化后重拍）：
  · 取图目录仍是 素材/截图/，但文件名与旧版不同，旧图已备份到
    素材/截图/旧版-改造前/；本脚本不再引用任何旧文件名。
  · 帧序列里新增两段：**减排日历热力图**与**「我的年度碳迹」年度报告**，
    末尾补上「改造前后对比」与「图标集」两张整备素材。
  · 热力图与图例两帧用构建期裁剪（见 crop()），不修改素材文件本身。

用法：
    python3 tools/docs/make_video.py          # 只生成帧
    python3 tools/docs/make_video.py --encode # 生成帧并调用 ffmpeg 合成
"""
import os
import subprocess
import sys

from PIL import Image, ImageDraw, ImageFont

W, H = 1080, 1920
BAR_H = 108
BG = (245, 247, 250)
GREEN = (31, 154, 78)
GREEN_DARK = (20, 107, 54)
GREEN_DEEP = (11, 74, 45)          # 新版看板英雄区的深墨绿，用于标题帧渐变
WHITE = (255, 255, 255)
GREY = (140, 152, 166)

FONT_PATH = "/System/Library/Fonts/STHeiti Medium.ttc"
SHOT_DIR = "素材/截图"
ASSET_DIR = "素材"
FIG_DIR = "/tmp/carbon-video-figs"     # 构建期裁剪出的派生图
CROP_BASE = (1320, 2232)               # 手机截图基准分辨率，换分辨率时按比例缩放裁剪框
FRAME_DIR = "/tmp/carbon-video-frames"
DUR = 7.0          # 每帧停留秒数


def crop(path, box):
    """按基准分辨率给出裁剪框，返回裁剪后的图片路径（缓存到 /tmp）。

    box=(left, top, right, bottom)，单位是 1320×2232 下的像素。
    """
    if not box:
        return path
    os.makedirs(FIG_DIR, exist_ok=True)
    im = Image.open(path)
    sx, sy = im.width / CROP_BASE[0], im.height / CROP_BASE[1]
    px = (int(box[0] * sx), int(box[1] * sy), int(box[2] * sx), int(box[3] * sy))
    name = os.path.splitext(os.path.basename(path))[0]
    out = os.path.join(FIG_DIR, f"{name}-{px[0]}_{px[1]}_{px[2]}_{px[3]}.png")
    if not os.path.exists(out):
        im.crop(px).save(out)
    return out


# (截图文件 或 None, 主标题, 副标题[, 裁剪框])
FRAMES = [
    (None, "碳迹", "碳足迹 · 全民绿色生活碳积分与减排指南"),

    # ---- 主要功能 1：低碳行为核算 ----
    (f"{SHOT_DIR}/01-记一笔-初始.jpeg",
     "主要功能 1 · 低碳行为核算",
     "渐变英雄区 + 今日目标环 + 端侧 AI 识图 + 四个类目卡"),
    (f"{SHOT_DIR}/02-记一笔-最近记录.jpeg",
     "录入表单与最近记录",
     "本周减排 0.98 kg、今日 5 条记录；保存后自动折算并发放积分"),

    # ---- 主要功能 2：数据可视化看板 ----
    (f"{SHOT_DIR}/03-看板-总览.jpeg",
     "主要功能 2 · 数据可视化看板",
     "深墨绿英雄区 + 「我的年度碳迹」入口 + 统计粒度 + 减排日历"),
    (f"{SHOT_DIR}/03-看板-总览.jpeg",
     "新增 · 减排日历热力图",
     "最近 12 周 × 7 天，四档色阶 + 连续记录天数",
     (40, 1395, 1280, 1972)),
    (f"{SHOT_DIR}/04-看板-减排日历.jpeg",
     "四档色阶图例",
     "少 → 多，每格 = 一天；没有记录的日子为浅灰",
     (40, 150, 1280, 525)),
    (f"{SHOT_DIR}/04-看板-减排日历.jpeg",
     "减排趋势 · 新增「上期」对比线",
     "实线为本期，灰色虚线为上期，折线带渐变面积填充"),
    (f"{SHOT_DIR}/05-看板-折线趋势.jpeg",
     "分类减排对比与分类占比",
     "柱顶直接标注数值；环形图中心显示累计总量 14.62 kg"),
    (f"{SHOT_DIR}/05-看板-折线趋势.jpeg",
     "原生图例：色点 + 百分比 + 进度条",
     "占比一眼可读，不再依赖悬浮提示",
     (40, 1060, 1280, 1560)),

    # ---- 创新拓展 4：智能服务与分享 ----
    (f"{SHOT_DIR}/06-看板-柱状对比.jpeg",
     "创新拓展 4 · 智能服务",
     "今日低碳任务按「短板优先」推荐，建议全部由数据事实驱动"),
    (f"{SHOT_DIR}/07-看板-饼图与图例.jpeg",
     "减排成果分享",
     "低碳成绩单：累计减排、等效植树、记录天数，可导出为图片"),

    # ---- 新增页面：我的年度碳迹 ----
    (f"{SHOT_DIR}/17-年度报告-封面.jpeg",
     "新增页面 · 我的年度碳迹",
     "2026 年度报告：低碳称号、活跃天数与核心数字一屏读完"),
    (f"{SHOT_DIR}/18-年度报告-细节.jpeg",
     "年度报告 · 碳积分与减排构成",
     "四色条形与看板环形图一一对应，口径完全一致"),

    # ---- 鸿蒙特色：桌面服务卡片（桌面截图本次未改动，沿用） ----
    (f"{SHOT_DIR}/10-桌面卡片-选择.png",
     "鸿蒙特色 · 桌面服务卡片",
     "不用打开应用，桌面上就能看到今日减排量与碳积分"),

    # ---- 主要功能 3 + 创新拓展 3：积分与碳普惠 ----
    (f"{SHOT_DIR}/09-积分-碳普惠.jpeg",
     "主要功能 3 + 创新拓展 3",
     "碳积分 1,462 分 · 权益解锁 100% · 城市碳普惠平台 · 成就勋章墙"),
    (f"{SHOT_DIR}/10-积分-权益与勋章.jpeg",
     "权益兑换与积分流水",
     "植树证书 300 分、碳中和达人证书 800 分；流水逐条可追溯"),

    # ---- 主要功能 4、5 + 创新拓展 1、2 ----
    (f"{SHOT_DIR}/13-科普专栏.jpeg",
     "主要功能 4 · 双碳科普专栏",
     "8 篇图文科普，按政策 / 概念 / 数据 / 技巧分类"),
    (f"{SHOT_DIR}/14-我的-档案.jpeg",
     "主要功能 5 + 创新拓展 1 · 我的",
     "低碳称号英雄区、我的档案与超级终端同步面板"),
    (f"{SHOT_DIR}/15-我的-同步面板.jpeg",
     "同步状态 · 端侧 AI 自检 · 数据管理",
     "同步结果与冲突计数如实呈现；备份 JSON、导出 CSV"),
    (f"{SHOT_DIR}/12-AI自检-推理通过.png",
     "创新拓展 2 · 端侧 AI 推理链路实测通过",
     "模型 11.4MB 加载成功，输入 [1,224,224,3]、输出 [1,500]"),

    # ---- 视觉改造（本次交付物更新的重点） ----
    (f"{ASSET_DIR}/改造前后对比-前端美化.png",
     "视觉改造 · 改造前 vs 改造后",
     "统一英雄区 · 卡片默认投影 · 列表图标化 · 弹簧动效 · 数据可视化"),
    (f"{ASSET_DIR}/图标集-预览.png",
     "图标体系",
     "24 个自绘图标：重绘 5 个页签图标，新绘地铁 / 单车 / 礼券"),

    (None, "把每一次低碳行为", "算清楚 · 记下来 · 换成看得见的回馈"),
]


def font(size):
    return ImageFont.truetype(FONT_PATH, size)


def text_center(draw, xy, text, f, fill):
    box = draw.textbbox((0, 0), text, font=f)
    draw.text((xy[0] - (box[2] - box[0]) / 2, xy[1]), text, font=f, fill=fill)


def make_title_frame(title, sub):
    """标题帧：新版看板的「深墨绿」气质，用竖向渐变代替纯色块。"""
    img = Image.new("RGB", (W, H), GREEN)
    d = ImageDraw.Draw(img)
    for y in range(H):
        t = y / H
        d.line([(0, y), (W, y)], fill=(
            int(GREEN_DEEP[0] + (GREEN[0] - GREEN_DEEP[0]) * t),
            int(GREEN_DEEP[1] + (GREEN[1] - GREEN_DEEP[1]) * t),
            int(GREEN_DEEP[2] + (GREEN[2] - GREEN_DEEP[2]) * t)))
    text_center(d, (W / 2, H / 2 - 160), title, font(84), WHITE)
    text_center(d, (W / 2, H / 2 - 20), sub, font(34), (215, 232, 220))
    return img


def make_shot_frame(path, title, sub):
    img = Image.new("RGB", (W, H), BG)
    d = ImageDraw.Draw(img)
    # 顶部标题条
    d.rectangle([0, 0, W, BAR_H], fill=GREEN)
    text_center(d, (W / 2, 16), title, font(38), WHITE)
    text_center(d, (W / 2, 64), sub, font(22), (215, 232, 220))

    # 截图按剩余高度等比缩放并居中；不放大，避免整备素材被拉糊
    avail_h = H - BAR_H
    shot = Image.open(path).convert("RGB")
    ratio = min(W / shot.width, avail_h / shot.height, 1.0)
    nw, nh = int(shot.width * ratio), int(shot.height * ratio)
    shot = shot.resize((nw, nh), Image.LANCZOS) if ratio < 1.0 else shot
    img.paste(shot, ((W - nw) // 2, BAR_H + (avail_h - nh) // 2))
    return img


def build_frames():
    os.makedirs(FRAME_DIR, exist_ok=True)
    for f in os.listdir(FRAME_DIR):
        os.remove(os.path.join(FRAME_DIR, f))

    paths = []
    for i, item in enumerate(FRAMES):
        shot, title, sub = item[0], item[1], item[2]
        box = item[3] if len(item) > 3 else None
        if shot is None:
            img = make_title_frame(title, sub)
        else:
            if not os.path.exists(shot):
                print(f"  ⚠️ 缺少截图，跳过：{shot}")
                continue
            img = make_shot_frame(crop(shot, box), title, sub)
        p = os.path.join(FRAME_DIR, f"frame-{i:02d}.png")
        img.save(p)
        paths.append(p)
        print(f"  帧 {i:02d}: {title}")
    return paths


def encode(paths):
    lst = os.path.join(FRAME_DIR, "list.txt")
    with open(lst, "w") as f:
        for p in paths:
            f.write(f"file '{p}'\n")
            f.write(f"duration {DUR}\n")
        f.write(f"file '{paths[-1]}'\n")   # concat 需要最后一帧重复

    out = "交付物/演示视频_碳迹.mp4"
    cmd = [
        "ffmpeg", "-y", "-hide_banner", "-loglevel", "error",
        "-f", "concat", "-safe", "0", "-i", lst,
        "-vf", "fps=30,format=yuv420p",
        "-c:v", "libx264", "-preset", "medium", "-crf", "22",
        "-movflags", "+faststart",
        out,
    ]
    subprocess.run(cmd, check=True)
    size_mb = os.path.getsize(out) / 1024 / 1024
    print(f"\n已生成：{os.path.abspath(out)}")
    print(f"大小：{size_mb:.1f} MB（要求 ≤100MB）")
    # 读时长
    r = subprocess.run(["ffprobe", "-v", "error", "-show_entries",
                        "format=duration", "-of",
                        "default=noprint_wrappers=1:nokey=1", out],
                       capture_output=True, text=True)
    dur = float(r.stdout.strip()) if r.stdout.strip() else 0
    print(f"时长：{dur:.1f} 秒（要求 ≤300 秒）")
    return size_mb, dur


def main():
    print("=== 生成视频帧 ===")
    paths = build_frames()
    print(f"共 {len(paths)} 帧，每帧 {DUR} 秒 → 约 {len(paths) * DUR:.0f} 秒")
    if "--encode" in sys.argv:
        print("\n=== ffmpeg 合成 ===")
        size_mb, dur = encode(paths)
        if size_mb > 100:
            print("  ❌ 超过 100MB")
        if dur > 300:
            print("  ❌ 超过 300 秒")
    else:
        print("\n（未合成；加 --encode 调用 ffmpeg）")


if __name__ == "__main__":
    main()
