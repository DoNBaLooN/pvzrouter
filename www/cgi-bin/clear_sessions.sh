#!/bin/ash

CONFIG_FILE="/etc/config/wifi_auth"
SESSIONS_FILE="/tmp/active_sessions.txt"

print_header() {
    echo "Content-Type: text/html; charset=utf-8"
    echo
}

load_config() {
    if [ -f "$CONFIG_FILE" ]; then
        # shellcheck disable=SC1090
        . "$CONFIG_FILE"
    fi
    [ -n "$admin_macs" ] || admin_macs=''
}

restore_admin_macs() {
    local mac
    for mac in $admin_macs; do
        nodogsplashctl add "$mac" >/dev/null 2>&1
    done
}

main() {
    load_config
    nodogsplashctl clear >/dev/null 2>&1
    : > "$SESSIONS_FILE"
    restore_admin_macs

    print_header
    cat <<HTML
<!DOCTYPE html>
<html lang="ru">
<head>
    <meta charset="utf-8">
    <title>Сессии очищены</title>
</head>
<body>
    <h1>Все активные пользователи отключены.</h1>
    <p><a href="/admin.html">Вернуться назад</a></p>
</body>
</html>
HTML
}

main "$@"
