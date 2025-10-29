#!/bin/sh

set -eu

SESS_FILE="/tmp/active_sessions.txt"
LOCK_FILE="/var/lock/wifi_auth_sessions.lock"
LOCK_HELD=0

acquire_lock() {
    if command -v lock >/dev/null 2>&1; then
        lock -w 10 "$LOCK_FILE"
        LOCK_HELD=1
    elif command -v flock >/dev/null 2>&1; then
        exec 9>"$LOCK_FILE"
        flock -w 10 9 || true
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

respond() {
    cat <<HTML
Content-Type: text/html; charset=utf-8
Cache-Control: no-store

<!DOCTYPE html>
<html lang="ru">
<head>
    <meta charset="UTF-8">
    <title>Сессии очищены</title>
    <style>
        body { font-family: Arial, sans-serif; background: #fff; color: #111; display: flex; justify-content: center; align-items: center; height: 100vh; margin: 0; }
        .card { background: #f8fafc; padding: 2rem; border-radius: 10px; box-shadow: 0 4px 12px rgba(0,0,0,0.08); text-align: center; max-width: 420px; width: 100%; }
        h1 { margin-bottom: 1rem; font-size: 1.6rem; }
        p { margin: 0.5rem 0; }
        a { color: #2563eb; text-decoration: none; font-weight: bold; }
        a:hover { text-decoration: underline; }
    </style>
</head>
<body>
    <div class="card">
        <h1>Все пользователи отключены</h1>
        <p>Активные сессии очищены.</p>
        <p><a href="/admin.html">Вернуться в панель</a></p>
    </div>
</body>
</html>
HTML
    exit 0
}

main() {
    acquire_lock
    if [ -f "$SESS_FILE" ]; then
        while IFS='|' read -r mac _; do
            [ -n "$mac" ] || continue
            if command -v nodogsplashctl >/dev/null 2>&1; then
                nodogsplashctl deauth "$mac" >/dev/null 2>&1 || true
            fi
        done < "$SESS_FILE"
        : > "$SESS_FILE"
    else
        : > "$SESS_FILE"
    fi
    release_lock
    respond
}

trap release_lock EXIT
main "$@"
