#!/usr/bin/env bash
# ---------------------------------------------------------------------------
#  碳迹 —— 真机（或模拟器）操作工具
#
#  为什么单独做这个脚本：
#    原来的 tools/emulator.sh 是给模拟器用的（依赖 Emulator 二进制的
#    实例名、UI 自动化参数）。真机没有这些东西，只能走 hdc。但两者在
#    「装应用 / 起应用 / 截图 / 看日志」这四件事上是共通的，所以抽到这里。
#
#  用法：
#    tools/device.sh list                 列出所有已连接设备（含 UDID）
#    tools/device.sh connect 192.168.1.5:8710    无线连接（手机需先开无线调试）
#    tools/device.sh disconnect <key>     断开无线连接
#    tools/device.sh info                 当前设备的型号 / 系统 / UDID
#    tools/device.sh install              安装已签名 HAP
#    tools/device.sh start                启动应用
#    tools/device.sh stop                 停止应用
#    tools/device.sh shot [输出路径]       截图（默认 素材/截图/真机-时间戳.jpeg）
#    tools/device.sh log [关键词]          看应用日志
#    tools/device.sh udid                 只打印 UDID（注册到华为 AGC 用）
#
#  指定设备（多台时）：
#    加 -t <key>，例如：tools/device.sh -t 192.168.1.5:8710 install
# ---------------------------------------------------------------------------
set -euo pipefail

WS_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DEVECO_APP="${DEVECO_APP:-/Applications/DevEco-Studio.app}"
HDC="$DEVECO_APP/Contents/sdk/default/openharmony/toolchains/hdc"
BUNDLE="com.henan.carbonfootprint"
HAP="$HOME/DevEcoStudioProjects/carbon-footprint/entry/build/default/outputs/default/entry-default-signed.hap"

CMD_TARGET=()
if [ "${1:-}" = "-t" ]; then
  CMD_TARGET=(-t "$2")
  shift 2
fi

if [ ! -x "$HDC" ]; then
  echo "错误：找不到 hdc（${HDC}）" >&2
  exit 1
fi

# 注意：macOS 自带 bash 3.2，在 set -u 下直接展开空数组会报
# 「unbound variable」。这里用安全的展开写法，空数组时等价于什么都不加。
h() { "$HDC" ${CMD_TARGET[@]+"${CMD_TARGET[@]}"} "$@"; }

# ---------------------------------------------------------------------------
# 是否是真机（用来给出针对性的提示）
# ---------------------------------------------------------------------------
is_emulator() {
  local model
  model="$(h shell "param get const.product.model" 2>/dev/null | tr -d '\r\n' | tr -d ' ')"
  [ "$model" = "emulator" ]
}

# ---------------------------------------------------------------------------
cmd_list() {
  echo "=== 已连接设备 ==="
  "$HDC" list targets -v 2>&1 | sed 's/^/  /'
  echo
  echo "说明：TCP 行是无线/模拟器连接，USB 行是数据线直连。"
  echo "     真机第一次连接需要在手机上点「允许调试」。"
}

cmd_connect() {
  local key="${1:-}"
  if [ -z "$key" ]; then
    echo "用法：tools/device.sh connect <手机IP:端口>" >&2
    echo "端口在手机「开发者选项 → 无线调试」里看。" >&2
    exit 1
  fi
  "$HDC" tconn "$key"
}

cmd_disconnect() {
  "$HDC" tconn "${1:?用法：tools/device.sh disconnect <key>}" -remove
}

cmd_info() {
  echo "=== 当前设备 ==="
  printf "  型号      : %s\n" "$(h shell "param get const.product.model" 2>/dev/null | tr -d '\r\n')"
  printf "  品牌      : %s\n" "$(h shell "param get const.product.brand" 2>/dev/null | tr -d '\r\n')"
  printf "  系统版本  : %s\n" "$(h shell "param get const.product.software.version" 2>/dev/null | tr -d '\r\n')"
  printf "  API 版本  : %s\n" "$(h shell "param get const.ohos.apiversion" 2>/dev/null | tr -d '\r\n')"
  printf "  UDID      : %s\n" "$(cmd_udid)"
  echo
  if is_emulator; then
    echo "  类型：模拟器"
  else
    echo "  类型：真机"
  fi
}

cmd_udid() {
  # 输出形如：
  #   udid of current device is :
  #   454D5504...0000
  # 值在**下一行**，所以取最后一行的非空内容。
  h shell bm get --udid 2>/dev/null | tr -d '\r' | grep -vE '^\s*$' | tail -1
}

cmd_install() {
  if [ ! -f "$HAP" ]; then
    echo "错误：找不到已签名 HAP" >&2
    echo "  路径：$HAP" >&2
    echo "  请先执行：tools/build.sh && tools/sign.sh" >&2
    exit 1
  fi
  echo "安装：$(basename "$HAP")  ($(du -h "$HAP" | cut -f1))"
  if h install -r "$HAP" 2>&1 | tee /tmp/carbon-install.log | sed 's/^/  /'; then
    :
  fi
  if grep -qiE "failed|error" /tmp/carbon-install.log; then
    echo
    echo "────────────────────────────────────────────────────────────"
    echo "安装失败。如果你用的是**华为商用手机**，最可能的原因是签名："
    echo
    echo "  本工程默认的 tools/sign.sh 用的是 **OpenHarmony 通用调试签名**"
    echo "  （OpenHarmony.p12 + OpenHarmony Application CA）。"
    echo "  这套材料在模拟器和 OpenHarmony 设备上可用，"
    echo "  但**华为商用机只信任华为签发的证书**，会直接拒绝安装。"
    echo
    echo "  真机请改用华为调试签名，见《真机接入指南.md》："
    echo "    在 DevEco Studio 里勾选 Automatically generate signature，"
    echo "    它会自动把本机 UDID 注册到华为 AGC 并生成绑定该设备的 profile。"
    echo "────────────────────────────────────────────────────────────"
    exit 1
  fi
  echo "  安装完成"
}

cmd_start() {
  h shell aa start -a EntryAbility -b "$BUNDLE" 2>&1 | sed 's/^/  /'
  echo "  已请求启动 $BUNDLE"
}

cmd_stop() {
  h shell aa force-stop "$BUNDLE" 2>&1 | sed 's/^/  /' || true
  echo "  已停止 $BUNDLE"
}

cmd_shot() {
  local out="${1:-$WS_ROOT/素材/截图/真机-$(date +%m%d-%H%M%S).jpeg}"
  mkdir -p "$(dirname "$out")"
  h shell snapshot_display -f /data/local/tmp/carbon-shot.jpeg >/dev/null 2>&1
  h file recv /data/local/tmp/carbon-shot.jpeg "$out" >/dev/null 2>&1
  if [ -f "$out" ]; then
    echo "  截图已保存：$out"
  else
    echo "  截图失败" >&2
    exit 1
  fi
}

cmd_log() {
  local kw="${1:-}"
  if [ -n "$kw" ]; then
    echo "=== 应用日志（过滤：${kw}）==="
    h shell hilog -x 2>/dev/null | grep -iE "$kw|carbonfootprint" | tail -40
  else
    echo "=== 应用日志（全部）==="
    h shell hilog -x 2>/dev/null | grep -iE "carbonfootprint" | tail -40
  fi
}

case "${1:-}" in
  list)       cmd_list ;;
  connect)    shift; cmd_connect "$@" ;;
  disconnect) shift; cmd_disconnect "$@" ;;
  info)       cmd_info ;;
  udid)       cmd_udid ;;
  install)    cmd_install ;;
  start)      cmd_start ;;
  stop)       cmd_stop ;;
  shot)       shift; cmd_shot "$@" ;;
  log)        shift; cmd_log "$@" ;;
  *)
    sed -n '2,30p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
    exit 1
    ;;
esac
