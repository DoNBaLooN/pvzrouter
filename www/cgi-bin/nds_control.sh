#!/bin/ash

CONFIG_FILE="/etc/config/wifi_auth"

authorize() {
    return 0
}

print_header() {
    echo "Content-Type: text/html; charset=utf-8"
    echo
}

url_decode() {
    local data="${1//+/ }"
    printf '%b' "${data//%/\\x}"
}

load_config() {
    if [ -f "$CONFIG_FILE" ]; then
        # shellcheck disable=SC1090
        . "$CONFIG_FILE"
    fi
    [ -n "$nds_enabled" ] || nds_enabled='0'
    [ -n "$admin_macs" ] || admin_macs=''
    [ -n "$code" ] || code='0000'
    [ -n "$duration" ] || duration='60'
}

write_config() {
    cat <<CFG > "$CONFIG_FILE"
code='$code'
duration='$duration'
nds_enabled='$nds_enabled'
admin_macs='$admin_macs'
CFG
}

parse_post() {
    local raw payload key value
    raw="$(cat)"
    IFS='&' set -- $raw
    unset IFS
    for payload in "$@"; do
        key=${payload%%=*}
        value=${payload#*=}
        [ "$key" = "$payload" ] && value=""
        key="$(url_decode "$key")"
        value="$(url_decode "$value")"
        case "$key" in
            action)
                ACTION="$value"
                ;;
            mac)
                ADMIN_MAC_RAW="$value"
                ;;
        esac
    done
}

normalize_mac() {
    echo "$1" | tr '[:lower:]' '[:upper:]'
}

add_admin_mac() {
    local mac list
    mac="$(normalize_mac "$ADMIN_MAC_RAW")"
    echo "$mac" | grep -Eq '^[A-F0-9]{2}(:[A-F0-9]{2}){5}$' || return 1
    list=" $admin_macs "
    case "$list" in
        *" $mac "*)
            :
            ;;
        *)
            if [ -n "$admin_macs" ]; then
                admin_macs="$admin_macs $mac"
            else
                admin_macs="$mac"
            fi
            ;;
    esac
    nodogsplashctl add "$mac" >/dev/null 2>&1
    write_config
    return 0
}

set_portal_state() {
    case "$1" in
        on)
            /etc/init.d/nodogsplash start >/dev/null 2>&1
            /etc/init.d/nodogsplash enable >/dev/null 2>&1
            nds_enabled='1'
            write_config
            ;;
        off)
            /etc/init.d/nodogsplash stop >/dev/null 2>&1
            /etc/init.d/nodogsplash disable >/dev/null 2>&1
            nds_enabled='0'
            write_config
            ;;
    esac
}

restart_nds() {
    /etc/init.d/nodogsplash restart >/dev/null 2>&1
}

print_response() {
    local message="$1"
    print_header
    cat <<HTML
<!DOCTYPE html>
<html lang="ru">
<head>
    <meta charset="utf-8">
    <title>Управление NDS</title>
</head>
<body>
    <h1>$message</h1>
    <p><a href="/admin.html">Вернуться в панель управления</a></p>
</body>
</html>
HTML
}

main() {
    authorize || exit 1
    [ "$REQUEST_METHOD" = "POST" ] || { print_response "Неверный метод запроса."; exit 0; }

    load_config
    parse_post

    case "$ACTION" in
        enable)
            set_portal_state on
            print_response "NoDogSplash запущен и включён."
            ;;
        disable)
            set_portal_state off
            print_response "NoDogSplash остановлен и отключён."
            ;;
        restart)
            restart_nds
            print_response "NoDogSplash перезапущен."
            ;;
        add_admin_mac)
            if add_admin_mac; then
                print_response "MAC-адрес добавлен в белый список."
            else
                print_response "Ошибка: проверьте формат MAC-адреса."
            fi
            ;;
        *)
            print_response "Неизвестная команда."
            ;;
    esac
}

main "$@"
