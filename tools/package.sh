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
RAR_BIN="$WS_ROOT/tools/rar/rar/rar"

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

if [ ! -x "$RAR_BIN" ]; then
  echo "错误：找不到 rar 可执行文件（$RAR_BIN）" >&2
  exit 1
fi

# 1) 暂存：只放通知要求的三类材料
rm -rf "$STAGE"
mkdir -p "$STAGE"
missing=0
for f in "设计方案_碳迹.docx" "演示文稿_碳迹.pptx"; do
  if [ -f "$DELIV/$f" ]; then
    cp "$DELIV/$f" "$STAGE/"
  else
    echo "  ⚠️ 缺少：$f"
    missing=1
  fi
done
# 演示视频：mp4，≤100MB，≤5 分钟（由团队录制后放到 交付物/ 下）
shopt -s nullglob
videos=("$DELIV"/*.mp4)
shopt -u nullglob
if [ ${#videos[@]} -gt 0 ]; then
  for v in "${videos[@]}"; do
    size_mb=$(( $(stat -f%z "$v") / 1024 / 1024 ))
    if [ "$size_mb" -gt 100 ]; then
      echo "  ⚠️ 视频超过 100MB（${size_mb}MB）：$(basename "$v")"
      missing=1
    else
      cp "$v" "$STAGE/"
      echo "  已加入视频：$(basename "$v")（${size_mb}MB）"
    fi
  done
else
  echo "  ⚠️ 尚未放入演示视频（*.mp4）"
  missing=1
fi

echo
echo "=== 暂存内容 ==="
ls -la "$STAGE"

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
