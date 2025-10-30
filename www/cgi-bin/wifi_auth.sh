#!/bin/ash

set -eu

CONFIG="wifi_auth.portal"
SESSIONS_FILE="/tmp/active_sessions.txt"
LOG_TAG="wifi_auth"

read_request_body() {
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

url_decode() {
  local data="${1//+/ }"
  printf '%b' "${data//%/\\x}"
}

get_field() {
  local data="$1" key="$2"
  printf '%s' "$data" | tr '&' '\n' | awk -F'=' -v k="$key" '$1==k {print $2}' | tail -n 1
}

normalize_mac() {
  echo "$1" | tr 'a-z' 'A-Z' | sed 's/[^0-9A-F:]//g'
}

authorize_client() {
  local mac="$1"
  if command -v nodogsplashctl >/dev/null 2>&1; then
    nodogsplashctl allow "$mac" >/dev/null 2>&1 || true
  elif command -v ndsctl >/dev/null 2>&1; then
    ndsctl allow "$mac" >/dev/null 2>&1 || true
  fi
}

ensure_sessions_file() {
  touch "$SESSIONS_FILE"
}

body=$(read_request_body)
submitted_code=$(url_decode "$(get_field "$body" code)")
submitted_code=$(echo "$submitted_code" | tr -d '\r')

expected_code=$(uci -q get $CONFIG.code 2>/dev/null)
[ -n "$expected_code" ] || expected_code=""

duration=$(uci -q get $CONFIG.duration 2>/dev/null)
[ -n "$duration" ] || duration=60

client_mac=$(normalize_mac "${HTTP_NDSMAC:-${HTTP_X_NDS_MAC:-${HTTP_X_NDSMAC:-${HTTP_NDS_REMOTE_MAC:-}}}}")
client_ip="$REMOTE_ADDR"

if [ -z "$client_mac" ]; then
  client_mac="UNKNOWN"
fi

if [ -z "$submitted_code" ]; then
  logger -t "$LOG_TAG" "empty code submitted from $client_mac"
  cat <<'HTML'
Content-Type: text/html; charset=utf-8

<!DOCTYPE html>
<html lang="ru">
<head><meta charset="UTF-8" /><title>Ошибка авторизации</title><link rel="stylesheet" href="/css/wifi_auth.css" /></head>
<body><div class="container"><header><h1>Ошибка</h1><p>Код не был передан</p></header></div></body></html>
HTML
  exit 0
fi

now=$(date +%s)
expiry=$((now + duration * 60))

if [ "$submitted_code" = "$expected_code" ] && [ -n "$expected_code" ]; then
  ensure_sessions_file
  if [ -f "$SESSIONS_FILE" ]; then
    grep -v "^$client_mac|" "$SESSIONS_FILE" >"$SESSIONS_FILE.tmp" 2>/dev/null || true
    mv "$SESSIONS_FILE.tmp" "$SESSIONS_FILE"
  fi
  echo "$client_mac|$expiry|$client_ip|$now" >>"$SESSIONS_FILE"
  authorize_client "$client_mac"

  total_logins=$(uci -q get $CONFIG.total_logins 2>/dev/null)
  [ -n "$total_logins" ] || total_logins=0
  total_logins=$((total_logins + 1))
  uci set $CONFIG.total_logins=$total_logins
  uci commit wifi_auth

  logger -t "$LOG_TAG" "client $client_mac authorized until $expiry"
  cat <<'HTML'
Status: 302 Found
Location: /success.html

HTML
else
  logger -t "$LOG_TAG" "client $client_mac provided wrong code"
  cat <<'HTML'
Content-Type: text/html; charset=utf-8

<!DOCTYPE html>
<html lang="ru">
<head><meta charset="UTF-8" /><title>Неверный код</title><link rel="stylesheet" href="/css/wifi_auth.css" /></head>
<body>
  <div class="container">
    <header>
      <h1>Доступ отклонён</h1>
      <p>Введён неверный код. Пожалуйста, попробуйте ещё раз.</p>
    </header>
    <form method="post" action="/cgi-bin/wifi_auth.sh">
      <label for="code">Код дня</label>
      <input type="text" id="code" name="code" required />
      <button type="submit">Повторить</button>
    </form>
  </div>
</body>
</html>
HTML
fi
