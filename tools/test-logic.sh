#!/usr/bin/env bash
# ---------------------------------------------------------------------------
#  碳迹 —— 纯逻辑单元测试
#
#  原理：model/ 与 data/ 下的纯逻辑模块（Models / FactorLibrary / TaskEngine）
#        不含任何 ArkUI 装饰器，本质就是 TypeScript。把它们原样复制成 .ts，
#        用 DevEco 自带的 tsc 编译后用 node 跑断言，即可在没有设备的情况下
#        验证「减排量算得对不对」「任务推荐逻辑对不对」。
#
#  用法：
#    tools/test-logic.sh
#    CARBON_TSC=/path/to/tsc.js CARBON_NODE=/path/to/node tools/test-logic.sh
#
#  为什么加路径候选：
#    原脚本把 tsc / node 写死成 macOS 的 /Applications/DevEco-Studio.app/...，
#    在任何非 macOS 机器上第一次运行就 exit 1。而它是验收四件套之一，
#    「工具坏了」和「代码坏了」会混在一起，属于最该修的一类问题。
# ---------------------------------------------------------------------------
set -euo pipefail

WS_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SRC="$WS_ROOT/project/carbon-footprint/entry/src/main/ets"
WORK="${TMPDIR:-/tmp}/carbon-logic-test"

# ---- 定位 node -------------------------------------------------------------
NODE_BIN="${CARBON_NODE:-}"
if [ -z "$NODE_BIN" ]; then
  for cand in \
    "/Applications/DevEco-Studio.app/Contents/tools/node/bin/node" \
    "C:/Program Files/Huawei/DevEco Studio/tools/node/node.exe" \
    "C:/Program Files/Huawei/DevEco-Studio/tools/node/node.exe" \
    "$HOME/DevEco-Studio/tools/node/bin/node"; do
    if [ -x "$cand" ]; then
      NODE_BIN="$cand"
      break
    fi
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
# 优先 DevEco 自带的 typescript（4.9.5），其次 PATH 上的 tsc
TSC_JS="${CARBON_TSC:-}"
if [ -n "$TSC_JS" ] && [ ! -f "$TSC_JS" ] && [ ! -x "$TSC_JS" ]; then
  echo "错误：CARBON_TSC 指向的文件不存在：$TSC_JS" >&2
  exit 1
fi
if [ -z "$TSC_JS" ]; then
  for root in \
    "/Applications/DevEco-Studio.app/Contents" \
    "C:/Program Files/Huawei/DevEco Studio" \
    "C:/Program Files/Huawei/DevEco-Studio" \
    "$HOME/DevEco-Studio" \
    "${DEVECO_HOME:-}"; do
    [ -n "$root" ] || continue
    for sub in \
      "tools/hvigor/hvigor/node_modules/typescript/lib/tsc.js" \
      "tools/hvigor/hvigor-ohos-plugin/node_modules/typescript/lib/tsc.js"; do
      if [ -f "$root/$sub" ]; then
        TSC_JS="$root/$sub"
        break 2
      fi
    done
  done
fi
TSC_BIN=""
if [ -z "$TSC_JS" ]; then
  TSC_BIN="$(command -v tsc || true)"
fi
if [ -z "$TSC_JS" ] && [ -z "$TSC_BIN" ]; then
  echo "错误：找不到 tsc" >&2
  echo "  已查找 DevEco 默认安装目录与 PATH。可用 CARBON_TSC=<tsc.js 或 tsc 可执行文件> 指定。" >&2
  exit 1
fi

rm -rf "$WORK"
mkdir -p "$WORK/model" "$WORK/data" "$WORK/common"

# 原样复制纯逻辑模块（.ets → .ts），保持 import 相对路径不变
cp "$SRC/model/Models.ets"        "$WORK/model/Models.ts"
cp "$SRC/data/FactorLibrary.ets"  "$WORK/data/FactorLibrary.ts"
cp "$SRC/data/TaskEngine.ets"     "$WORK/data/TaskEngine.ts"
cp "$SRC/common/RoughMath.ets"    "$WORK/common/RoughMath.ts"
cp "$WS_ROOT/tests/logic.test.ts" "$WORK/logic.test.ts"

cd "$WORK"
# 宽松编译：只要类型层面能过就够，重点是跑逻辑
if [ -n "$TSC_JS" ]; then
  "$NODE_BIN" "$TSC_JS" --target ES2021 --module commonjs --moduleResolution node \
    --strict false --skipLibCheck --outDir out \
    model/Models.ts data/FactorLibrary.ts data/TaskEngine.ts common/RoughMath.ts logic.test.ts
else
  "$TSC_BIN" --target ES2021 --module commonjs --moduleResolution node \
    --strict false --skipLibCheck --outDir out \
    model/Models.ts data/FactorLibrary.ts data/TaskEngine.ts common/RoughMath.ts logic.test.ts
fi

"$NODE_BIN" out/logic.test.js
