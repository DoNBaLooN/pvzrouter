#!/bin/ash
. /www/cgi-bin/api/common.sh

ensure_session_store
NOW="$(date +%s)"
TMP_FILE="${SESSION_FILE}.tmp"
: > "$TMP_FILE"
if [ -f "$SESSION_FILE" ]; then
    while IFS=' ' read -r MAC EXPIRY; do
        [ -z "$MAC" ] && continue
        MAC_UP="$(uppercase_mac "$MAC")"
        if mac_in_whitelist "$MAC_UP"; then
            printf '%s %s\n' "$MAC_UP" "$EXPIRY" >> "$TMP_FILE"
            continue
        fi
        if [ "$EXPIRY" -gt "$NOW" ] 2>/dev/null; then
            printf '%s %s\n' "$MAC_UP" "$EXPIRY" >> "$TMP_FILE"
        else
            nodogsplashctl del "$MAC_UP" >/dev/null 2>&1
        fi
    done < "$SESSION_FILE"
fi
mv "$TMP_FILE" "$SESSION_FILE"
