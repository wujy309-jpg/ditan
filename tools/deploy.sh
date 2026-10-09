#!/usr/bin/env bash
# ---------------------------------------------------------------------------
#  碳迹 —— 发布到 DevEco Studio 工程目录
#
#  工程必须放在纯英文路径，DevEco Studio 也需要在常规位置打开它，
#  因此把工作区源码同步到 ~/DevEcoStudioProjects/carbon-footprint。
#
#  ⚠️ 单一事实来源：本工作区的 project/carbon-footprint 是源码正本。
#     如果你在 DevEco Studio 里改了代码，请把改动同步回工作区，
#     否则下次执行本脚本会覆盖你的修改。
#
#  用法：
#    tools/deploy.sh
#    可选环境变量：
#      CARBON_DEPLOY_TARGET   目标目录（默认 ~/DevEcoStudioProjects/carbon-footprint）
# ---------------------------------------------------------------------------
set -euo pipefail

WS_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SRC="$WS_ROOT/project/carbon-footprint"
TARGET="${CARBON_DEPLOY_TARGET:-$HOME/DevEcoStudioProjects/carbon-footprint}"

if [ ! -d "$SRC" ]; then
  echo "错误：找不到工程源码 $SRC" >&2
  exit 1
fi

mkdir -p "$TARGET"
# 覆盖同步源码，但保留目标目录里已有的 build / .hvigor / oh_modules 等本地产物
(cd "$SRC" && tar cf - --exclude=build --exclude=.hvigor --exclude=oh_modules .) \
  | (cd "$TARGET" && tar xf -)

echo "已同步到：$TARGET"
echo
echo "下一步："
echo "  1. 用 DevEco Studio 打开该目录"
echo "  2. File → Project Structure → Signing Configs → 勾选 Automatically generate signature"
echo "  3. 选择模拟器或真机，点击 Run"
