#!/usr/bin/env bash
# ---------------------------------------------------------------------------
#  碳迹 · 手机远程 —— 一键抢修
#
#  二维码打不开时跑这个。它会自己判断卡在哪一环并修好：
#    1. 本机服务没起来   → 拉起
#    2. 隧道进程死了     → 重启
#    3. 服务器有僵尸 sshd 占着端口（最常见）→ 清掉再重启
#    4. 模拟器没起来     → 只提示，不自动起（怕打断你正在做的事）
#
#  用法： tools/remote/repair.sh
# ---------------------------------------------------------------------------
set -uo pipefail
WS=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
SSH_PORT=2222
SERVER="root@8.133.220.133"
PLIST="$HOME/Library/LaunchAgents/com.carbon.remote-server.plist"
DOMAIN="dsh.saidao.asia"

TOKEN=$(python3 - "$PLIST" <<'PY' 2>/dev/null
import re,sys
m=re.search(r'<string>--token</string>\s*<string>([^<]+)</string>', open(sys.argv[1]).read())
print(m.group(1) if m else '')
PY
)

say() { printf '  %s\n' "$1"; }

say "① 检查本机投屏服务…"
if curl -s --max-time 4 "http://127.0.0.1:8899/healthz?t=$TOKEN" | grep -q '"ok":true'; then
  say "   正常"
else
  say "   不在 → 拉起"
  launchctl kickstart -k "gui/$(id -u)/com.carbon.remote-server" 2>/dev/null
  sleep 4
fi

say "② 检查隧道进程…"
if pgrep -f "ssh -p $SSH_PORT -N -T" >/dev/null; then
  say "   在跑"
else
  say "   已退出 → 先清服务器僵尸再重启"
  STALE=$(ssh -p $SSH_PORT -o StrictHostKeyChecking=no -o ConnectTimeout=8 $SERVER \
    "ss -lntp 2>/dev/null | grep 127.0.0.1:8899 | grep -oE 'pid=[0-9]+' | cut -d= -f2" 2>/dev/null)
  if [ -n "$STALE" ]; then
    say "   发现僵尸 sshd（pid ${STALE}）→ 清理"
    ssh -p $SSH_PORT -o StrictHostKeyChecking=no $SERVER "kill $STALE" 2>/dev/null
    sleep 2
  fi
  launchctl kickstart -k "gui/$(id -u)/com.carbon.remote-tunnel" 2>/dev/null
fi

say "③ 等待链路恢复（最多 40 秒）…"
for i in $(seq 1 20); do
  C=$(curl -s -o /dev/null -w '%{http_code}' --max-time 8 "https://$DOMAIN/carbon/?t=$TOKEN" 2>/dev/null)
  if [ "$C" = "200" ]; then say "   公网已恢复 (HTTP 200)"; OK=1; break; fi
  sleep 2
done
[ "${OK:-0}" = "1" ] || { say "   仍未恢复（最后状态 ${C}）—— 跑 tools/remote/doctor.sh 看细节"; exit 1; }

say "④ 模拟器状态…"
HDC="/Applications/DevEco-Studio.app/Contents/sdk/default/openharmony/toolchains/hdc"
T=$("$HDC" list targets 2>/dev/null | tr -d '\r' | head -1)
if [ -n "$T" ] && [ "$T" != "[Empty]" ]; then say "   在线（${T}）"
else say "   ⚠️ 离线 —— 执行：tools/emulator.sh start && tools/emulator.sh wait"; fi

echo ""
echo "  可以扫码了： https://$DOMAIN/carbon/?t=$TOKEN"
echo ""
