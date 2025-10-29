#!/bin/sh

SESS_FILE="/tmp/active_sessions.txt"
LOCK_FILE="/var/lock/wifi_auth_sessions.lock"
NOW=$(date +%s)
TMP_FILE="${SESS_FILE}.tmp"
LOCK_HELD=0
CONFIG_ENABLED="$(uci -q get wifi_auth.settings.enabled 2>/dev/null || echo '1')"

[ "$CONFIG_ENABLED" = "1" ] || exit 0

[ -f "$SESS_FILE" ] || exit 0

if command -v lock >/dev/null 2>&1; then
    lock -w 10 "$LOCK_FILE"
    LOCK_HELD=1
elif command -v flock >/dev/null 2>&1; then
    exec 9>"$LOCK_FILE"
    flock -w 10 9 || true
    LOCK_HELD=2
else
    LOCK_HELD=0
fi

trap 'case "${LOCK_HELD:-0}" in 1) lock -u "$LOCK_FILE" 2>/dev/null || true ;; 2) exec 9>&- ;; esac; LOCK_HELD=0' EXIT

: > "$TMP_FILE"

while IFS='|' read -r mac ip expires; do
    [ -n "$mac" ] || continue
    [ -n "$expires" ] || continue
    case "$expires" in
        ''|*[!0-9]*) continue ;;
    esac
    if [ "$expires" -gt "$NOW" ] 2>/dev/null; then
        printf '%s|%s|%s\n' "$mac" "$ip" "$expires" >> "$TMP_FILE"
    else
        if command -v nodogsplashctl >/dev/null 2>&1; then
            nodogsplashctl deauth "$mac" >/dev/null 2>&1 || true
        fi
    fi
done < "$SESS_FILE"

mv "$TMP_FILE" "$SESS_FILE"
