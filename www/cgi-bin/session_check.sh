#!/bin/ash

set -eu

CONFIG="wifi_auth.portal"
SESSIONS_FILE="/tmp/active_sessions.txt"
LOG_TAG="wifi_auth"

[ -f "$SESSIONS_FILE" ] || exit 0

is_admin_mac() {
  local mac="$1"
  [ -n "$mac" ] || return 1
  uci -q show $CONFIG.admin_mac_whitelist 2>/dev/null | grep -qi "=$mac$"
}

tmp_file="$SESSIONS_FILE.tmp"
now=$(date +%s)
removed=0

>"$tmp_file"
while IFS='|' read -r mac expiry ip created; do
  [ -n "$mac" ] || continue
  if is_admin_mac "$mac"; then
    echo "$mac|$expiry|$ip|$created" >>"$tmp_file"
    continue
  fi
  if [ "$expiry" -gt "$now" ] 2>/dev/null; then
    echo "$mac|$expiry|$ip|$created" >>"$tmp_file"
  else
    removed=$((removed + 1))
    if command -v nodogsplashctl >/dev/null 2>&1; then
      nodogsplashctl deauth "$mac" >/dev/null 2>&1 || true
    elif command -v ndsctl >/dev/null 2>&1; then
      ndsctl deauth "$mac" >/dev/null 2>&1 || true
    fi
  fi
done <"$SESSIONS_FILE"

mv "$tmp_file" "$SESSIONS_FILE"

if [ "$removed" -gt 0 ]; then
  logger -t "$LOG_TAG" "$removed expired sessions removed"
fi
