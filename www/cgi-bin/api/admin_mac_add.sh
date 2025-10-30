#!/bin/ash
. /www/cgi-bin/api/common.sh

ensure_session_store
BODY="$(read_body)"
MAC_RAW="$(parse_json_string mac "$BODY")"
MAC="$(uppercase_mac "$MAC_RAW")"
if [ -z "$MAC" ]; then
    send_json '{"ok":false,"msg":"MAC пуст"}'
    exit 0
fi
if ! printf '%s' "$MAC" | grep -Eq '^[0-9A-F]{2}(:[0-9A-F]{2}){5}$'; then
    send_json '{"ok":false,"msg":"Неверный формат MAC"}'
    exit 0
fi
add_whitelist_mac "$MAC"
nodogsplashctl add "$MAC" >/dev/null 2>&1
MESSAGE="$(json_escape "MAC ${MAC} добавлен в whitelist")"
send_json "{\"ok\":true,\"msg\":\"${MESSAGE}\"}"
