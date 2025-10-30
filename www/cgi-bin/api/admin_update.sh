#!/bin/ash
. /www/cgi-bin/api/common.sh

ensure_config
BODY="$(read_body)"
NEW_CODE="$(parse_json_string code "$BODY")"
NEW_DURATION="$(parse_json_number duration "$BODY")"
if [ -z "$NEW_CODE" ]; then
    send_json '{"ok":false,"msg":"Код пуст"}'
    exit 0
fi
if [ -z "$NEW_DURATION" ]; then
    send_json '{"ok":false,"msg":"Некорректная длительность"}'
    exit 0
fi
if [ "$NEW_DURATION" -lt 5 ] || [ "$NEW_DURATION" -gt 720 ]; then
    send_json '{"ok":false,"msg":"Допустимо от 5 до 720 минут"}'
    exit 0
fi
CURRENT_ENABLED="$(get_nds_enabled_flag)"
write_config "$NEW_CODE" "$NEW_DURATION" "$CURRENT_ENABLED"
MESSAGE="$(json_escape "Параметры обновлены")"
send_json "{\"ok\":true,\"msg\":\"${MESSAGE}\",\"code\":\"$(json_escape "$NEW_CODE")\",\"duration\":${NEW_DURATION}}"
