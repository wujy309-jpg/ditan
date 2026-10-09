#!/usr/bin/env bash
# ---------------------------------------------------------------------------
#  碳迹 —— 一键「同步 + 编译验证」
#
#  为什么不在工作区里直接构建：
#    工作区路径含中文，hvigor 会硬性拒绝构建（实测报错见
#    开工方案_环境实测与启动顺序.md）。所以源码正本留在工作区，
#    构建在纯英文路径 ~/DevEcoStudioProjects/carbon-footprint 里进行。
#
#  依赖说明：
#    工程依赖 @ohos/mpchart（图表库）。ohpm 装好的 oh_modules 保留在
#    目标工程目录里，本脚本不会删除它，因此装一次即可离线反复构建。
#
#  用法：
#    tools/build.sh              # 同步 + 构建未签名 HAP
#    tools/build.sh clean        # 同步 + 清理
#    可选环境变量：
#      CARBON_PROJECT_DIR   目标工程目录（默认 ~/DevEcoStudioProjects/carbon-footprint）
# ---------------------------------------------------------------------------
set -euo pipefail

WS_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SRC="$WS_ROOT/project/carbon-footprint"
DST="${CARBON_PROJECT_DIR:-$HOME/DevEcoStudioProjects/carbon-footprint}"

if [ ! -d "$SRC" ]; then
  echo "错误：找不到工程源码 $SRC" >&2
  exit 1
fi

# 1) 同步源码到纯英文路径（保留目标里已有的 oh_modules / build / .hvigor）
mkdir -p "$DST"
(cd "$SRC" && tar cf - --exclude=build --exclude=.hvigor --exclude=oh_modules .) \
  | (cd "$DST" && tar xf -)

# 2) 依赖检查
if [ ! -d "$DST/oh_modules" ]; then
  echo "提示：尚未安装依赖，正在执行 ohpm install …"
  export OHPM_HOME="${OHPM_HOME:-$HOME/.ohpm}"
  (cd "$DST" && /Applications/DevEco-Studio.app/Contents/tools/ohpm/bin/ohpm install)
fi

# 3) 构建
cd "$DST"
./hvigorw "${1:-assembleHap}" --no-daemon

echo
echo "构建产物："
find "$DST/entry/build" -name '*.hap' 2>/dev/null || echo "（未找到 HAP）"
