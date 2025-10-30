#!/bin/ash
. /www/cgi-bin/api/common.sh

ensure_config
BODY="$(read_body)"
ACTION="$(parse_json_string action "$BODY")"
if [ -z "$ACTION" ]; then
    send_json '{"ok":false,"msg":"Не указано действие"}'
    exit 0
fi
case "$ACTION" in
    start)
        if /etc/init.d/nodogsplash start >/dev/null 2>&1; then
            /etc/init.d/nodogsplash enable >/dev/null 2>&1
            CURRENT_CODE="$(get_config_value code)"
            CURRENT_DURATION="$(get_config_value duration)"
            write_config "$CURRENT_CODE" "$CURRENT_DURATION" "1"
            send_json '{"ok":true,"msg":"NoDogSplash запущен"}'
        else
            send_json '{"ok":false,"msg":"Не удалось запустить"}'
        fi
        ;;
    stop)
        if /etc/init.d/nodogsplash stop >/dev/null 2>&1; then
            /etc/init.d/nodogsplash disable >/dev/null 2>&1
            CURRENT_CODE="$(get_config_value code)"
            CURRENT_DURATION="$(get_config_value duration)"
            write_config "$CURRENT_CODE" "$CURRENT_DURATION" "0"
            send_json '{"ok":true,"msg":"NoDogSplash остановлен"}'
        else
            send_json '{"ok":false,"msg":"Не удалось остановить"}'
        fi
        ;;
    *)
        send_json '{"ok":false,"msg":"Неизвестное действие"}'
        ;;
esac
