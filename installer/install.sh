#!/bin/ash

set -eu

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
BASE_DIR=$(cd "$SCRIPT_DIR/.." && pwd)
CONFIG_NAME="wifi_auth"
CONFIG_SECTION="portal"
CONFIG_PATH="/etc/config/$CONFIG_NAME"
CRON_FILE="/etc/crontabs/root"
SESSIONS_FILE="/tmp/active_sessions.txt"
AUTH_FILE="/etc/httpd-wifi-auth.users"

log() {
  echo "[install] $1"
}

ensure_package() {
  local pkg="$1"
  if ! opkg list-installed "$pkg" >/dev/null 2>&1; then
    log "installing $pkg"
    opkg update >/dev/null 2>&1 || true
    opkg install "$pkg"
  fi
}

ensure_binary() {
  local binary="$1" package="$2"
  if ! command -v "$binary" >/dev/null 2>&1; then
    ensure_package "$package"
  fi
}

stop_nodogsplash() {
  if [ -x /etc/init.d/nodogsplash ]; then
    log "stopping nodogsplash during installation"
    /etc/init.d/nodogsplash stop >/dev/null 2>&1 || true
    /etc/init.d/nodogsplash disable >/dev/null 2>&1 || true
  fi
}

backup_file() {
  local target="$1"
  if [ -e "$target" ]; then
    local backup="$target.$(date +%Y%m%d%H%M%S).bak"
    cp "$target" "$backup"
    log "backup created: $backup"
  fi
}

copy_file() {
  local src="$1" dst="$2" mode="$3"
  backup_file "$dst"
  install -D -m "$mode" "$src" "$dst"
}

setup_files() {
  log "deploying portal web content"
  copy_file "$BASE_DIR/www/index.html" "/www/index.html" 0644
  copy_file "$BASE_DIR/www/success.html" "/www/success.html" 0644
  copy_file "$BASE_DIR/www/admin.html" "/www/admin.html" 0644
  copy_file "$BASE_DIR/www/css/wifi_auth.css" "/www/css/wifi_auth.css" 0644

  for script in wifi_auth.sh update_code.sh clear_sessions.sh session_check.sh nds_control.sh admin_mac.sh admin_portal.sh metrics.sh; do
    copy_file "$BASE_DIR/www/cgi-bin/$script" "/www/cgi-bin/$script" 0755
  done

  touch "$SESSIONS_FILE"
}

setup_config() {
  log "configuring UCI package"
  if [ ! -f "$CONFIG_PATH" ]; then
    cat <<'CFG' >"$CONFIG_PATH"
config portal 'portal'
  option code '0000'
  option duration '60'
  option updated ''
  option updated_unix '0'
  option admin_mac_whitelist ''
  option basic_auth_enabled '0'
  option basic_auth_user ''
  option basic_auth_password ''
  option nds_enabled '0'
  option total_logins '0'
  option code_updates_total '0'
CFG
  fi

  uci -q rename $CONFIG_NAME.@portal[0]=$CONFIG_SECTION 2>/dev/null || true

  [ -n "$(uci -q get $CONFIG_NAME.$CONFIG_SECTION.code 2>/dev/null)" ] || uci set $CONFIG_NAME.$CONFIG_SECTION.code='0000'
  [ -n "$(uci -q get $CONFIG_NAME.$CONFIG_SECTION.duration 2>/dev/null)" ] || uci set $CONFIG_NAME.$CONFIG_SECTION.duration='60'
  uci -q get $CONFIG_NAME.$CONFIG_SECTION.updated >/dev/null 2>&1 || uci set $CONFIG_NAME.$CONFIG_SECTION.updated=''
  uci -q get $CONFIG_NAME.$CONFIG_SECTION.updated_unix >/dev/null 2>&1 || uci set $CONFIG_NAME.$CONFIG_SECTION.updated_unix='0'
  uci -q get $CONFIG_NAME.$CONFIG_SECTION.basic_auth_enabled >/dev/null 2>&1 || uci set $CONFIG_NAME.$CONFIG_SECTION.basic_auth_enabled='0'
  uci -q get $CONFIG_NAME.$CONFIG_SECTION.basic_auth_user >/dev/null 2>&1 || uci set $CONFIG_NAME.$CONFIG_SECTION.basic_auth_user=''
  uci -q get $CONFIG_NAME.$CONFIG_SECTION.basic_auth_password >/dev/null 2>&1 || uci set $CONFIG_NAME.$CONFIG_SECTION.basic_auth_password=''
  uci -q get $CONFIG_NAME.$CONFIG_SECTION.nds_enabled >/dev/null 2>&1 || uci set $CONFIG_NAME.$CONFIG_SECTION.nds_enabled='0'
  uci -q get $CONFIG_NAME.$CONFIG_SECTION.total_logins >/dev/null 2>&1 || uci set $CONFIG_NAME.$CONFIG_SECTION.total_logins='0'
  uci -q get $CONFIG_NAME.$CONFIG_SECTION.code_updates_total >/dev/null 2>&1 || uci set $CONFIG_NAME.$CONFIG_SECTION.code_updates_total='0'
  uci commit $CONFIG_NAME
}

setup_cron() {
  log "registering cron cleanup job"
  touch "$CRON_FILE"
  if ! grep -q "/www/cgi-bin/session_check.sh" "$CRON_FILE"; then
    echo "*/5 * * * * /www/cgi-bin/session_check.sh >/dev/null 2>&1" >>"$CRON_FILE"
  fi
  /etc/init.d/cron enable >/dev/null 2>&1 || true
  /etc/init.d/cron restart >/dev/null 2>&1 || true
}

ensure_uhttpd_list() {
  local option="$1" value="$2"
  if ! uci -q show uhttpd.main.$option 2>/dev/null | grep -q "='$value'"; then
    uci add_list uhttpd.main.$option="$value"
  fi
}

setup_uhttpd() {
  log "ensuring uhttpd CGI routing"
  ensure_uhttpd_list cgi_prefix '/cgi-bin'
  ensure_uhttpd_list interpreter '.sh=/bin/ash'
  ensure_uhttpd_list alias '/metrics=/www/cgi-bin/metrics.sh'
  uci commit uhttpd
  /etc/init.d/uhttpd reload >/dev/null 2>&1 || /etc/init.d/uhttpd restart >/dev/null 2>&1 || true
}

apply_basic_auth() {
  local enabled=$(uci -q get $CONFIG_NAME.$CONFIG_SECTION.basic_auth_enabled 2>/dev/null)
  local user=$(uci -q get $CONFIG_NAME.$CONFIG_SECTION.basic_auth_user 2>/dev/null)
  local secret=$(uci -q get $CONFIG_NAME.$CONFIG_SECTION.basic_auth_password 2>/dev/null)

  if [ "$enabled" = "1" ] && [ -n "$user" ] && [ -n "$secret" ]; then
    log "applying HTTP basic auth configuration"
    printf '%s:%s\n' "$user" "$secret" >"$AUTH_FILE"
    uci -q delete uhttpd.main.httpauth >/dev/null 2>&1 || true
    uci -q delete uhttpd.main.htpasswd >/dev/null 2>&1 || true
    uci add_list uhttpd.main.httpauth="/admin=$AUTH_FILE"
    uci add_list uhttpd.main.httpauth="/cgi-bin/admin_portal.sh=$AUTH_FILE"
    uci add_list uhttpd.main.htpasswd="$AUTH_FILE"
    uci set uhttpd.main.realm='Wi-Fi Admin Portal'
  else
    log "removing HTTP basic auth configuration"
    rm -f "$AUTH_FILE"
    uci -q delete uhttpd.main.httpauth >/dev/null 2>&1 || true
    uci -q delete uhttpd.main.htpasswd >/dev/null 2>&1 || true
  fi
  uci commit uhttpd
  /etc/init.d/uhttpd reload >/dev/null 2>&1 || true
}

log_install() {
  logger -t wifi_auth "installer completed"
}

main() {
  log "starting Wi-Fi portal deployment"
  ensure_package nodogsplash
  ensure_package uhttpd
  ensure_binary uci base-files
  ensure_binary crond busybox
  ensure_package coreutils-date

  stop_nodogsplash
  setup_files
  setup_config
  setup_cron
  setup_uhttpd
  apply_basic_auth
  log_install
  log "done. manage the portal via http://10.0.0.1/admin"
}

main "$@"
