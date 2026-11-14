#!/usr/bin/env bash
# ---------------------------------------------------------------------------
#  碳迹 · 手机远程 —— 演示前自检
#
#  答辩前几分钟跑一遍，逐项确认「评委扫码能不能用」。
#  任何一项 ❌ 都意味着现场会出问题，先修完再上台。
#
#  用法：
#    tools/remote/doctor.sh              # 完整自检（含公网）
#    tools/remote/doctor.sh --local      # 只查本机（不联网）
# ---------------------------------------------------------------------------
set -uo pipefail

WS=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
PLIST="$HOME/Library/LaunchAgents/com.carbon.remote-server.plist"
TPLIST="$HOME/Library/LaunchAgents/com.carbon.remote-tunnel.plist"
LOCAL_ONLY=${1:-} 
DOMAIN="dsh.saidao.asia"
SERVER="root@8.133.220.133"
SSH_PORT=2222

ok=0; bad=0
pass() { printf '  ✅ %s\n' "$1"; ok=$((ok+1)); }
fail() { printf '  ❌ %s\n' "$1"; bad=$((bad+1)); }
warn() { printf '  ⚠️  %s\n' "$1"; }

echo ""
echo "  碳迹 · 手机远程 —— 演示前自检"
echo "  ──────────────────────────────────────────"

# --- 令牌（二维码里的那把钥匙）--------------------------------------------
TOKEN=""
if [ -f "$PLIST" ]; then
  TOKEN=$(python3 - "$PLIST" <<'PY' 2>/dev/null
import re,sys
s=open(sys.argv[1]).read()
m=re.search(r'<string>--token</string>\s*<string>([^<]+)</string>',s)
print(m.group(1) if m else '')
PY
)
fi
if [ -n "$TOKEN" ]; then
  pass "令牌已固定：${TOKEN}（写在 LaunchAgent 里，重启不变）"
else
  fail "读不到固定令牌 —— LaunchAgent 可能没装，重启后二维码会失效"
fi

# --- LaunchAgent ------------------------------------------------------------
for job in com.carbon.remote-server com.carbon.remote-tunnel; do
  st=$(launchctl print "gui/$(id -u)/$job" 2>/dev/null | awk '/state =/{print $3; exit}')
  if [ "$st" = "running" ]; then pass "$job 在跑"
  else fail "$job 没在跑（launchctl kickstart -k gui/$(id -u)/${job}）"; fi
done

# --- 本机服务 ---------------------------------------------------------------
H=$(curl -s --max-time 4 "http://127.0.0.1:8899/healthz?t=$TOKEN" 2>/dev/null)
if echo "$H" | grep -q '"ok":true'; then
  if echo "$H" | grep -q '"deviceOnline":true'; then
    pass "投屏服务正常，模拟器在线"
  else
    fail "投屏服务在，但设备离线 —— 模拟器没起来？tools/emulator.sh list"
  fi
else
  fail "本机 8899 无响应（投屏服务没起来）"
fi

# --- 模拟器 ---------------------------------------------------------------
HDC="/Applications/DevEco-Studio.app/Contents/sdk/default/openharmony/toolchains/hdc"
if [ -x "$HDC" ]; then
  T=$("$HDC" list targets 2>/dev/null | tr -d '\r' | head -1)
  if [ -n "$T" ] && [ "$T" != "[Empty]" ]; then pass "hdc 看到设备：$T"
  else fail "hdc 没有设备（tools/emulator.sh start && wait）"; fi
fi

# --- 睡眠（演示第一天敌）----------------------------------------------------
SLEEP_HOLD=$(pmset -g 2>/dev/null | grep -E "^ *sleep" | head -1)
if echo "$SLEEP_HOLD" | grep -qi "prevented"; then
  HOLD=${SLEEP_HOLD#*prevented by }; pass "Mac 当前不会睡眠（由 ${HOLD%% *} 保持）"
else
  warn "Mac 可能进入睡眠 —— 睡眠会断隧道，二维码就废了。演示前执行：caffeinate -dims &"
fi

if [ "$LOCAL_ONLY" = "--local" ]; then
  echo "  ──────────────────────────────────────────"
  echo "  本机检查：通过 ${ok}，失败 $bad"
  echo ""
  exit $([ "$bad" -eq 0 ] && echo 0 || echo 1)
fi

# --- 反向隧道（服务器侧看到 8899）-------------------------------------------
TUN=$(ssh -p $SSH_PORT -o StrictHostKeyChecking=no -o ConnectTimeout=8 $SERVER \
      "ss -lnt 2>/dev/null | grep -c 127.0.0.1:8899" 2>/dev/null | tr -d '[:space:]')
if [ "$TUN" = "1" ]; then pass "反向隧道已建立（服务器 127.0.0.1:8899）"
else fail "反向隧道断了（launchctl kickstart -k gui/$(id -u)/com.carbon.remote-tunnel）"; fi

# --- 公网页面 ---------------------------------------------------------------
CODE=$(curl -s -o /dev/null -w '%{http_code}' --max-time 12 "https://$DOMAIN/carbon/?t=$TOKEN" 2>/dev/null)
if [ "$CODE" = "200" ]; then pass "公网页面可访问（https://$DOMAIN/carbon/）"
else fail "公网页面返回 ${CODE}（预期 200）"; fi

CODE_NO=$(curl -s -o /dev/null -w '%{http_code}' --max-time 12 "https://$DOMAIN/carbon/" 2>/dev/null)
if [ "$CODE_NO" = "403" ]; then pass "无令牌访问被拦截（403，正常）"
else warn "无令牌访问返回 ${CODE_NO}（预期 403，注意别把链接外传）"; fi

# --- 证书有效期 -------------------------------------------------------------
DAYS=$(echo | timeout 12 openssl s_client -connect "$DOMAIN:443" -servername "$DOMAIN" 2>/dev/null \
       | openssl x509 -noout -enddate 2>/dev/null \
       | python3 -c "
import sys,datetime,email.utils
s=sys.stdin.read().strip()
if s.startswith('notAfter='):
    d=email.utils.parsedate_to_datetime(s.split('=',1)[1])
    print((d - datetime.datetime.now(datetime.timezone.utc)).days)
" 2>/dev/null)
if [ -n "${DAYS:-}" ] && [ "$DAYS" -gt 14 ]; then pass "TLS 证书还有 $DAYS 天（acme.sh 每天自动续期）"
elif [ -n "${DAYS:-}" ]; then fail "TLS 证书只剩 $DAYS 天，立刻检查 acme.sh 续期"
else warn "证书到期时间取不到（网络问题？）"; fi

echo "  ──────────────────────────────────────────"
if [ "$bad" -eq 0 ]; then
  echo "  结论：全部通过 ✅  可以扫码演示"
  echo ""
  echo "  二维码链接：https://$DOMAIN/carbon/?t=$TOKEN"
else
  echo "  结论：有 $bad 项失败 ❌  先修再上台"
fi
echo ""
exit $([ "$bad" -eq 0 ] && echo 0 || echo 1)
