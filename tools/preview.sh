#!/usr/bin/env bash
# ---------------------------------------------------------------------------
#  碳迹 —— 视觉迭代预览（构建 → 签名 → 装到模拟器 → 截图）
#
#  和 tools/build.sh 的区别：
#    build.sh 同步到 ~/DevEcoStudioProjects/（给 DevEco Studio 用）
#    preview.sh 同步到 /tmp/carbon-footprint（纯英文路径），一条命令直接出截图，
#               不需要打开 DevEco Studio 图形界面。
#
#  为什么要在 /tmp 里构建：hvigor 拒绝含非 ASCII 字符的工程路径，
#  而工作区路径是中文的。~ 下也可以，但 /tmp 不污染用户目录。
#
#  依赖：先把 ~/DevEcoStudioProjects/carbon-footprint 里的
#        oh_modules / signing 复制到 /tmp/carbon-footprint（首次执行本脚本会自动做）。
#
#  用法：
#    tools/preview.sh              完整流程（构建 + 签名 + 安装 + 截图）
#    tools/preview.sh build        只构建 + 签名
#    tools/preview.sh shot 名字    只截图（存到 素材/截图/预览/）
#    tools/preview.sh tap X Y      按坐标点击
#    tools/preview.sh tab N        切到第 N 个页签（0..4）
# ---------------------------------------------------------------------------
set -euo pipefail

WS_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SRC="$WS_ROOT/project/carbon-footprint"
BUILD_DIR="${CARBON_PREVIEW_DIR:-/tmp/carbon-footprint}"
REF_DIR="${CARBON_REF_DIR:-$HOME/DevEcoStudioProjects/carbon-footprint}"
SHOT_DIR="$WS_ROOT/素材/截图/预览"

DEVECO_APP="${DEVECO_APP:-/Applications/DevEco-Studio.app}"
HDC="$DEVECO_APP/Contents/sdk/default/openharmony/toolchains/hdc"
BUNDLE="com.henan.carbonfootprint"
ABILITY="EntryAbility"

mkdir -p "$SHOT_DIR"

# --- 设备检查 -------------------------------------------------------------
need_device() {
  local t
  t="$("$HDC" list targets 2>/dev/null | tr -d '\r' | head -1)"
  if [ -z "$t" ] || [ "$t" = "[Empty]" ]; then
    echo "错误：没有设备。先执行 tools/emulator.sh start && tools/emulator.sh wait" >&2
    exit 1
  fi
  echo "$t"
}

# --- 同步源码到 /tmp -------------------------------------------------------
sync_src() {
  mkdir -p "$BUILD_DIR"
  (cd "$SRC" && tar cf - --exclude=build --exclude=.hvigor --exclude=oh_modules --exclude=signing .) \
    | (cd "$BUILD_DIR" && tar xf -)
  # oh_modules / signing / .hvigor 只复制一次（它们体积大且不随源码变化）
  for d in oh_modules signing .hvigor; do
    if [ ! -e "$BUILD_DIR/$d" ] && [ -e "$REF_DIR/$d" ]; then
      echo "同步 $d …"
      cp -R "$REF_DIR/$d" "$BUILD_DIR/$d"
    fi
  done
}

do_build() {
  sync_src
  cd "$BUILD_DIR"
  # hvigor / npm / ohpm 默认都往 ~ 下写缓存；整个重定向到 /tmp，
  # 让构建全程只落在可写区（工作区外的东西一律不碰）。
  export HOME="${CARBON_FAKE_HOME:-/tmp/carbon-home}"
  export HVIGOR_USER_HOME="$HOME/.hvigor"
  export npm_config_cache="$HOME/.npm"
  mkdir -p "$HOME" "$HVIGOR_USER_HOME" "$npm_config_cache"
  ./hvigorw assembleHap --no-daemon 2>&1 | tail -6
  local unsigned
  unsigned="$(find "$BUILD_DIR/entry/build" -name '*-unsigned.hap' | head -1)"
  if [ -z "$unsigned" ]; then echo "错误：没有产出 HAP" >&2; exit 1; fi
  CARBON_PROJECT_DIR="$BUILD_DIR" CARBON_SIGN_DIR="$BUILD_DIR/signing" \
    "$WS_ROOT/tools/sign.sh" "$unsigned" >/dev/null
  echo "已签名：${unsigned%-unsigned.hap}-signed.hap"
}

do_install() {
  local hap
  hap="$(find "$BUILD_DIR/entry/build" -name '*-signed.hap' | head -1)"
  [ -n "$hap" ] || { echo "错误：没有签名 HAP" >&2; exit 1; }
  "$HDC" install -r "$hap"
  "$HDC" shell aa start -a "$ABILITY" -b "$BUNDLE" >/dev/null 2>&1 || true
}

do_shot() {
  local name="${1:-shot}"
  local remote="/data/local/tmp/${name}.jpeg"
  "$HDC" shell snapshot_display -f "$remote" >/dev/null 2>&1
  "$HDC" file recv "$remote" "$SHOT_DIR/${name}.jpeg" >/dev/null 2>&1
  "$HDC" shell rm -f "$remote" >/dev/null 2>&1 || true
  echo "截图：$SHOT_DIR/${name}.jpeg"
}

do_tap() {
  "$HDC" shell uinput -T -c "$1" "$2" >/dev/null 2>&1 || \
    "$HDC" shell input tap "$1" "$2" >/dev/null 2>&1 || true
  sleep 1
}

# 五个页签的坐标：屏幕 1320×2232，页签栏可点区约 y∈[1992,2160]
# （实测：y=2170 落在系统导航区，点了没反应；y=2075 可靠命中）
do_tab() {
  local i="${1:-0}"
  local x=$(( 132 + i * 264 ))
  "$HDC" shell uinput -T -c "$x" 2075 >/dev/null 2>&1 || true
  sleep 2
}

action="${1:-all}"
case "$action" in
  build)   do_build ;;
  install) do_install ;;
  shot)    need_device >/dev/null; do_shot "${2:-shot}" ;;
  tap)     do_tap "$2" "$3" ;;
  tab)     do_tab "$2" ;;
  all)
    need_device
    do_build
    do_install
    sleep 4
    do_shot "01-记一笔"
    do_tab 1; do_shot "02-看板"
    do_tab 2; do_shot "03-积分"
    do_tab 3; do_shot "04-科普"
    do_tab 4; do_shot "05-我的"
    ;;
  *) sed -n '2,30p' "$0" ;;
esac
