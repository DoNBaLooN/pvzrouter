#!/bin/sh

set -eu

CONFIG_CODE="$(uci -q get wifi_auth.settings.code 2>/dev/null || echo '')"
CONFIG_DURATION="$(uci -q get wifi_auth.settings.duration 2>/dev/null || echo '60')"
CONFIG_ENABLED="$(uci -q get wifi_auth.settings.enabled 2>/dev/null || echo '1')"
SESS_FILE="/tmp/active_sessions.txt"
LOCK_FILE="/var/lock/wifi_auth_sessions.lock"
LOCK_HELD=0
SUCCESS_PAGE="/www/success.html"

read_post() {
    if [ "${REQUEST_METHOD:-}" = "POST" ]; then
        read -r -n "${CONTENT_LENGTH:-0}" POST_DATA || true
    else
        POST_DATA="${QUERY_STRING:-}"
    fi
}

urldecode() {
    local data="${1//+/ }"
    printf '%b' "${data//%/\\x}"
}

extract_param() {
    local key="$1" pair value="" raw="${POST_DATA:-}" old_ifs="$IFS"
    IFS='&'
    for pair in $raw; do
        case "$pair" in
            ${key}=*)
                value="${pair#${key}=}"
                value="$(urldecode "$value")"
                printf '%s' "$value"
                IFS="$old_ifs"
                return 0
                ;;
        esac
    done
    IFS="$old_ifs"
    printf ''
}

error_page() {
    local message="$1"
    cat <<HTML
Content-Type: text/html; charset=utf-8
Cache-Control: no-store

<!DOCTYPE html>
<html lang="ru">
<head>
    <meta charset="UTF-8">
    <title>Ошибка авторизации</title>
    <style>
        body { font-family: Arial, sans-serif; background: #fff0f0; color: #c0392b; display: flex; justify-content: center; align-items: center; height: 100vh; margin: 0; }
        .card { background: #fff; padding: 2rem; border-radius: 8px; box-shadow: 0 2px 8px rgba(0,0,0,0.1); max-width: 360px; width: 100%; text-align: center; }
        h1 { font-size: 1.6rem; margin-bottom: 1rem; }
        p { margin: 0.5rem 0; color: #6b0000; }
        a { color: #0b5394; text-decoration: none; font-weight: bold; }
        a:hover { text-decoration: underline; }
    </style>
</head>
<body>
    <div class="card">
        <h1>Доступ отклонён</h1>
        <p>${message}</p>
        <p><a href="/index.html">Попробовать ещё раз</a></p>
    </div>
</body>
</html>
HTML
    exit 0
}

serve_success() {
    if [ -f "$SUCCESS_PAGE" ]; then
        printf 'Content-Type: text/html; charset=utf-8\n\n'
        cat "$SUCCESS_PAGE"
    else
        cat <<HTML
Content-Type: text/html; charset=utf-8

<!DOCTYPE html>
<html lang="ru">
<head><meta charset="UTF-8"><title>Доступ предоставлен</title></head>
<body><h1>Доступ предоставлен</h1><p>Интернет открыт.</p></body>
</html>
HTML
    fi
    exit 0
}

identify_client() {
    CLIENT_MAC="${HTTP_NDS_MAC:-}"
    CLIENT_IP="${REMOTE_ADDR:-}"
    [ -z "$CLIENT_MAC" ] && CLIENT_MAC="${HTTP_X_CLIENT_MAC:-}"
    [ -z "$CLIENT_IP" ] && CLIENT_IP="${HTTP_X_FORWARDED_FOR:-}"
    [ -z "$CLIENT_IP" ] && CLIENT_IP="${REMOTE_HOST:-}"
    case "$CLIENT_IP" in
        *',') CLIENT_IP="${CLIENT_IP%%,*}" ;;
    esac
    if [ -z "$CLIENT_MAC" ]; then
        CLIENT_MAC=""
    fi
}

ensure_lock() {
    if command -v lock >/dev/null 2>&1; then
        lock -w 5 "$LOCK_FILE"
        LOCK_HELD=1
    elif command -v flock >/dev/null 2>&1; then
        exec 9>"$LOCK_FILE"
        flock -w 5 9 || true
        LOCK_HELD=2
    else
        LOCK_HELD=0
    fi
}

release_lock() {
    case "${LOCK_HELD:-0}" in
        1) lock -u "$LOCK_FILE" 2>/dev/null || true ;;
        2) exec 9>&- ;;
    esac
    LOCK_HELD=0
}

main() {
    read_post
    identify_client

    if [ -z "$CLIENT_MAC" ]; then
        if [ -n "$CLIENT_IP" ]; then
            CLIENT_MAC="unknown-$(printf '%s' "$CLIENT_IP" | tr '.:' '-')"
        else
            CLIENT_MAC="unknown"
        fi
    fi

    if [ "${CONFIG_ENABLED}" != "1" ]; then
        if command -v nodogsplashctl >/dev/null 2>&1; then
            nodogsplashctl allow "$CLIENT_MAC" >/dev/null 2>&1 || true
        fi
        serve_success
    fi

    INPUT_CODE="$(extract_param "code")"
    [ -z "$INPUT_CODE" ] && error_page "Не указан код доступа."
    [ -z "$CONFIG_CODE" ] && error_page "Код не настроен. Обратитесь к администратору."

    if [ "$INPUT_CODE" != "$CONFIG_CODE" ]; then
        error_page "Неверный код. Попросите сотрудника магазина уточнить код дня."
    fi

    DURATION_MIN=${CONFIG_DURATION:-60}
    case "$DURATION_MIN" in
        ''|*[!0-9]*) DURATION_MIN=60 ;;
    esac

    NOW=$(date +%s)
    EXPIRES=$((NOW + DURATION_MIN * 60))

    if command -v nodogsplashctl >/dev/null 2>&1; then
        nodogsplashctl allow "$CLIENT_MAC" >/dev/null 2>&1 || true
    fi

    mkdir -p "$(dirname "$SESS_FILE")"
    touch "$SESS_FILE"

    ensure_lock

    TMP_FILE="${SESS_FILE}.tmp"
    grep -v "^${CLIENT_MAC}|" "$SESS_FILE" 2>/dev/null > "$TMP_FILE" || true
    printf '%s|%s|%s\n' "$CLIENT_MAC" "${CLIENT_IP:-unknown}" "$EXPIRES" >> "$TMP_FILE"
    mv "$TMP_FILE" "$SESS_FILE"

    release_lock

    serve_success
}

trap release_lock EXIT
main "$@"
