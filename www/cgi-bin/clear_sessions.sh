#!/bin/ash

set -eu

CONFIG="wifi_auth.portal"
SESSIONS_FILE="/tmp/active_sessions.txt"
LOG_TAG="wifi_auth"

is_admin_mac() {
  local mac="$1"
  [ -n "$mac" ] || return 1
  uci -q show $CONFIG.admin_mac_whitelist 2>/dev/null | grep -qi "=$mac$"
}

if [ -f "$SESSIONS_FILE" ]; then
  tmp_file="$SESSIONS_FILE.tmp"
  >"$tmp_file"
  while IFS='|' read -r mac expiry ip created; do
    [ -n "$mac" ] || continue
    if is_admin_mac "$mac"; then
      echo "$mac|$expiry|$ip|$created" >>"$tmp_file"
      continue
    fi
    if command -v nodogsplashctl >/dev/null 2>&1; then
      nodogsplashctl deauth "$mac" >/dev/null 2>&1 || true
    elif command -v ndsctl >/dev/null 2>&1; then
      ndsctl deauth "$mac" >/dev/null 2>&1 || true
    fi
  done <"$SESSIONS_FILE"
  mv "$tmp_file" "$SESSIONS_FILE"
fi

logger -t "$LOG_TAG" "all sessions cleared"

cat <<'HTML'
Content-Type: text/html; charset=utf-8

<!DOCTYPE html>
<html lang="ru">
<head><meta charset="UTF-8" /><title>Сессии очищены</title><link rel="stylesheet" href="/css/wifi_auth.css" /></head>
<body>
  <div class="container">
    <header>
      <h1>Выполнено</h1>
      <p>Все активные сессии завершены.</p>
    </header>
    <form method="get" action="/cgi-bin/admin_portal.sh">
      <button type="submit">Вернуться в админку</button>
    </form>
  </div>
</body>
</html>
HTML
