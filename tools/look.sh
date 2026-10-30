#!/usr/bin/env bash
# ---------------------------------------------------------------------------
#  碳迹 —— 快速视觉迭代：构建 → 安装 → 截当前屏 → 裁印章放大
#
#  和 tools/preview.sh 的分工：
#    preview.sh  正经流程，五页截图落到 素材/截图/预览/
#    本脚本      只给「印章 / 细节」反复调参用，一次往返约 20 秒，
#                截完直接裁出印章区域放大 4×，存到 /tmp/look-<名字>.png
#
#  用法：tools/look.sh 印章       # 构建+安装+截图+裁印章
#        tools/look.sh 印章 0.6   # 同上，并临时改抖动幅度（只改 /tmp 构建副本）
# ---------------------------------------------------------------------------
set -euo pipefail

WS_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
NAME="${1:-look}"
ROUGH="${2:-}"

"$WS_ROOT/tools/preview.sh" build >/dev/null
# 抖动幅度是 Seal 的默认参数，想在真机上比几个值就改 /tmp 副本再单独构建
if [ -n "$ROUGH" ]; then
  sed -i '' -E "s/@Prop rough: number = [0-9.]+;/@Prop rough: number = ${ROUGH};/" \
    /tmp/carbon-footprint/entry/src/main/ets/view/Common.ets
  ( cd /tmp/carbon-footprint && \
    HOME=/tmp/carbon-home HVIGOR_USER_HOME=/tmp/carbon-home/.hvigor \
    ./hvigorw assembleHap --no-daemon >/dev/null 2>&1 )
  u="$(find /tmp/carbon-footprint/entry/build -name '*-unsigned.hap' | head -1)"
  CARBON_PROJECT_DIR=/tmp/carbon-footprint CARBON_SIGN_DIR=/tmp/carbon-footprint/signing \
    "$WS_ROOT/tools/sign.sh" "$u" >/dev/null
fi

"$WS_ROOT/tools/preview.sh" install >/dev/null
sleep 5
"$WS_ROOT/tools/preview.sh" shot "$NAME" >/dev/null

python3 - "$WS_ROOT/素材/截图/预览/${NAME}.jpeg" "$NAME" <<'PY'
import sys
from PIL import Image
src, name = sys.argv[1], sys.argv[2]
im = Image.open(src)
w, h = im.size
# 印章在抬头区右上：横 74%–100%，纵 6%–13%
box = (int(w * 0.74), int(h * 0.055), int(w * 1.0), int(h * 0.130))
c = im.crop(box)
c = c.resize((c.width * 4, c.height * 4), Image.LANCZOS)
out = f"/tmp/look-{name}.png"
c.save(out)
print(f"放大 4×：{out}  ({c.width}×{c.height})")
PY
