#!/bin/sh

set -eu

restart_nds() {
    if [ -x /etc/init.d/nodogsplash ]; then
        /etc/init.d/nodogsplash restart >/dev/null 2>&1 && return 0
    fi
    if command -v service >/dev/null 2>&1; then
        service nodogsplash restart >/dev/null 2>&1 && return 0
    fi
    if command -v nodogsplashctl >/dev/null 2>&1; then
        nodogsplashctl reload >/dev/null 2>&1 && return 0
    fi
    return 1
}

if restart_nds; then
    STATUS_TITLE="Перезапуск выполнен"
    STATUS_MESSAGE="Портал авторизации перезапущен."
else
    STATUS_TITLE="Ошибка"
    STATUS_MESSAGE="Не удалось перезапустить NoDogSplash. Проверьте журнал."
fi

cat <<HTML
Content-Type: text/html; charset=utf-8
Cache-Control: no-store

<!DOCTYPE html>
<html lang="ru">
<head>
    <meta charset="UTF-8">
    <title>${STATUS_TITLE}</title>
    <style>
        body { font-family: Arial, sans-serif; background: #f8fafc; color: #111827; display: flex; justify-content: center; align-items: center; height: 100vh; margin: 0; }
        .card { background: #fff; padding: 2rem; border-radius: 10px; box-shadow: 0 4px 14px rgba(15,23,42,0.12); max-width: 420px; width: 100%; text-align: center; }
        h1 { margin-bottom: 1rem; font-size: 1.6rem; }
        p { margin: 0.5rem 0; }
        a { color: #2563eb; text-decoration: none; font-weight: bold; }
        a:hover { text-decoration: underline; }
    </style>
</head>
<body>
    <div class="card">
        <h1>${STATUS_TITLE}</h1>
        <p>${STATUS_MESSAGE}</p>
        <p><a href="/admin.html">Вернуться в панель</a></p>
    </div>
</body>
</html>
HTML
