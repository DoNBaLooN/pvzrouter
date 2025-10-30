#!/bin/ash

CONFIG_FILE="/etc/config/wifi_auth"
SESSIONS_FILE="/tmp/active_sessions.txt"

load_config() {
    if [ -f "$CONFIG_FILE" ]; then
        # shellcheck disable=SC1090
        . "$CONFIG_FILE"
    fi
    [ -n "$admin_macs" ] || admin_macs=''
}

refresh_admin_macs() {
    local mac
    for mac in $admin_macs; do
        nodogsplashctl add "$mac" >/dev/null 2>&1
    done
}

cleanup_sessions() {
    local now tmp mac expiry
    [ -f "$SESSIONS_FILE" ] || return
    now="$(date +%s)"
    tmp="$(mktemp /tmp/nds_sessions.XXXXXX 2>/dev/null)"
    if [ -z "$tmp" ]; then
        tmp="$SESSIONS_FILE.tmp"
    fi
    : > "$tmp"
    while read -r mac expiry; do
        [ -n "$mac" ] || continue
        case "$expiry" in
            ''|*[!0-9]*)
                nodogsplashctl del "$mac" >/dev/null 2>&1
                continue
                ;;
        esac
        if [ "$expiry" -le "$now" ]; then
            nodogsplashctl del "$mac" >/dev/null 2>&1
        else
            echo "$mac $expiry" >> "$tmp"
        fi
    done < "$SESSIONS_FILE"
    mv "$tmp" "$SESSIONS_FILE"
}

main() {
    load_config
    cleanup_sessions
    refresh_admin_macs
}

main "$@"
