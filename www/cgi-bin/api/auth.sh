#!/bin/ash
. /www/cgi-bin/api/common.sh

ensure_config
ensure_session_store
BODY="$(read_body)"
CODE_INPUT="$(parse_json_string code "$BODY")"
if [ -z "$CODE_INPUT" ]; then
    send_json '{"ok":false,"msg":"Код не указан"}'
    exit 0
fi
EXPECTED="$(get_config_value code)"
DURATION_MINUTES="$(get_config_value duration)"
if [ "$CODE_INPUT" != "$EXPECTED" ]; then
    send_json '{"ok":false,"msg":"Неверный код"}'
    exit 0
fi
MAC="$(uppercase_mac "${CLIENTMAC:-}")"
IP_ADDRESS="${REMOTE_ADDR:-}"
if [ -z "$MAC" ]; then
    send_json '{"ok":false,"msg":"MAC не обнаружен"}'
    exit 0
fi
CURRENT_TIME="$(date +%s)"
DURATION_SECONDS=$((DURATION_MINUTES * 60))
EXPIRY=$((CURRENT_TIME + DURATION_SECONDS))
append_session "$MAC" "$EXPIRY"
nodogsplashctl add "$MAC" >/dev/null 2>&1
MESSAGE="$(json_escape "Доступ предоставлен на ${DURATION_MINUTES} мин")"
send_json "{\"ok\":true,\"msg\":\"${MESSAGE}\",\"duration\":${DURATION_MINUTES},\"ip\":\"$(json_escape "$IP_ADDRESS")\"}"
