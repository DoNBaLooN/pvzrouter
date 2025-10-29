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

control_nodogsplash() {
    local action="$1"
    if [ -x /etc/init.d/nodogsplash ]; then
        /etc/init.d/nodogsplash "$action" >/dev/null 2>&1 && return 0
    fi
    if command -v service >/dev/null 2>&1; then
        service nodogsplash "$action" >/dev/null 2>&1 && return 0
    fi
    return 1
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
        body { font-family: Arial, sans-serif; background: #f5f5f5; color: #1f2937; display: flex; justify-content: center; align-items: center; height: 100vh; margin: 0; }
        .card { background: #fff; padding: 2rem; border-radius: 12px; box-shadow: 0 12px 32px rgba(15, 23, 42, 0.12); max-width: 420px; width: 100%; text-align: center; }
        h1 { margin-bottom: 1rem; font-size: 1.65rem; }
        p { margin: 0.5rem 0; }
        a { color: #2563eb; text-decoration: none; font-weight: 600; }
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
    STATE="$(extract_param "state")"

    case "$STATE" in
        enable)
            TARGET="1"
            TITLE="Защита включена"
            MESSAGE="Портал авторизации вновь требует ввод кода."
            ACTION="start"
            ;;
        disable)
            TARGET="0"
            TITLE="Защита отключена"
            MESSAGE="Гости могут подключаться без авторизации."
            ACTION="stop"
            ;;
        *)
            respond "Ошибка" "Некорректный параметр. Попробуйте снова."
            ;;
    esac

    if ! uci -q show ${PACKAGE}.${SECTION} >/dev/null 2>&1; then
        uci set ${PACKAGE}.${SECTION}=auth
    fi

    uci set ${PACKAGE}.${SECTION}.enabled="$TARGET"
    uci commit ${PACKAGE}

    control_nodogsplash "$ACTION" || true

    respond "$TITLE" "$MESSAGE"
}

main "$@"
