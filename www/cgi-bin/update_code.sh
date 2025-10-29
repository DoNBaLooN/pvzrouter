#!/bin/sh

set -eu

PACKAGE="wifi_auth"
SECTION="settings"

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
                IFS="$old_ifs"
                printf '%s' "$value"
                return 0
                ;;
        esac
    done
    IFS="$old_ifs"
    printf ''
}

respond() {
    local title="$1" message="$2"
    cat <<HTML
Content-Type: text/html; charset=utf-8
Cache-Control: no-store

<!DOCTYPE html>
<html lang="ru">
<head>
    <meta charset="UTF-8">
    <title>${title}</title>
    <style>
        body { font-family: Arial, sans-serif; background: #f5f5f5; color: #333; display: flex; justify-content: center; align-items: center; height: 100vh; margin: 0; }
        .card { background: #fff; padding: 2rem; border-radius: 8px; box-shadow: 0 2px 8px rgba(0,0,0,0.1); max-width: 420px; width: 100%; text-align: center; }
        h1 { font-size: 1.6rem; margin-bottom: 1rem; }
        p { margin: 0.5rem 0; }
        a { color: #2563eb; text-decoration: none; font-weight: bold; }
        a:hover { text-decoration: underline; }
    </style>
</head>
<body>
    <div class="card">
        <h1>${title}</h1>
        <p>${message}</p>
        <p><a href="/admin.html">Вернуться в панель</a></p>
    </div>
</body>
</html>
HTML
    exit 0
}

main() {
    read_post
    NEW_CODE="$(extract_param "code")"
    NEW_DURATION="$(extract_param "duration")"

    [ -n "$NEW_CODE" ] || respond "Ошибка" "Код не может быть пустым."
    [ -n "$NEW_DURATION" ] || respond "Ошибка" "Укажите длительность доступа."

    case "$NEW_DURATION" in
        ''|*[!0-9]*) respond "Ошибка" "Длительность должна быть числом." ;;
    esac

    if [ "$NEW_DURATION" -lt 1 ] 2>/dev/null; then
        respond "Ошибка" "Минимальная длительность — 1 минута."
    fi

    if [ "$NEW_DURATION" -gt 720 ] 2>/dev/null; then
        respond "Ошибка" "Максимальная длительность — 720 минут (12 часов)."
    fi

    if ! uci -q show ${PACKAGE}.${SECTION} >/dev/null 2>&1; then
        uci set ${PACKAGE}.${SECTION}=auth
    fi

    uci set ${PACKAGE}.${SECTION}.code="$NEW_CODE"
    uci set ${PACKAGE}.${SECTION}.duration="$NEW_DURATION"
    uci set ${PACKAGE}.${SECTION}.updated="$(date '+%Y-%m-%d %H:%M')"
    uci commit ${PACKAGE}

    respond "Сохранено" "Новые параметры успешно применены."
}

main "$@"
