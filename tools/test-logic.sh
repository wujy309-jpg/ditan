#!/usr/bin/env bash
# ---------------------------------------------------------------------------
#  碳迹 —— 纯逻辑单元测试
#
#  原理：model/ 与 data/ 下的纯逻辑模块（Models / FactorLibrary / TaskEngine）
#        不含任何 ArkUI 装饰器，本质就是 TypeScript。把它们原样复制成 .ts，
#        用 DevEco 自带的 tsc 编译后用 node 跑断言，即可在没有设备的情况下
#        验证「减排量算得对不对」「任务推荐逻辑对不对」。
#
#  用法：tools/test-logic.sh
# ---------------------------------------------------------------------------
set -euo pipefail

WS_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SRC="$WS_ROOT/project/carbon-footprint/entry/src/main/ets"
# DevEco 自带的 typescript 4.9.5（ohpm 下的 .bin/tsc 是坏的符号链接，不能用）
TSC_JS="/Applications/DevEco-Studio.app/Contents/tools/hvigor/hvigor/node_modules/typescript/lib/tsc.js"
NODE="/Applications/DevEco-Studio.app/Contents/tools/node/bin/node"
WORK="${TMPDIR:-/tmp}/carbon-logic-test"

if [ ! -f "$TSC_JS" ]; then
  echo "错误：找不到 tsc（$TSC_JS）" >&2
  exit 1
fi

rm -rf "$WORK"
mkdir -p "$WORK/model" "$WORK/data"

# 原样复制纯逻辑模块（.ets → .ts），保持 import 相对路径不变
cp "$SRC/model/Models.ets"            "$WORK/model/Models.ts"
cp "$SRC/data/FactorLibrary.ets"      "$WORK/data/FactorLibrary.ts"
cp "$SRC/data/TaskEngine.ets"         "$WORK/data/TaskEngine.ts"
cp "$WS_ROOT/tests/logic.test.ts"     "$WORK/logic.test.ts"

cd "$WORK"
# 宽松编译：只要类型层面能过就够，重点是跑逻辑
"$NODE" "$TSC_JS" --target ES2021 --module commonjs --moduleResolution node \
       --strict false --skipLibCheck --outDir out \
       model/Models.ts data/FactorLibrary.ts data/TaskEngine.ts logic.test.ts

"$NODE" out/logic.test.js
