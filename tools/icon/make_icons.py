"""生成「碳迹」应用图标（HarmonyOS 分层图标：background + foreground + startIcon）。

设计：绿色渐变底 + 白色叶片 + 深绿叶脉。

关于叶片形状的一点记录（踩过的坑）：
  最初用两段相交圆弧（vesica piscis）生成叶片，看起来数学上很优雅，
  但当圆心偏移 A / 半径 R = 0.45 时，叶尖的内角是 2·atan(T/A) ≈ 127° —— 是**钝的**，
  渲染出来叶尖像被平切了一刀。扫掠多边形的顶点投影只能确认「尖点位置对不对」，
  确认不了「尖角够不够尖」，所以一开始被误导了。
  现在改用两条三次贝塞尔曲线，叶尖角度由控制点**显式决定**（见 TIP_ANGLE_DEG）。

用法（在工程根目录执行）：
    python3 <此脚本>
"""
import math
import os
from PIL import Image, ImageDraw, ImageFilter

S = 1024
GREEN_TOP = (34, 168, 88)
GREEN_BOT = (18, 116, 62)
WHITE = (255, 255, 255, 255)
VEIN = (26, 138, 74, 255)
TRANSPARENT = (0, 0, 0, 0)

# PIL 的多边形填充没有抗锯齿，边缘会显锯齿。
# 在 SS 倍尺寸上绘制再 LANCZOS 缩小，等价于 SS×SS 超采样。
SS = 4

# --- 叶片几何（叶空间：长轴为 y，叶尖 (0, +1)，叶基 (0, -1)）--------------
TIP_ANGLE_DEG = 46.0     # 叶尖总夹角：越小越尖
_HALF_TAN = math.tan(math.radians(TIP_ANGLE_DEG / 2.0))

# 叶尖控制点：距叶尖长度 CTRL_LEN，方向与长轴成 TIP_ANGLE/2
_CTRL_LEN = 0.60
_C2X = _CTRL_LEN * _HALF_TAN          # ≈ 0.254
_C2Y = 1.0 - _CTRL_LEN                # = 0.40
# 叶身最宽处的控制点（决定叶片胖瘦）
_C1X = 0.62
_C1Y = -0.55

# 叶片最大半宽（由贝塞尔曲线在 t=0.5 处取到），供叶脉定位使用
_W_MAX = 0.75 * _C1X + 0.75 * _C2X    # = 3/8·C1X + 3/8·C2X 的两倍修正见下
_W_MAX = (3 * 0.25 * 0.5) * _C1X + (3 * 0.5 * 0.25) * _C2X


def _bezier(p0, p1, p2, p3, n):
    """三次贝塞尔采样。"""
    out = []
    for i in range(n + 1):
        t = i / n
        mt = 1.0 - t
        a = mt * mt * mt
        b = 3 * mt * mt * t
        c = 3 * mt * t * t
        d = t * t * t
        out.append((
            a * p0[0] + b * p1[0] + c * p2[0] + d * p3[0],
            a * p0[1] + b * p1[1] + c * p2[1] + d * p3[1],
        ))
    return out


def leaf_unit_outline(n: int = 140):
    """叶空间下的叶片轮廓（长轴长度 2，最宽处约 ±0.345）。"""
    base = (0.0, -1.0)
    tip = (0.0, 1.0)
    right = _bezier(base, (_C1X, _C1Y), (_C2X, _C2Y), tip, n)
    left = _bezier(tip, (-_C2X, _C2Y), (-_C1X, _C1Y), base, n)
    return right + left[1:-1]


def leaf_polygon(cx: float, cy: float, half_len: float, rot_deg: float):
    """把叶空间轮廓变换到屏幕坐标。half_len 为叶尖到中心的像素距离。"""
    rad = math.radians(rot_deg)
    cos_r, sin_r = math.cos(rad), math.sin(rad)
    out = []
    for (x, y) in leaf_unit_outline():
        xr = x * cos_r - y * sin_r
        yr = x * sin_r + y * cos_r
        out.append((cx + xr * half_len, cy - yr * half_len))   # 屏幕 y 轴向下
    return out


def axis_vectors(rot_deg: float):
    """屏幕坐标下的（叶基->叶尖）单位向量与其左法向量。"""
    rad = math.radians(rot_deg)
    ax, ay = -math.sin(rad), -math.cos(rad)
    nx, ny = -ay, ax
    return ax, ay, nx, ny


def make_background(size: int = S) -> Image.Image:
    """绿色竖向渐变，叠一层柔和的左上高光。"""
    img = Image.new("RGBA", (size, size), TRANSPARENT)
    d = ImageDraw.Draw(img)
    for y in range(size):
        t = y / (size - 1)
        r = int(GREEN_TOP[0] + (GREEN_BOT[0] - GREEN_TOP[0]) * t)
        g = int(GREEN_TOP[1] + (GREEN_BOT[1] - GREEN_TOP[1]) * t)
        b = int(GREEN_TOP[2] + (GREEN_BOT[2] - GREEN_TOP[2]) * t)
        d.line([(0, y), (size, y)], fill=(r, g, b, 255))

    glow = Image.new("L", (size, size), 0)
    ImageDraw.Draw(glow).ellipse(
        [-size * 0.35, -size * 0.45, size * 0.75, size * 0.65], fill=64
    )
    glow = glow.filter(ImageFilter.GaussianBlur(size * 0.20))
    highlight = Image.new("RGBA", (size, size), (255, 255, 255, 0))
    highlight.putalpha(glow)
    return Image.alpha_composite(img, highlight)


def make_foreground(out_size: int = S) -> Image.Image:
    """白色叶片 + 被裁切在叶内的深绿叶脉。内容控制在中间安全区。"""
    R = out_size * SS
    half_len = R * 0.27
    cx = cy = R * 0.5
    rot = -40.0
    poly = leaf_polygon(cx, cy, half_len, rot)

    # 1) 叶片本体
    leaf = Image.new("RGBA", (R, R), TRANSPARENT)
    ImageDraw.Draw(leaf).polygon(poly, fill=WHITE)

    # 2) 叶脉（独立图层，稍后按叶片轮廓裁切）
    ax, ay, nx, ny = axis_vectors(rot)
    veins = Image.new("RGBA", (R, R), TRANSPARENT)
    vd = ImageDraw.Draw(veins)

    # 主脉：沿长轴，两端各留 10% 不顶到叶尖
    L = 2 * half_len * 0.90
    x0, y0 = cx - ax * L / 2, cy - ay * L / 2
    x1, y1 = cx + ax * L / 2, cy + ay * L / 2
    vd.line([(x0, y0), (x1, y1)], fill=VEIN, width=int(R * 0.009))

    # 侧脉：斜向叶尖伸出（真实叶脉是斜的）
    for frac in (0.28, 0.50):
        bx, by = x0 + ax * L * frac, y0 + ay * L * frac
        taper = math.sin(math.pi * (0.12 + frac * 0.8)) * 0.72 + 0.14
        half_w = _W_MAX * half_len * taper
        for sgn in (1.0, -1.0):
            dxv = sgn * nx + ax * 0.65
            dyv = sgn * ny + ay * 0.65
            norm = math.hypot(dxv, dyv)
            ex = bx + dxv / norm * half_w
            ey = by + dyv / norm * half_w
            vd.line([(bx, by), (ex, ey)], fill=VEIN, width=int(R * 0.0065))

    # 3) 裁切叶脉，确保没有一根线伸出叶外
    mask = Image.new("L", (R, R), 0)
    ImageDraw.Draw(mask).polygon(poly, fill=255)
    clipped = Image.composite(veins, Image.new("RGBA", (R, R), TRANSPARENT), mask)

    merged = Image.alpha_composite(leaf, clipped)
    if out_size != R:
        merged = merged.resize((out_size, out_size), Image.LANCZOS)
    return merged


def main() -> None:
    here = os.path.dirname(os.path.abspath(__file__))
    bg = make_background()
    fg = make_foreground()

    bg.save("AppScope/resources/base/media/background.png")
    fg.save("AppScope/resources/base/media/foreground.png")
    bg.save("entry/src/main/resources/base/media/background.png")
    fg.save("entry/src/main/resources/base/media/foreground.png")

    # 启动图标：背景 + 叶片，144×144
    start = Image.alpha_composite(make_background(144), make_foreground(144))
    start.save("entry/src/main/resources/base/media/startIcon.png")

    # 预览（不参与打包，供人工检查）；同时输出小尺寸确认可辨识度
    preview = Image.alpha_composite(make_background(), make_foreground())
    preview.save(os.path.join(here, "icon-preview.png"))
    preview.resize((144, 144), Image.LANCZOS).save(os.path.join(here, "icon-144.png"))
    print("图标已生成：background.png / foreground.png / startIcon.png")
    print(f"叶尖夹角 = {TIP_ANGLE_DEG}°，叶片最大半宽/半长 = {_W_MAX:.3f}")


if __name__ == "__main__":
    main()
