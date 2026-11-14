#!/usr/bin/env bash
# 打印当前手机可用的地址（IP 会变，每次用之前跑一下）
set -euo pipefail
PORT="${1:-8899}"
TOKEN="$(sed -n 's/.*令牌: \([A-Za-z0-9_-]*\).*/\1/p' /tmp/carbon-remote.log 2>/dev/null | head -1)"
IP="$(ipconfig getifaddr en0 2>/dev/null || true)"
[ -n "$IP" ] || { echo "en0 没有 IPv4 地址（Wi-Fi 断了？）" >&2; exit 1; }
[ -n "$TOKEN" ] || { echo "读不到令牌，服务起了吗？ tail /tmp/carbon-remote.log" >&2; exit 1; }
echo "http://${IP}:${PORT}/?t=${TOKEN}"
