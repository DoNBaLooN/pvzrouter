#!/bin/ash

CONFIG_FILE="/etc/config/wifi_auth"

authorize() {
    # Хук для базовой аутентификации (можно расширить при необходимости)
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
            code)
                NEW_CODE="$value"
                ;;
            duration)
                NEW_DURATION="$value"
                ;;
        esac
    done
}

validate() {
    [ -n "$NEW_CODE" ] || return 1
    [ -n "$NEW_DURATION" ] || return 1
    echo "$NEW_CODE" | grep -Eq '^[A-Za-z0-9_-]{1,32}$' || return 1
    echo "$NEW_DURATION" | grep -Eq '^[0-9]{1,4}$' || return 1
    if [ "$NEW_DURATION" -lt 1 ] || [ "$NEW_DURATION" -gt 1440 ]; then
        return 1
    fi
    return 0
}

print_response() {
    local message="$1"
    print_header
    cat <<HTML
<!DOCTYPE html>
<html lang="ru">
<head>
    <meta charset="utf-8">
    <title>Обновление параметров</title>
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

    if validate; then
        code="$NEW_CODE"
        duration="$NEW_DURATION"
        write_config
        print_response "Параметры успешно обновлены."
    else
        print_response "Ошибка: проверьте введённые данные."
    fi
}

main "$@"
