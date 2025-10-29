#!/bin/sh

. /lib/functions.sh 2>/dev/null

CFG_CODE="$(uci -q get wifi_auth.settings.code)"
CFG_DURATION="$(uci -q get wifi_auth.settings.duration)"
CFG_UPDATED="$(uci -q get wifi_auth.settings.updated)"
[ -z "$CFG_CODE" ] && CFG_CODE=""
[ -z "$CFG_DURATION" ] && CFG_DURATION="60"
[ -z "$CFG_UPDATED" ] && CFG_UPDATED="не задано"

SESS_FILE="/tmp/active_sessions.txt"
if [ -s "$SESS_FILE" ]; then
    ACTIVE_COUNT=$(grep -cv '^[[:space:]]*$' "$SESS_FILE")
else
    ACTIVE_COUNT=0
fi

LAST_UPDATED_FMT="$CFG_UPDATED"
if [ -n "$CFG_UPDATED" ] && [ "$CFG_UPDATED" != "не задано" ]; then
    LAST_UPDATED_FMT="$(date -d "$CFG_UPDATED" '+%d.%m.%Y %H:%M' 2>/dev/null || echo "$CFG_UPDATED")"
fi

cat <<HTML
Content-Type: text/html; charset=utf-8
Cache-Control: no-store

<!DOCTYPE html>
<html lang="ru">
<head>
    <meta charset="UTF-8">
    <title>Панель управления Wi-Fi</title>
    <style>
        body { font-family: Arial, sans-serif; background: #f0f2f5; color: #333; margin: 0; padding: 0; }
        header { background: #111827; color: #fff; padding: 1.5rem; text-align: center; }
        main { max-width: 720px; margin: 0 auto; padding: 2rem 1rem 3rem; }
        section { background: #fff; padding: 1.5rem; border-radius: 10px; box-shadow: 0 4px 12px rgba(0,0,0,0.08); margin-bottom: 1.5rem; }
        h1 { margin: 0; font-size: 1.8rem; }
        label { display: block; font-weight: bold; margin-top: 1rem; }
        input[type="text"], input[type="number"] { width: 100%; padding: 0.6rem; border: 1px solid #ccc; border-radius: 6px; font-size: 1rem; }
        button { margin-top: 1.2rem; padding: 0.8rem 1.5rem; border: none; border-radius: 6px; font-size: 1rem; cursor: pointer; }
        button.primary { background: #2563eb; color: #fff; }
        button.secondary { background: #f97316; color: #fff; }
        button.danger { background: #dc2626; color: #fff; }
        .footer { text-align: center; color: #6b7280; font-size: 0.9rem; margin-top: 2rem; }
        form { margin: 0; }
        .info { margin-top: 0.3rem; color: #555; }
        .actions { display: flex; flex-direction: column; gap: 1rem; }
        @media (min-width: 560px) {
            .actions { flex-direction: row; }
            .actions form { flex: 1; }
        }
    </style>
</head>
<body>
    <header>
        <h1>Панель управления Wi-Fi</h1>
    </header>
    <main>
        <section>
            <form method="post" action="/cgi-bin/update_code.sh">
                <label for="code">Текущий код дня</label>
                <input id="code" name="code" type="text" value="${CFG_CODE}" required>
                <label for="duration">Длительность доступа (мин)</label>
                <input id="duration" name="duration" type="number" min="1" max="720" value="${CFG_DURATION}" required>
                <p class="info">Дата последнего изменения: ${LAST_UPDATED_FMT}</p>
                <button class="primary" type="submit">Сохранить изменения</button>
            </form>
        </section>
        <section>
            <p><strong>Активных клиентов:</strong> ${ACTIVE_COUNT}</p>
            <div class="actions">
                <form method="post" action="/cgi-bin/clear_sessions.sh">
                    <button class="danger" type="submit">Очистить все сессии</button>
                </form>
                <form method="post" action="/cgi-bin/restart_portal.sh">
                    <button class="secondary" type="submit">Перезапустить авторизацию</button>
                </form>
            </div>
        </section>
        <div class="footer">VlessWB © $(date '+%Y')</div>
    </main>
</body>
</html>
HTML
