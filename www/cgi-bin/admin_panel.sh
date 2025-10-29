#!/bin/sh

. /lib/functions.sh 2>/dev/null

CFG_CODE="$(uci -q get wifi_auth.settings.code)"
CFG_DURATION="$(uci -q get wifi_auth.settings.duration)"
CFG_UPDATED="$(uci -q get wifi_auth.settings.updated)"
CFG_ENABLED="$(uci -q get wifi_auth.settings.enabled)"
[ -z "$CFG_CODE" ] && CFG_CODE=""
[ -z "$CFG_DURATION" ] && CFG_DURATION="60"
[ -z "$CFG_UPDATED" ] && CFG_UPDATED="не задано"
[ -z "$CFG_ENABLED" ] && CFG_ENABLED="1"

if [ "$CFG_ENABLED" = "1" ]; then
    PROTECTION_STATUS_TEXT="Включена"
    PROTECTION_STATUS_CLASS="status-tag--on"
    PROTECTION_BUTTON_TEXT="Отключить защиту"
    PROTECTION_BUTTON_CLASS="danger"
    PROTECTION_NEXT_STATE="disable"
    PROTECTION_HINT="Пользователи будут видеть страницу авторизации и вводить код."
else
    PROTECTION_STATUS_TEXT="Выключена"
    PROTECTION_STATUS_CLASS="status-tag--off"
    PROTECTION_BUTTON_TEXT="Включить защиту"
    PROTECTION_BUTTON_CLASS="success"
    PROTECTION_NEXT_STATE="enable"
    PROTECTION_HINT="Гости могут подключаться к Wi‑Fi без ввода кода."
fi

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
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Панель управления Wi-Fi</title>
    <style>
        :root {
            color-scheme: light dark;
            --bg: #f4f5fb;
            --card-bg: rgba(255, 255, 255, 0.82);
            --border: rgba(99, 102, 241, 0.18);
            --primary: #6366f1;
            --primary-dark: #4f46e5;
            --primary-soft: rgba(99, 102, 241, 0.15);
            --danger: #ef4444;
            --warning: #f97316;
            --text-main: #0f172a;
            --text-muted: #6b7280;
            --shadow: 0 22px 45px rgba(99, 102, 241, 0.18);
            --blur: saturate(140%) blur(14px);
        }

        body.theme-night {
            --bg: #0f172a;
            --card-bg: rgba(15, 23, 42, 0.75);
            --border: rgba(129, 140, 248, 0.25);
            --primary: #818cf8;
            --primary-dark: #6366f1;
            --primary-soft: rgba(129, 140, 248, 0.12);
            --danger: #f87171;
            --warning: #fb923c;
            --text-main: #f8fafc;
            --text-muted: #cbd5f5;
            --shadow: 0 25px 45px rgba(15, 23, 42, 0.55);
            --blur: saturate(140%) blur(16px);
            background-image: radial-gradient(circle at top right, rgba(99, 102, 241, 0.35), rgba(37, 99, 235, 0));
        }

        * {
            box-sizing: border-box;
        }

        body {
            margin: 0;
            font-family: 'Inter', 'Segoe UI', sans-serif;
            background: var(--bg);
            color: var(--text-main);
            min-height: 100vh;
            padding: clamp(1.5rem, 3vw, 3rem);
            display: flex;
            justify-content: center;
        }

        .layout {
            width: min(900px, 100%);
            display: flex;
            flex-direction: column;
            gap: 1.5rem;
        }

        header {
            display: flex;
            flex-wrap: wrap;
            gap: 1rem;
            align-items: center;
            justify-content: space-between;
        }

        header h1 {
            margin: 0;
            font-size: clamp(1.6rem, 3.5vw, 2.2rem);
            font-weight: 700;
            letter-spacing: -0.01em;
        }

        .theme-switch {
            display: inline-flex;
            align-items: center;
            gap: 0.75rem;
            padding: 0.6rem 1rem;
            border-radius: 999px;
            border: 1px solid var(--border);
            background: var(--card-bg);
            box-shadow: var(--shadow);
            backdrop-filter: var(--blur);
            cursor: pointer;
            transition: transform 0.2s ease, box-shadow 0.2s ease;
        }

        .theme-switch:hover {
            transform: translateY(-2px);
        }

        .theme-switch__icon {
            width: 2.2rem;
            height: 2.2rem;
            border-radius: 50%;
            background: var(--primary-soft);
            display: grid;
            place-items: center;
            font-size: 1.1rem;
        }

        .theme-switch__label {
            font-weight: 600;
            color: var(--text-main);
            letter-spacing: 0.01em;
        }

        main {
            display: grid;
            gap: 1.5rem;
            grid-template-columns: repeat(auto-fit, minmax(280px, 1fr));
        }

        section {
            background: var(--card-bg);
            border-radius: 26px;
            padding: clamp(1.5rem, 3vw, 2.2rem);
            border: 1px solid var(--border);
            box-shadow: var(--shadow);
            backdrop-filter: var(--blur);
            display: flex;
            flex-direction: column;
            gap: 1.1rem;
        }

        section h2 {
            margin: 0;
            font-size: 1.15rem;
            font-weight: 700;
            color: var(--primary-dark);
        }

        label {
            font-weight: 600;
            font-size: 0.95rem;
            color: var(--text-muted);
        }

        input[type="text"], input[type="number"] {
            width: 100%;
            padding: 0.85rem 1rem;
            border-radius: 16px;
            border: 1px solid var(--border);
            background: rgba(255, 255, 255, 0.6);
            font-size: 1rem;
            color: var(--text-main);
            transition: border 0.2s ease, box-shadow 0.2s ease;
        }

        body.theme-night input[type="text"], body.theme-night input[type="number"] {
            background: rgba(15, 23, 42, 0.65);
        }

        input[type="text"]:focus, input[type="number"]:focus {
            outline: none;
            border-color: var(--primary);
            box-shadow: 0 0 0 4px rgba(99, 102, 241, 0.18);
        }

        .info-line {
            display: flex;
            gap: 0.75rem;
            align-items: center;
            font-size: 0.9rem;
            color: var(--text-muted);
        }

        .status-tag {
            display: inline-flex;
            align-items: center;
            gap: 0.35rem;
            padding: 0.35rem 0.85rem;
            border-radius: 999px;
            font-weight: 600;
            font-size: 0.85rem;
            text-transform: uppercase;
            letter-spacing: 0.04em;
        }

        .status-tag--on {
            background: rgba(22, 163, 74, 0.18);
            color: #166534;
        }

        .status-tag--off {
            background: rgba(239, 68, 68, 0.18);
            color: #b91c1c;
        }

        .hint {
            margin: 0;
            font-size: 0.85rem;
            color: var(--text-muted);
            line-height: 1.4;
        }

        button {
            padding: 0.85rem 1.2rem;
            border-radius: 14px;
            border: none;
            font-weight: 600;
            font-size: 0.98rem;
            cursor: pointer;
            transition: transform 0.2s ease, box-shadow 0.2s ease;
        }

        button.primary {
            background: linear-gradient(135deg, var(--primary) 0%, var(--primary-dark) 100%);
            color: #fff;
        }

        button.secondary {
            background: linear-gradient(135deg, #fbbf24 0%, var(--warning) 100%);
            color: #fff;
        }

        button.danger {
            background: linear-gradient(135deg, #fb7185 0%, var(--danger) 100%);
            color: #fff;
        }

        button.success {
            background: linear-gradient(135deg, #34d399 0%, #059669 100%);
            color: #fff;
        }

        button:hover {
            transform: translateY(-2px);
            box-shadow: 0 18px 28px rgba(99, 102, 241, 0.25);
        }

        .stats {
            display: flex;
            align-items: center;
            gap: 0.75rem;
            font-size: 2.2rem;
            font-weight: 700;
            color: var(--primary-dark);
        }

        .stats span {
            font-size: 0.9rem;
            font-weight: 500;
            color: var(--text-muted);
        }

        .actions {
            display: grid;
            gap: 0.8rem;
        }

        footer {
            text-align: center;
            font-size: 0.85rem;
            color: var(--text-muted);
            margin-top: 0.5rem;
        }

        @media (max-width: 640px) {
            body {
                padding: 1.25rem;
            }

            header {
                gap: 0.75rem;
            }

            main {
                grid-template-columns: 1fr;
            }
        }
    </style>
</head>
<body class="theme-day">
    <div class="layout">
        <header>
            <h1>Панель управления Wi-Fi</h1>
            <button id="themeToggle" class="theme-switch" type="button">
                <span class="theme-switch__icon" aria-hidden="true">🌞</span>
                <span class="theme-switch__label">Дневная тема</span>
            </button>
        </header>
        <main>
            <section>
                <h2>Защита портала</h2>
                <div class="info-line">
                    <strong>Статус:</strong>
                    <span class="status-tag ${PROTECTION_STATUS_CLASS}">${PROTECTION_STATUS_TEXT}</span>
                </div>
                <p class="hint">${PROTECTION_HINT}</p>
                <form method="post" action="/cgi-bin/toggle_protection.sh">
                    <input type="hidden" name="state" value="${PROTECTION_NEXT_STATE}">
                    <button class="${PROTECTION_BUTTON_CLASS}" type="submit">${PROTECTION_BUTTON_TEXT}</button>
                </form>
            </section>
            <section>
                <h2>Код доступа</h2>
                <form method="post" action="/cgi-bin/update_code.sh">
                    <label for="code">Текущий код дня</label>
                    <input id="code" name="code" type="text" value="${CFG_CODE}" required>
                    <label for="duration">Длительность доступа (мин)</label>
                    <input id="duration" name="duration" type="number" min="1" max="720" value="${CFG_DURATION}" required>
                    <div class="info-line">Дата последнего изменения: ${LAST_UPDATED_FMT}</div>
                    <button class="primary" type="submit">Сохранить изменения</button>
                </form>
            </section>
            <section>
                <h2>Состояние подключений</h2>
                <div class="stats">${ACTIVE_COUNT}<span>активных клиентов</span></div>
                <div class="actions">
                    <form method="post" action="/cgi-bin/clear_sessions.sh">
                        <button class="danger" type="submit">Очистить все сессии</button>
                    </form>
                    <form method="post" action="/cgi-bin/restart_portal.sh">
                        <button class="secondary" type="submit">Перезапустить авторизацию</button>
                    </form>
                </div>
            </section>
        </main>
        <footer>VlessWB © $(date '+%Y')</footer>
    </div>
    <script>
        (function() {
            const body = document.body;
            const toggle = document.getElementById('themeToggle');
            const label = toggle.querySelector('.theme-switch__label');
            const icon = toggle.querySelector('.theme-switch__icon');
            const THEMES = {
                day: {
                    className: 'theme-day',
                    label: 'Дневная тема',
                    icon: '🌞'
                },
                night: {
                    className: 'theme-night',
                    label: 'Ночная тема',
                    icon: '🌜'
                }
            };

            const storedTheme = localStorage.getItem('adminTheme');
            if (storedTheme === THEMES.night.className) {
                body.classList.remove(THEMES.day.className);
                body.classList.add(THEMES.night.className);
                label.textContent = THEMES.night.label;
                icon.textContent = THEMES.night.icon;
            }

            toggle.addEventListener('click', function() {
                const isNight = body.classList.toggle(THEMES.night.className);
                if (isNight) {
                    body.classList.remove(THEMES.day.className);
                    label.textContent = THEMES.night.label;
                    icon.textContent = THEMES.night.icon;
                    localStorage.setItem('adminTheme', THEMES.night.className);
                } else {
                    body.classList.add(THEMES.day.className);
                    label.textContent = THEMES.day.label;
                    icon.textContent = THEMES.day.icon;
                    localStorage.setItem('adminTheme', THEMES.day.className);
                }
            });
        })();
    </script>
</body>
</html>
HTML
