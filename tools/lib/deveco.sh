#!/usr/bin/env bash
# ---------------------------------------------------------------------------
#  deveco.sh —— 跨平台定位 DevEco Studio 的各个工具（被其他脚本 source）
#
#  用法：
#    . "$(dirname "${BASH_SOURCE[0]}")/lib/deveco.sh"
#    deveco_locate            # 定位并按需 export，失败返回 1
#
#  为什么要这一层：
#    原脚本各自写死 /Applications/DevEco-Studio.app，换到 Windows 或自定义
#    安装盘直接报「找不到」。这里把「去哪找、找到怎么拼路径」收在一处。
#
#  查找顺序（先命中先用）：
#    1. $DEVECO_HOME              显式指定，优先
#    2. macOS 默认                 /Applications/DevEco-Studio.app
#    3. Windows 默认常见位置        C:\Program Files\Huawei\DevEco Studio 等
#    4. 当前用户目录自装            $HOME/DevEco-Studio 等
#    5. PATH 上的 deveco / DevEco Studio
# ---------------------------------------------------------------------------
# shellcheck shell=bash

# 该目录下同时存在 tools/ 与 sdk/ 时视为有效的 DevEco 根目录
_deveco_is_root() {
  [ -d "$1" ] && [ -d "$1/tools" ] && { [ -d "$1/sdk" ] || [ -d "$1/Contents/sdk" ]; }
}

_deveco_candidates() {
  printf '%s\n' \
    "${DEVECO_HOME:-}" \
    "/Applications/DevEco-Studio.app" \
    "/Applications/DevEco-Studio.app/Contents" \
    "C:/Program Files/Huawei/DevEco Studio" \
    "C:/Program Files/Huawei/DevEco Studio/Contents" \
    "D:/Program Files/Huawei/DevEco Studio" \
    "E:/Huawei/DveStudio/DevEco Studio" \
    "$HOME/DevEco-Studio" \
    "$HOME/DevEcoStudio" \
    "/opt/DevEco-Studio" \
    "/usr/local/DevEco-Studio"
}

# 输出 DevEco 根目录；找不到返回 1 且不输出任何内容
deveco_home() {
  local c
  while IFS= read -r c; do
    [ -n "$c" ] || continue
    c="${c%/}"
    if _deveco_is_root "$c"; then
      printf '%s\n' "$c"
      return 0
    fi
    # 传入 .../DevEco-Studio.app/Contents 这种也要能认
    if [ -d "$c/sdk" ] && [ -d "$c/tools" ]; then
      printf '%s\n' "$c"
      return 0
    fi
  done < <(_deveco_candidates)
  return 1
}

# 定位并 export 常用路径。返回 1 表示没装/没找到。
deveco_locate() {
  local home
  if ! home="$(deveco_home)"; then
    echo "错误：找不到 DevEco Studio。" >&2
    echo "      可用 DEVECO_HOME=<安装根目录> 指定，例如：" >&2
    echo "        Windows: DEVECO_HOME='E:/Huawei/DveStudio/DevEco Studio'" >&2
    echo "        macOS  : DEVECO_HOME='/Applications/DevEco-Studio.app'" >&2
    return 1
  fi
  export DEVECO_HOME="$home"

  # sdk 目录：macOS 在 Contents/sdk，Windows 直接在根下
  if [ -d "$home/Contents/sdk" ]; then
    export DEVECO_SDK_HOME="$home/Contents/sdk"
    export DEVECO_TOOLS="$home/Contents/tools"
  else
    export DEVECO_SDK_HOME="$home/sdk"
    export DEVECO_TOOLS="$home/tools"
  fi

  # node：Windows 自带 node.exe，macOS/Linux 用系统 node
  if [ -x "$DEVECO_TOOLS/node/node.exe" ]; then
    export DEVECO_NODE="$DEVECO_TOOLS/node/node.exe"
  elif [ -x "$DEVECO_TOOLS/node/bin/node" ]; then
    export DEVECO_NODE="$DEVECO_TOOLS/node/bin/node"
  else
    export DEVECO_NODE="$(command -v node || true)"
  fi

  export DEVECO_HVIGORW="$DEVECO_TOOLS/hvigor/bin/hvigorw.js"
  export DEVECO_HDC="$DEVECO_SDK_HOME/default/openharmony/toolchains/hdc"
  [ -x "${DEVECO_HDC}.exe" ] && export DEVECO_HDC="${DEVECO_HDC}.exe"
  export DEVECO_OHPM="$DEVECO_TOOLS/ohpm/bin/ohpm"
  [ -x "${DEVECO_OHPM}.bat" ] && export DEVECO_OHPM="${DEVECO_OHPM}.bat"
  export DEVECO_TSC="$DEVECO_TOOLS/hvigor/hvigor/node_modules/typescript/lib/tsc.js"
  export DEVECO_EMULATOR="$DEVECO_TOOLS/emulator/Emulator"
  [ -x "${DEVECO_EMULATOR}.exe" ] && export DEVECO_EMULATOR="${DEVECO_EMULATOR}.exe"

  # hvigor 默认把缓存写到 ~/.hvigor，受限环境里会 EPERM；统一指到工程可写目录
  if [ -z "${HVIGOR_USER_HOME:-}" ]; then
    export HVIGOR_USER_HOME="${CARBON_HVIGOR_HOME:-${TMPDIR:-/tmp}/carbon-hvigor-home}"
  fi
  mkdir -p "$HVIGOR_USER_HOME" 2>/dev/null || true

  return 0
}
