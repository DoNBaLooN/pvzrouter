#!/bin/ash

set -eu

# Ensure system utilities like uci and init scripts are available when the
# script is executed by the web server (which may have a reduced PATH).
export PATH="/sbin:/usr/sbin:/bin:/usr/bin"

CONFIG="wifi_auth.portal"
SESSIONS_FILE="/tmp/active_sessions.txt"

uci_get() {
  uci -q get "$CONFIG.$1" 2>/dev/null || echo ""
}

current_code=$(uci_get code)
current_duration=$(uci_get duration)
last_updated=$(uci_get updated)
nds_enabled=$(uci_get nds_enabled)
[ -n "$current_duration" ] || current_duration=60
[ -n "$last_updated" ] || last_updated="не задано"
[ -n "$nds_enabled" ] || nds_enabled=0

active_clients=0
if [ -f "$SESSIONS_FILE" ]; then
  now=$(date +%s)
  active_clients=$(awk -F'|' -v now="$now" '$2 > now {count++} END {print count+0}' "$SESSIONS_FILE" 2>/dev/null)
fi

if /etc/init.d/nodogsplash status >/dev/null 2>&1; then
  nds_state_label="работает"
else
  nds_state_label="остановлен"
fi

action_label="Включить"
if [ "$nds_enabled" = "1" ]; then
  action_label="Выключить"
fi

admin_mac_entries=$(uci -q show $CONFIG.admin_mac_whitelist 2>/dev/null | sed -n 's/.*=//p')

cat <<HTML
Content-Type: text/html; charset=utf-8

<!DOCTYPE html>
<html lang="ru">
<head>
  <meta charset="UTF-8" />
  <meta name="viewport" content="width=device-width, initial-scale=1.0" />
  <title>Администрирование Wi-Fi портала</title>
  <link rel="stylesheet" href="/css/wifi_auth.css" />
</head>
<body>
  <div class="container">
    <header>
      <h1>Портал управления Wi‑Fi</h1>
      <p>Изменяйте параметры авторизации и управляйте сессиями посетителей</p>
    </header>

    <section class="grid">
      <form method="post" action="/cgi-bin/update_code.sh" class="grid">
        <div>
          <label for="code">Текущий код дня</label>
          <input type="text" id="code" name="code" value="$current_code" required />
        </div>
        <div>
          <label for="duration">Длительность, минут</label>
          <input type="number" id="duration" name="duration" min="1" max="1440" value="$current_duration" required />
        </div>
        <button type="submit">Сохранить параметры</button>
      </form>

      <div class="notice">
        <strong>Последнее изменение:</strong> $last_updated<br />
        <strong>Активных клиентов:</strong> $active_clients<br />
        <strong>Состояние NDS:</strong> $nds_state_label
      </div>
    </section>

    <section class="grid two">
      <form method="post" action="/cgi-bin/clear_sessions.sh" class="actions">
        <label>Активные сессии</label>
        <button type="submit">Очистить все сессии</button>
      </form>

      <form method="post" action="/cgi-bin/nds_control.sh" class="actions">
        <label>Портал авторизации</label>
        <input type="hidden" name="action" value="toggle" />
        <button type="submit">$action_label портал</button>
        <button type="submit" name="action" value="restart" class="secondary">Перезапустить NDS</button>
      </form>
    </section>

    <section class="grid">
      <form method="post" action="/cgi-bin/admin_mac.sh" class="grid">
        <div>
          <label for="admin_mac">MAC администратора</label>
          <input type="text" id="admin_mac" name="mac" placeholder="AA:BB:CC:DD:EE:FF" required />
        </div>
        <div class="actions">
          <button type="submit" name="mode" value="add">Добавить в белый список</button>
          <button type="submit" name="mode" value="remove" class="secondary">Удалить из белого списка</button>
        </div>
      </form>
      <div>
        <label>Текущий белый список</label>
        <div class="notice">
HTML

if [ -n "$admin_mac_entries" ]; then
  printf '%s\n' "$admin_mac_entries" | while IFS= read -r entry; do
    [ -n "$entry" ] || continue
    printf '          • %s<br />\n' "$entry"
  done
else
  echo "          Нет сохранённых MAC-адресов"
fi

cat <<'HTML'
        </div>
      </div>
    </section>

    <section class="notice">
      <p>Для просмотра метрик Prometheus используйте <a href="/cgi-bin/metrics.sh">/metrics</a>.</p>
      <p>HTTP Basic Auth активируется автоматически, если заданы логин и пароль в настройках.</p>
    </section>
  </div>
</body>
</html>
HTML
