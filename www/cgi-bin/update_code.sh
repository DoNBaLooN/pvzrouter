#!/bin/ash

set -eu

CONFIG="wifi_auth.portal"
LOG_TAG="wifi_auth"

read -r body

url_decode() {
  local data="${1//+/ }"
  printf '%b' "${data//%/\\x}"
}

get_field() {
  printf '%s' "$body" | tr '&' '\n' | awk -F'=' -v k="$1" '$1==k {print $2}' | tail -n 1
}

new_code=$(url_decode "$(get_field code)")
new_duration=$(url_decode "$(get_field duration)")

if ! echo "$new_duration" | grep -Eq '^[0-9]+$'; then
  new_duration=60
fi

if [ "$new_duration" -lt 1 ] 2>/dev/null; then
  new_duration=1
fi

timestamp=$(date +%s)
now=$(date '+%Y-%m-%d %H:%M:%S %Z')
uci set $CONFIG.code="$new_code"
uci set $CONFIG.duration="$new_duration"
uci set $CONFIG.updated="$now"
uci set $CONFIG.updated_unix="$timestamp"

code_updates=$(uci -q get $CONFIG.code_updates_total 2>/dev/null)
[ -n "$code_updates" ] || code_updates=0
code_updates=$((code_updates + 1))
uci set $CONFIG.code_updates_total=$code_updates
uci commit wifi_auth

logger -t "$LOG_TAG" "code updated; duration=$new_duration"

cat <<'HTML'
Content-Type: text/html; charset=utf-8

<!DOCTYPE html>
<html lang="ru">
<head><meta charset="UTF-8" /><title>Параметры обновлены</title><link rel="stylesheet" href="/css/wifi_auth.css" /></head>
<body>
  <div class="container">
    <header>
      <h1>Сохранено</h1>
      <p>Новые параметры авторизации применены.</p>
    </header>
    <form method="get" action="/cgi-bin/admin_portal.sh">
      <button type="submit">Вернуться в админку</button>
    </form>
  </div>
</body>
</html>
HTML
