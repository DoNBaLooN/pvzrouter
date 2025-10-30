#!/bin/ash

set -eu

CONFIG="wifi_auth.portal"
LOG_TAG="wifi_auth"

read_cgi_body() {
  local method="${REQUEST_METHOD:-GET}"
  if [ "$method" = "POST" ]; then
    if [ -n "${CONTENT_LENGTH:-}" ]; then
      dd bs=1 count="$CONTENT_LENGTH" 2>/dev/null || true
    else
      local data=""
      IFS= read -r data || true
      printf '%s' "$data"
    fi
  else
    printf '%s' "${QUERY_STRING:-}"
  fi
}

action="${1:-}"
if [ -z "$action" ]; then
  body="$(read_cgi_body)"
  action=$(printf '%s' "$body" | tr '&' '\n' | awk -F'=' '$1=="action" {print $2}' | tail -n 1)
fi

url_decode() {
  local data="${1//+/ }"
  printf '%b' "${data//%/\\x}"
}

action=$(url_decode "$action")
[ -n "$action" ] || action="toggle"

current_state=$(uci -q get $CONFIG.nds_enabled 2>/dev/null)
[ -n "$current_state" ] || current_state=0

init_script="/etc/init.d/nodogsplash"
result_msg=""

case "$action" in
  start)
    "$init_script" start >/dev/null 2>&1 || true
    "$init_script" enable >/dev/null 2>&1 || true
    uci set $CONFIG.nds_enabled='1'
    result_msg="Портал запущен"
    ;;
  stop)
    "$init_script" stop >/dev/null 2>&1 || true
    "$init_script" disable >/dev/null 2>&1 || true
    uci set $CONFIG.nds_enabled='0'
    result_msg="Портал остановлен"
    ;;
  restart)
    "$init_script" restart >/dev/null 2>&1 || { "$init_script" stop >/dev/null 2>&1; "$init_script" start >/dev/null 2>&1; }
    result_msg="Портал перезапущен"
    ;;
  toggle)
    if [ "$current_state" = "1" ]; then
      "$init_script" stop >/dev/null 2>&1 || true
      "$init_script" disable >/dev/null 2>&1 || true
      uci set $CONFIG.nds_enabled='0'
      result_msg="Портал выключен"
    else
      "$init_script" start >/dev/null 2>&1 || true
      "$init_script" enable >/dev/null 2>&1 || true
      uci set $CONFIG.nds_enabled='1'
      result_msg="Портал включен"
    fi
    ;;
  enable)
    "$init_script" enable >/dev/null 2>&1 || true
    uci set $CONFIG.nds_enabled='1'
    result_msg="Автозапуск включён"
    ;;
  disable)
    "$init_script" disable >/dev/null 2>&1 || true
    uci set $CONFIG.nds_enabled='0'
    result_msg="Автозапуск выключен"
    ;;
  *)
    result_msg="Неизвестная команда"
    ;;
esac

uci commit wifi_auth
logger -t "$LOG_TAG" "nds control action=$action"

cat <<HTML
Content-Type: text/html; charset=utf-8

<!DOCTYPE html>
<html lang="ru">
<head><meta charset="UTF-8" /><title>Управление NDS</title><link rel="stylesheet" href="/css/wifi_auth.css" /></head>
<body>
  <div class="container">
    <header>
      <h1>Выполнено</h1>
      <p>$result_msg.</p>
    </header>
    <form method="get" action="/cgi-bin/admin_portal.sh">
      <button type="submit">Вернуться в админку</button>
    </form>
  </div>
</body>
</html>
HTML
