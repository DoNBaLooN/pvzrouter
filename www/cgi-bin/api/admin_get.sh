#!/bin/ash
. /www/cgi-bin/api/common.sh

ensure_config
ensure_session_store
CODE="$(get_config_value code)"
DURATION="$(get_config_value duration)"
NDS_ENABLED="$(get_nds_enabled_flag)"
if /etc/init.d/nodogsplash status >/dev/null 2>&1; then
    NDS_RUNNING=1
else
    NDS_RUNNING=0
fi
CLIENTS="$(count_sessions)"
JSON="{\"ok\":true,\"code\":\"$(json_escape "$CODE")\",\"duration\":${DURATION},\"nds_enabled\":${NDS_ENABLED},\"nds_running\":${NDS_RUNNING},\"sessions\":${CLIENTS}}"
send_json "$JSON"
