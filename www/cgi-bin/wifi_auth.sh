#!/bin/ash

CONFIG_FILE="/etc/config/wifi_auth"
SESSIONS_FILE="/tmp/active_sessions.txt"
SUCCESS_PAGE="/www/success.html"

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
    else
        code='0000'
        duration='60'
        nds_enabled='0'
        admin_macs=''
    fi
    case "$duration" in
        ''|*[!0-9]*) duration='60' ;;
    esac
    [ -n "$code" ] || code='0000'
    [ -n "$admin_macs" ] || admin_macs=''
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
                FORM_CODE="$value"
                ;;
        esac
    done
}

fail() {
    print_header
    cat <<HTML
<!DOCTYPE html>
<html lang="ru">
<head>
    <meta charset="utf-8">
    <title>Ошибка авторизации</title>
</head>
<body>
    <h1>Доступ отклонён</h1>
    <p>$1</p>
    <p><a href="/index.html">Повторить попытку</a></p>
</body>
</html>
HTML
    exit 0
}

allow_client() {
    local tmp now expires mac_upper duration_minutes
    [ -n "$CLIENT_MAC" ] || return 1
    now="$(date +%s)"
    duration_minutes=$duration
    expires=$((now + duration_minutes * 60))
    touch "$SESSIONS_FILE"
    tmp="$(mktemp /tmp/wifi_session.XXXXXX 2>/dev/null)"
    if [ -n "$tmp" ] && [ -w "$(dirname "$tmp")" ]; then
        grep -iv "^$CLIENT_MAC " "$SESSIONS_FILE" 2>/dev/null > "$tmp"
        echo "$CLIENT_MAC $expires" >> "$tmp"
        mv "$tmp" "$SESSIONS_FILE"
    else
        grep -iv "^$CLIENT_MAC " "$SESSIONS_FILE" 2>/dev/null > "$SESSIONS_FILE.tmp"
        echo "$CLIENT_MAC $expires" >> "$SESSIONS_FILE.tmp"
        mv "$SESSIONS_FILE.tmp" "$SESSIONS_FILE"
    fi
    nodogsplashctl add "$CLIENT_MAC" >/dev/null 2>&1
    for mac_upper in $admin_macs; do
        nodogsplashctl add "$mac_upper" >/dev/null 2>&1
    done
}

main() {
    load_config

    [ "$REQUEST_METHOD" = "POST" ] || fail "Некорректный запрос."

    parse_post

    [ -n "$FORM_CODE" ] || fail "Не указан код доступа."

    CLIENT_MAC="$(echo "$HTTP_X_NDS_MAC" | tr '[:lower:]' '[:upper:]')"
    [ -n "$CLIENT_MAC" ] || CLIENT_MAC="$(echo "$HTTP_NDS_MAC" | tr '[:lower:]' '[:upper:]')"

    case "$FORM_CODE" in
        *"'"*) fail "Код содержит недопустимые символы." ;;
    esac

    if [ "$FORM_CODE" = "$code" ]; then
        allow_client || fail "Не удалось идентифицировать устройство."
        print_header
        if [ -f "$SUCCESS_PAGE" ]; then
            cat "$SUCCESS_PAGE"
        else
            cat <<HTML
<!DOCTYPE html>
<html lang="ru">
<head>
    <meta charset="utf-8">
    <title>Доступ предоставлен</title>
</head>
<body>
    <h1>Интернет активирован</h1>
</body>
</html>
HTML
        fi
    else
        fail "Введён неверный код доступа."
    fi
}

main "$@"
