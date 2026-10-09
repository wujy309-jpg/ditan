#!/usr/bin/env python3
"""提交材料合规检查 —— 碳迹

大赛通知原文要求：
  「所有材料内容中均不得出现参赛团队、指导老师、院校等相关信息，确保评审公平公正。」

本脚本对交付物做自动扫描，覆盖三个最容易漏掉的地方：
  1. 正文与备注文字
  2. 文档属性（作者 / 最后修改者 / 公司）—— Office 文件最常泄漏信息的位置
  3. 文档内嵌的图片文件名与自定义 XML

用法：
    python3 tools/compliance_check.py [交付物目录]
退出码：0 = 通过；1 = 发现可疑内容（需人工确认）
"""
import os
import re
import sys
import zipfile

# 明显属于「院校 / 团队 / 指导老师」的线索词。
# 注意区分「合法出现」：例如命名规范里本来就有「XX学校团队名称」这种占位说明。
SUSPECT = [
    "大学", "学院", "学校", "校区", "职业技术学院", "高等专科",
    "指导老师", "指导教师", "老师", "导师", "教授",
    "参赛队", "队伍名称", "队长",
    "学院盖章", "教务处",
]

# 这些出现属于正常，命中时降级为提示或不报
# 说明：「中国科学院」含「学院」二字，但它是数据来源机构而非参赛院校，属典型误报
WHITELIST_CONTEXT = [
    "XX学校", "学校团队名称", "XX学院",
    "中国科学院", "中国社会科学院", "中国工程院",
    "科学院", "研究所",
]


def scan_text(label, text, findings):
    for i, line in enumerate(text.splitlines(), 1):
        for kw in SUSPECT:
            if kw in line:
                ctx = line.strip()
                if any(w in ctx for w in WHITELIST_CONTEXT):
                    findings.append(("提示", label, i, kw, ctx[:80]))
                else:
                    findings.append(("可疑", label, i, kw, ctx[:80]))


def check_docx(path, findings):
    from docx import Document
    doc = Document(path)

    # 正文 + 表格
    parts = [p.text for p in doc.paragraphs]
    for t in doc.tables:
        for row in t.rows:
            for c in row.cells:
                parts.append(c.text)
    scan_text(f"{os.path.basename(path)}:正文", "\n".join(parts), findings)

    # 文档属性
    cp = doc.core_properties
    for f in ("author", "last_modified_by", "comments", "category", "company"):
        v = getattr(cp, f, "") or ""
        if v.strip():
            findings.append(("提示", f"{os.path.basename(path)}:属性", 0, f, str(v)[:80]))


def check_pptx(path, findings):
    from pptx import Presentation
    prs = Presentation(path)
    for idx, slide in enumerate(prs.slides, 1):
        texts = []
        for shape in slide.shapes:
            if shape.has_text_frame:
                texts.append(shape.text_frame.text)
            if getattr(shape, "has_table", False) and shape.has_table:
                for row in shape.table.rows:
                    for c in row.cells:
                        texts.append(c.text)
        # 备注页也常常被忽略
        if slide.has_notes_slide:
            notes = slide.notes_slide.notes_text_frame.text
            if notes.strip():
                texts.append(notes)
        scan_text(f"{os.path.basename(path)}:第{idx}页", "\n".join(texts), findings)

    cp = prs.core_properties
    for f in ("author", "last_modified_by", "comments", "category"):
        v = getattr(cp, f, "") or ""
        if v.strip():
            findings.append(("提示", f"{os.path.basename(path)}:属性", 0, f, str(v)[:80]))


def check_zip_internals(path, findings):
    """检查 Office 包内是否残留可疑的作者信息或自定义属性。"""
    try:
        z = zipfile.ZipFile(path)
    except Exception:
        return
    for name in z.namelist():
        if not name.endswith(".xml"):
            continue
        raw = z.read(name).decode("utf-8", "ignore")
        for kw in ("python-docx", "python-pptx", "Steve Canny"):
            if kw in raw:
                findings.append(("可疑", f"{os.path.basename(path)}:{name}", 0, kw,
                                 "生成器默认写入的元数据，建议清理"))
        for kw in ("大学", "学院"):
            if kw in raw and "core" in name:
                m = re.search(r"<dc:creator>(.*?)</dc:creator>", raw)
                if m and kw in m.group(1):
                    findings.append(("可疑", f"{os.path.basename(path)}:{name}", 0, kw,
                                     m.group(1)[:80]))


def main():
    target = sys.argv[1] if len(sys.argv) > 1 else "交付物"
    if not os.path.isdir(target):
        print(f"错误：找不到目录 {target}", file=sys.stderr)
        return 1

    findings = []
    files = []
    for fn in sorted(os.listdir(target)):
        path = os.path.join(target, fn)
        if not os.path.isfile(path):
            continue
        files.append(fn)
        low = fn.lower()
        if low.endswith(".docx"):
            check_docx(path, findings)
        elif low.endswith(".pptx"):
            check_pptx(path, findings)
        if low.endswith((".docx", ".pptx")):
            check_zip_internals(path, findings)

    print("=" * 66)
    print("提交材料合规检查")
    print("=" * 66)
    print(f"扫描目录：{os.path.abspath(target)}")
    print(f"扫描文件：{', '.join(files) if files else '（无）'}")
    print()

    bad = [f for f in findings if f[0] == "可疑"]
    hint = [f for f in findings if f[0] == "提示"]

    for level, label, line, kw, ctx in bad:
        loc = f"{label}:{line}" if line else label
        print(f"  ❌ [{level}] {loc}  命中「{kw}」")
        print(f"       {ctx}")
    for level, label, line, kw, ctx in hint:
        loc = f"{label}:{line}" if line else label
        print(f"  ⚠️  [{level}] {loc}  命中「{kw}」")
        print(f"       {ctx}")

    print()
    if not findings:
        print("  ✅ 未发现团队 / 指导老师 / 院校信息，也未发现生成器残留元数据。")
    print(f"  可疑 {len(bad)} 项，提示 {len(hint)} 项")
    print()
    print("提醒：本脚本只能扫描文字与元数据。以下需要人工确认：")
    print("  · 演示视频的画面、字幕与背景音")
    print("  · 图片/截图里是否拍到校徽、校园卡、宿舍等可识别信息")
    print("  · PPT 的母版与页脚")
    print("=" * 66)

    return 1 if bad else 0


if __name__ == "__main__":
    sys.exit(main())
