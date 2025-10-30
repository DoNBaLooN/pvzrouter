#!/bin/ash
. /www/cgi-bin/api/common.sh

ensure_config
ensure_session_store
if /etc/init.d/nodogsplash status >/dev/null 2>&1; then
    RUNNING=1
else
    RUNNING=0
fi
if /etc/init.d/nodogsplash enabled >/dev/null 2>&1; then
    ENABLED=1
else
    ENABLED=0
fi
CLIENTS=$(nodogsplashctl clients 2>/dev/null | grep -c '^[0-9A-Fa-f:][0-9A-Fa-f:]*')
if [ -z "$CLIENTS" ]; then
    CLIENTS=0
fi
SESSIONS="$(count_sessions)"
JSON="{\"ok\":true,\"nds_running\":${RUNNING},\"nds_enabled\":${ENABLED},\"clients\":${CLIENTS},\"tracked_sessions\":${SESSIONS}}"
send_json "$JSON"
