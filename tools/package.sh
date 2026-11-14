#!/usr/bin/env bash
# ---------------------------------------------------------------------------
#  碳迹 —— 提交物打包
#
#  大赛对打包的硬性要求（通知原文）：
#    · 统一压缩打包为 **rar** 格式
#    · 命名格式：赛题序号+赛题名称+XX学校团队名称
#      示例：赛题二+碳足迹·全民绿色生活碳积分与减排指南+XX学校XX队.rar
#    · ⚠️ 通知附件 1 里的命名示例是**错的**（写成别的赛题名），按真实赛题名称写
#
#  用法：
#    tools/package.sh "XX学校XX队"          # 指定团队名称
#    tools/package.sh                        # 未指定时用占位名，并在末尾提示
#
#  说明：rar 二进制放在 tools/rar/（从 rarlab 官方下载，未安装到系统）。
# ---------------------------------------------------------------------------
set -euo pipefail

WS_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DELIV="$WS_ROOT/交付物"
# rar 可执行文件：仓库里可能没有（rar 不开源，需自行下载），所以按顺序找
#   1. $RAR_BIN 显式指定
#   2. 仓库内 tools/rar/ 下（官方 unrar/rarlab 解包后的常见位置）
#   3. PATH 上的 rar
#   4. Windows 常见安装位置
find_rar() {
  local c
  for c in \
    "${RAR_BIN_OVERRIDE:-}" \
    "$WS_ROOT/tools/rar/rar/rar" \
    "$WS_ROOT/tools/rar/rar.exe" \
    "$WS_ROOT/tools/rar/rar/rar.exe"; do
    [ -n "$c" ] && [ -x "$c" ] && { printf '%s\n' "$c"; return 0; }
  done
  if command -v rar >/dev/null 2>&1; then
    command -v rar
    return 0
  fi
  for c in "/c/Program Files/WinRAR/Rar.exe" "/c/Program Files/WinRAR/rar.exe" \
           "C:/Program Files/WinRAR/Rar.exe"; do
    [ -f "$c" ] && { printf '%s\n' "$c"; return 0; }
  done
  return 1
}
RAR_BIN="$(find_rar || true)"

SAI_TI_NAME="碳足迹·全民绿色生活碳积分与减排指南"
TEAM="${1:-}"
if [ -z "$TEAM" ]; then
  TEAM="XX学校XX队"
  PLACEHOLDER=1
else
  PLACEHOLDER=0
fi
BASE_NAME="赛题二+${SAI_TI_NAME}+${TEAM}"
STAGE="$WS_ROOT/交付物/_打包暂存"
OUT="$WS_ROOT/交付物/${BASE_NAME}.rar"

if [ -z "$RAR_BIN" ] && [ "${PACKAGE_DRY_RUN:-0}" = "1" ]; then
  echo "  ℹ️ 未找到 rar（试运行不打包，只验证白名单与命名）"
elif [ -z "$RAR_BIN" ]; then
  echo "错误：找不到 rar 可执行文件。大赛要求 .rar 格式，需要先准备：" >&2
  echo "  1) 下载 rarlab 的命令行版 rar（Windows 用 rarwin-x64，macOS 用 rarmacos-*）" >&2
  echo "  2) 解包后把 rar 放到 tools/rar/rar/rar（或安装到 PATH）" >&2
  echo "  3) 或用 RAR_BIN_OVERRIDE=<路径> 直接指定" >&2
  exit 1
fi
if [ -n "$RAR_BIN" ]; then
  echo "rar：$RAR_BIN"
fi

# 1) 暂存：**按文件名白名单**只放通知要求的三类材料
#
#    原来这里用 videos=("$DELIV"/*.mp4) 通配，会把「演示文稿_讲解视频.mp4」一起
#    打进提交包。通知只收「设计方案 / 演示文稿 / 演示视频」三类，多一个 17 MB
#    的附加文件既不符合要求，也可能让评审以为材料重复。
rm -rf "$STAGE"
mkdir -p "$STAGE"
missing=0

# 跨平台取文件字节数：GNU stat / BSD stat / wc 三种依次尝试
file_bytes() {
  stat -c%s "$1" 2>/dev/null || stat -f%z "$1" 2>/dev/null || wc -c < "$1"
}

REQUIRED_FILES=("设计方案_碳迹.docx" "演示文稿_碳迹.pptx" "演示视频_碳迹.mp4")
for f in "${REQUIRED_FILES[@]}"; do
  if [ ! -f "$DELIV/$f" ]; then
    echo "  ⚠️ 缺少：$f"
    missing=1
    continue
  fi
  if [ "$f" = "演示视频_碳迹.mp4" ]; then
    bytes="$(file_bytes "$DELIV/$f")"
    size_mb=$(( bytes / 1024 / 1024 ))
    if [ "$size_mb" -gt 100 ]; then
      echo "  ⚠️ 视频超过 100MB（${size_mb}MB）：$f"
      missing=1
      continue
    fi
    echo "  已加入视频：${f}（${size_mb}MB）"
  fi
  cp "$DELIV/$f" "$STAGE/"
done

# 显式提示被排除的文件，避免「以为打进去了」
shopt -s nullglob
for extra in "$DELIV"/*.mp4 "$DELIV"/*.m4a "$DELIV"/*.png "$DELIV"/*.md; do
  base="$(basename "$extra")"
  skip=0
  for f in "${REQUIRED_FILES[@]}"; do
    [ "$base" = "$f" ] && skip=1
  done
  if [ "$skip" = "0" ]; then
    echo "  · 未打包（不属于通知要求的三类，仅留作自用）：$base"
  fi
done
shopt -u nullglob

echo
echo "=== 暂存内容（必须恰好 3 个文件）==="
ls -la "$STAGE"
count=$(find "$STAGE" -maxdepth 1 -type f | wc -l | tr -d ' ')
if [ "$count" != "3" ]; then
  echo "  ⚠️ 暂存里有 ${count} 个文件，通知要求三类材料各一份" >&2
  missing=1
fi

if [ "${PACKAGE_DRY_RUN:-0}" = "1" ]; then
  echo
  echo "=== PACKAGE_DRY_RUN=1：只校验暂存内容，不生成 rar ==="
  if [ "$missing" = "1" ]; then
    rm -rf "$STAGE"
    exit 1
  fi
  rm -rf "$STAGE"
  exit 0
fi

# 2) 打 rar
rm -f "$OUT"
( cd "$STAGE" && "$RAR_BIN" a -r -ep1 "$OUT" . >/dev/null )
echo
echo "=== 打包完成 ==="
ls -la "$OUT"

# 3) 核对命名与合规
echo
echo "=== 命名核对 ==="
echo "  文件名：$(basename "$OUT")"
echo "  规范要求：赛题序号+赛题名称+XX学校团队名称"
echo "  真实赛题名称：赛题二  ${SAI_TI_NAME}"

echo
echo "=== 合规检查（材料中不得出现团队/指导老师/院校信息）==="
echo "  请在提交前逐份打开检查，特别是："
echo "    · Word 文档的属性（作者、单位）—— 建议用「另存为」后清除文档属性"
echo "    · PPT 的备注页与文档属性"
echo "    · 视频画面与字幕"

if [ "$PLACEHOLDER" = "1" ]; then
  echo
  echo "  ⚠️ 当前用的是占位团队名「XX学校XX队」，正式提交前请重新执行："
  echo "       tools/package.sh \"你的学校+队名\""
fi

rm -rf "$STAGE"
