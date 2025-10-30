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

body="$(read_cgi_body)"

url_decode() {
  local data="${1//+/ }"
  printf '%b' "${data//%/\\x}"
}

get_field() {
  printf '%s' "$body" | tr '&' '\n' | awk -F'=' -v k="$1" '$1==k {print $2}' | tail -n 1
}

normalize_mac() {
  echo "$1" | tr 'a-f' 'A-F' | sed 's/[^0-9A-F:]//g'
}

mac=$(normalize_mac "$(url_decode "$(get_field mac)")")
mode=$(url_decode "$(get_field mode)")

if [ -z "$mac" ]; then
  cat <<'HTML'
Content-Type: text/html; charset=utf-8

<!DOCTYPE html>
<html lang="ru">
<head><meta charset="UTF-8" /><title>Ошибка</title><link rel="stylesheet" href="/css/wifi_auth.css" /></head>
<body><div class="container"><header><h1>Ошибка</h1><p>MAC-адрес не распознан.</p></header></div></body></html>
HTML
  exit 0
fi

mac_exists() {
  uci -q show $CONFIG.admin_mac_whitelist 2>/dev/null | grep -qi "=$mac$"
}

result_msg=""

case "$mode" in
  remove)
    if mac_exists; then
      uci del_list $CONFIG.admin_mac_whitelist="$mac" 2>/dev/null || true
      result_msg="MAC $mac удалён из белого списка"
      logger -t "$LOG_TAG" "admin mac removed $mac"
      if command -v nodogsplashctl >/dev/null 2>&1; then
        nodogsplashctl deauth "$mac" >/dev/null 2>&1 || true
      fi
    else
      result_msg="MAC $mac не найден в белом списке"
    fi
    ;;
  *)
    if mac_exists; then
      result_msg="MAC $mac уже находится в белом списке"
    else
      uci add_list $CONFIG.admin_mac_whitelist="$mac" 2>/dev/null || true
      result_msg="MAC $mac добавлен в белый список"
      logger -t "$LOG_TAG" "admin mac added $mac"
    fi
    if command -v nodogsplashctl >/dev/null 2>&1; then
      nodogsplashctl allow "$mac" >/dev/null 2>&1 || true
    fi
    ;;
esac

uci commit wifi_auth

cat <<HTML
Content-Type: text/html; charset=utf-8

<!DOCTYPE html>
<html lang="ru">
<head><meta charset="UTF-8" /><title>Белый список</title><link rel="stylesheet" href="/css/wifi_auth.css" /></head>
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
