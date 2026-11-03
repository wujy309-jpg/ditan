#!/usr/bin/env python3
"""把 pptx 近似渲染成图片，用于没有 PowerPoint 自动化时的版式自检。
只支持本项目用到的元素：图片、矩形、文本框。"""
import io, os, sys
from PIL import Image, ImageDraw, ImageFont
from pptx import Presentation
from pptx.util import Emu

SERIF = "/System/Library/Fonts/Supplemental/Songti.ttc"
DPI = int(os.environ.get("PPT_DPI", "120"))
OUT = os.environ.get("PPT_OUT", "/tmp/ppt-preview")

def font(px, bold):
    return ImageFont.truetype(SERIF, max(8, int(px)), index=0 if bold else 1)

def px(v):
    return int(round(Emu(v).inches * DPI))

def render(path):
    prs = Presentation(path)
    W, H = px(prs.slide_width), px(prs.slide_height)
    os.makedirs(OUT, exist_ok=True)
    for si, slide in enumerate(prs.slides, 1):
        im = Image.new("RGB", (W, H), (242, 237, 225))
        d = ImageDraw.Draw(im)
        for sh in slide.shapes:
            x, y, w, h = px(sh.left), px(sh.top), px(sh.width), px(sh.height)
            if sh.shape_type == 13:  # picture
                try:
                    pic = Image.open(io.BytesIO(sh.image.blob)).convert("RGBA")
                    pic = pic.resize((max(1, w), max(1, h)), Image.LANCZOS)
                    im.paste(pic, (x, y), pic)
                except Exception as e:
                    print("pic err", e)
            elif sh.has_text_frame:
                cy = y
                for p in sh.text_frame.paragraphs:
                    # 组装 runs
                    runs = []
                    for r in p.runs:
                        size = r.font.size.pt if r.font.size else 16
                        bold = bool(r.font.bold)
                        color = tuple(r.font.color.rgb) if r.font.color and r.font.color.type is not None else (32, 29, 23)
                        runs.append((r.text, size, bold, color))
                    if not runs:
                        continue
                    maxsz = max(r[1] for r in runs)
                    # 行高
                    ls = p.line_spacing if isinstance(p.line_spacing, float) else 1.2
                    line_h = maxsz * DPI / 72 * ls
                    # 逐字符换行
                    lines, cur, curw = [], [], 0
                    space_w = None
                    for text, size, bold, color in runs:
                        f = font(size * DPI / 72, bold)
                        for ch in text:
                            if ch == "\n":
                                lines.append(cur); cur, curw = [], 0
                                continue
                            cw = d.textlength(ch, font=f)
                            if curw + cw > w and cur:
                                lines.append(cur); cur, curw = [], 0
                            cur.append((ch, f, color, size)); curw += cw
                    if cur:
                        lines.append(cur)
                    for line in lines:
                        lw = sum(d.textlength(ch, font=f) for ch, f, c, s in line)
                        lx = x
                        if p.alignment == 2:  # center
                            lx = x + (w - lw) / 2
                        elif p.alignment == 3:  # right
                            lx = x + w - lw
                        for ch, f, color, s in line:
                            d.text((lx, cy), ch, font=f, fill=color)
                            lx += d.textlength(ch, font=f)
                        cy += line_h
                    cy += (p.space_after.pt if p.space_after else 0) * DPI / 72
            elif sh.shape_type == 1:  # autoshape
                try:
                    fill = sh.fill
                    if fill.type is not None and fill.fore_color and fill.fore_color.type is not None:
                        col = tuple(fill.fore_color.rgb)
                        d.rectangle([x, y, x + w, y + h], fill=col)
                except Exception:
                    pass
        im.save(f"{OUT}/slide-{si:02d}.png")
    print("rendered", si, "slides to", OUT)

if __name__ == "__main__":
    render(sys.argv[1] if len(sys.argv) > 1 else "交付物/演示文稿_碳迹.pptx")
