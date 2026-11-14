#!/usr/bin/env bash
# ---------------------------------------------------------------------------
#  碳迹 —— 并发互斥测试（common/Mutex.ets）
#
#  姊妹脚本：tools/test-logic.sh（55 项纯逻辑断言）
#  本脚本只做一件事：证明 B4「三道防线」的第 1 道——互斥是真的。
#  为什么单独一个脚本：见 tests/mutex.test.ts 文件头。简言之，别让「55」
#  这个已经对外报出去的数字继续漂移。
#
#  用法：
#    tools/test-mutex.sh
#    CARBON_TSC=/path/to/tsc.js CARBON_NODE=/path/to/node tools/test-mutex.sh
# ---------------------------------------------------------------------------
set -euo pipefail

WS_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SRC="$WS_ROOT/project/carbon-footprint/entry/src/main/ets"
WORK="${TMPDIR:-/tmp}/carbon-mutex-test"

# ---- 定位 DevEco（复用 tools/lib/deveco.sh，全平台候选路径都在里面）--------
DEVECO_ROOT=""
# shellcheck source=lib/deveco.sh
if . "$WS_ROOT/tools/lib/deveco.sh" 2>/dev/null; then
  DEVECO_ROOT="$(deveco_home 2>/dev/null || true)"
fi

# ---- 定位 node -------------------------------------------------------------
NODE_BIN="${CARBON_NODE:-}"
if [ -z "$NODE_BIN" ] && [ -n "$DEVECO_ROOT" ]; then
  for cand in \
    "$DEVECO_ROOT/tools/node/bin/node" \
    "$DEVECO_ROOT/Contents/tools/node/bin/node" \
    "$DEVECO_ROOT/tools/node/node.exe"; do
    if [ -x "$cand" ]; then NODE_BIN="$cand"; break; fi
  done
fi
if [ -z "$NODE_BIN" ]; then
  NODE_BIN="$(command -v node || true)"
fi
if [ -z "$NODE_BIN" ]; then
  echo "错误：找不到 node（可用 CARBON_NODE 指定）" >&2
  exit 1
fi

# ---- 定位 tsc --------------------------------------------------------------
TSC_JS="${CARBON_TSC:-}"
if [ -z "$TSC_JS" ] && [ -n "$DEVECO_ROOT" ]; then
  for sub in \
    "tools/hvigor/hvigor/node_modules/typescript/lib/tsc.js" \
    "tools/hvigor/hvigor-ohos-plugin/node_modules/typescript/lib/tsc.js" \
    "Contents/tools/hvigor/hvigor/node_modules/typescript/lib/tsc.js"; do
    if [ -f "$DEVECO_ROOT/$sub" ]; then TSC_JS="$DEVECO_ROOT/$sub"; break; fi
  done
fi
TSC_BIN=""
if [ -z "$TSC_JS" ]; then
  TSC_BIN="$(command -v tsc || true)"
fi
if [ -z "$TSC_JS" ] && [ -z "$TSC_BIN" ]; then
  echo "错误：找不到 tsc（可用 CARBON_TSC 指定 tsc.js 或 tsc 可执行文件）" >&2
  exit 1
fi

rm -rf "$WORK"
mkdir -p "$WORK/common"

# 原样复制（.ets → .ts），保持 import 相对路径不变
cp "$SRC/common/Mutex.ets"       "$WORK/common/Mutex.ts"
cp "$WS_ROOT/tests/mutex.test.ts" "$WORK/mutex.test.ts"

cd "$WORK"
TSC_ARGS=(--target ES2021 --module commonjs --moduleResolution node
          --strict false --skipLibCheck --outDir out
          common/Mutex.ts mutex.test.ts)
if [ -n "$TSC_JS" ]; then
  "$NODE_BIN" "$TSC_JS" "${TSC_ARGS[@]}"
else
  "$TSC_BIN" "${TSC_ARGS[@]}"
fi

"$NODE_BIN" out/mutex.test.js
