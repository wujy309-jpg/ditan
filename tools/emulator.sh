#!/usr/bin/env bash
# ---------------------------------------------------------------------------
#  碳迹 —— 模拟器管理（纯命令行，不需要 DevEco Studio 图形界面）
#
#  为什么可以用命令行：DevEco 自带的 Emulator 二进制其实是一套完整的 CLI，
#  支持镜像下载 / 建实例 / 启动 / 停止，详见 `Emulator -help`。
#
#  用法：
#    tools/emulator.sh images              查看可用镜像与下载状态
#    tools/emulator.sh install             下载手机镜像（约 2.3 GB）
#    tools/emulator.sh create              创建实例
#    tools/emulator.sh start               启动实例（后台）
#    tools/emulator.sh wait                等待设备上线
#    tools/emulator.sh install-app [hap]   安装已签名 HAP（缺省自动取最新）
#    tools/emulator.sh log                 看应用日志
#    tools/emulator.sh stop                停止实例
#    tools/emulator.sh list                列出实例
#
#  可覆盖的环境变量：
#    EMU_NAME      实例名（默认 carbon）
#    EMU_DEVICE    设备类型（默认 phone）
#    EMU_OS        系统版本（默认 HarmonyOS 7.0.0(26.0.0)）
# ---------------------------------------------------------------------------
set -euo pipefail

DEVECO_APP="${DEVECO_APP:-/Applications/DevEco-Studio.app}"
EMU="$DEVECO_APP/Contents/tools/emulator/Emulator"
HDC="$DEVECO_APP/Contents/sdk/default/openharmony/toolchains/hdc"
PROJECT="${CARBON_PROJECT_DIR:-$HOME/DevEcoStudioProjects/carbon-footprint}"

EMU_NAME="${EMU_NAME:-carbon}"
EMU_DEVICE="${EMU_DEVICE:-phone}"
EMU_OS="${EMU_OS:-HarmonyOS 7.0.0(26.0.0)}"

if [ ! -x "$EMU" ]; then
  echo "错误：找不到 Emulator（$EMU）" >&2
  exit 1
fi

action="${1:-help}"

case "$action" in
  images)
    "$EMU" -imageList | python3 -c "
import sys, json
data = json.load(sys.stdin)
dl = [d for d in data if d['downloaded'] == 'true']
print(f'可用镜像 {len(data)} 个，已下载 {len(dl)} 个')
for d in dl:
    print(f\"  [已下载] {d['deviceType']:<12} {d['osVersion']}\")
"
    ;;

  install)
    echo "开始下载镜像：$EMU_DEVICE / $EMU_OS（约 2.3 GB）"
    "$EMU" -license accept >/dev/null 2>&1 || true
    "$EMU" -install -deviceType "$EMU_DEVICE" -osVersion "$EMU_OS" -force
    ;;

  create)
    echo "创建实例：$EMU_NAME（$EMU_DEVICE / $EMU_OS）"
    "$EMU" -create "$EMU_NAME" -deviceType "$EMU_DEVICE" -osVersion "$EMU_OS" -force 2>&1 || true
    "$EMU" -list -details || true
    ;;

  start)
    echo "启动实例：$EMU_NAME"
    nohup "$EMU" -start "$EMU_NAME" >/tmp/carbon-emulator.log 2>&1 &
    echo "已后台启动，日志：/tmp/carbon-emulator.log"
    ;;

  wait)
    echo -n "等待设备上线"
    for i in $(seq 1 90); do
      targets="$("$HDC" list targets 2>/dev/null | tr -d '\r')"
      if [ -n "$targets" ] && [ "$targets" != "[Empty]" ]; then
        echo
        echo "设备已上线："
        echo "$targets"
        exit 0
      fi
      echo -n "."
      sleep 2
    done
    echo
    echo "超时：3 分钟内没有设备上线" >&2
    exit 1
    ;;

  install-app)
    hap="${2:-}"
    if [ -z "$hap" ]; then
      hap="$(find "$PROJECT/entry/build" -name '*-signed.hap' 2>/dev/null | head -1)"
    fi
    if [ -z "$hap" ] || [ ! -f "$hap" ]; then
      echo "错误：找不到已签名 HAP，先跑 tools/build.sh 与 tools/sign.sh" >&2
      exit 1
    fi
    echo "安装：$hap"
    "$HDC" install -r "$hap"
    echo "启动应用…"
    "$HDC" shell aa start -a EntryAbility -b com.henan.carbonfootprint || true
    ;;

  log)
    "$HDC" shell hilog | grep -i "carbon\|DistributedStore\|CarbonRepo" || true
    ;;

  stop)
    "$EMU" -stop "$EMU_NAME" || true
    ;;

  list)
    "$EMU" -list -details || true
    "$HDC" list targets || true
    ;;

  *)
    sed -n '2,25p' "$0"
    ;;
esac
