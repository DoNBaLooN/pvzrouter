#!/bin/ash

set -eu

CONFIG="wifi_auth.portal"
SESSIONS_FILE="/tmp/active_sessions.txt"

hostname=$(uci -q get system.@system[0].hostname 2>/dev/null)
[ -n "$hostname" ] || hostname=$(uname -n)

if /etc/init.d/nodogsplash status >/dev/null 2>&1; then
  nds_up=1
else
  nds_up=0
fi

active_clients=0
remaining_sum=0
remaining_max=0
now=$(date +%s)
if [ -f "$SESSIONS_FILE" ]; then
  while IFS='|' read -r mac expiry ip created; do
    [ -n "$mac" ] || continue
    if [ "$expiry" -gt "$now" ] 2>/dev/null; then
      remaining=$((expiry - now))
      remaining_sum=$((remaining_sum + remaining))
      [ "$remaining" -gt "$remaining_max" ] && remaining_max=$remaining
      active_clients=$((active_clients + 1))
    fi
  done <"$SESSIONS_FILE"
fi

whitelist_count=$(uci -q show $CONFIG.admin_mac_whitelist 2>/dev/null | sed -n 's/.*=//p' | wc -l | tr -d ' ')
[ -n "$whitelist_count" ] || whitelist_count=0

total_logins=$(uci -q get $CONFIG.total_logins 2>/dev/null)
[ -n "$total_logins" ] || total_logins=0

code_updates=$(uci -q get $CONFIG.code_updates_total 2>/dev/null)
[ -n "$code_updates" ] || code_updates=0

last_update_ts=$(uci -q get $CONFIG.updated_unix 2>/dev/null)
[ -n "$last_update_ts" ] || last_update_ts=0

cat <<EOF_METRICS
Content-Type: text/plain; charset=utf-8

wifi_auth_nds_up{router="$hostname"} $nds_up
wifi_auth_active_clients $active_clients
wifi_auth_whitelist_count $whitelist_count
wifi_auth_total_logins $total_logins
wifi_auth_code_updates_total $code_updates
wifi_auth_last_update_timestamp $last_update_ts
wifi_auth_session_remaining_seconds_sum $remaining_sum
wifi_auth_session_remaining_seconds_max $remaining_max
EOF_METRICS
