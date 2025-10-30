#!/bin/sh
set -eu

REPO_RAW="${REPO_RAW:-https://raw.githubusercontent.com/DoNBaLooN/pvzrouter/main}"
WWW_DIR="${WWW_DIR:-/www}"
CGI_DIR="$WWW_DIR/cgi-bin"
CSS_DIR="$WWW_DIR/css"
CONFIG_PATH="${CONFIG_PATH:-/etc/config/wifi_auth}"
CRON_FILE="${CRON_FILE:-/etc/crontabs/root}"
SESSIONS_FILE="${SESSIONS_FILE:-/tmp/active_sessions.txt}"

log() {
  echo "[install] $1"
}

fetch() {
  dest="$1"
  src_path="$2"
  url="$REPO_RAW/$src_path"

  log "fetching $src_path"
  if ! wget -q -O "$dest" "$url"; then
    log "failed to download $url"
    exit 1
  fi
}

ensure_directory() {
  dir="$1"
  if [ ! -d "$dir" ]; then
    log "creating directory $dir"
    mkdir -p "$dir"
  fi
}

ensure_uhttpd_option() {
  option="$1"
  value="$2"
  if ! uci -q show uhttpd.main."$option" 2>/dev/null | grep -F "='$value'" >/dev/null; then
    uci add_list uhttpd.main."$option"="$value"
  fi
}

log "starting portal installation"

ensure_directory "$WWW_DIR"
ensure_directory "$CGI_DIR"
ensure_directory "$CSS_DIR"

fetch "$WWW_DIR/index.html" "www/index.html"
fetch "$WWW_DIR/success.html" "www/success.html"
fetch "$WWW_DIR/admin.html" "www/admin.html"
fetch "$CSS_DIR/wifi_auth.css" "www/css/wifi_auth.css"

for script in admin_mac.sh admin_portal.sh clear_sessions.sh metrics.sh nds_control.sh session_check.sh update_code.sh wifi_auth.sh; do
  fetch "$CGI_DIR/$script" "www/cgi-bin/$script"
  chmod 0755 "$CGI_DIR/$script"
done

ensure_directory "$(dirname "$CONFIG_PATH")"
fetch "$CONFIG_PATH" "etc/config/wifi_auth"

chmod 0644 "$WWW_DIR/index.html" "$WWW_DIR/success.html" "$WWW_DIR/admin.html" "$CSS_DIR/wifi_auth.css"
chmod 0644 "$CONFIG_PATH"

touch "$SESSIONS_FILE"

if [ ! -f "$CRON_FILE" ]; then
  log "creating cron file $CRON_FILE"
  touch "$CRON_FILE"
fi

if ! grep -q "/www/cgi-bin/session_check.sh" "$CRON_FILE" 2>/dev/null; then
  log "registering cron job for session cleanup"
  echo "*/5 * * * * /www/cgi-bin/session_check.sh >/dev/null 2>&1" >>"$CRON_FILE"
fi

if command -v uci >/dev/null 2>&1; then
  log "configuring uhttpd"
  ensure_uhttpd_option cgi_prefix '/cgi-bin'
  ensure_uhttpd_option interpreter '.sh=/bin/ash'
  ensure_uhttpd_option alias '/metrics=/www/cgi-bin/metrics.sh'
  uci commit uhttpd
  if [ -x /etc/init.d/uhttpd ]; then
    /etc/init.d/uhttpd reload >/dev/null 2>&1 || /etc/init.d/uhttpd restart >/dev/null 2>&1 || true
  fi
else
  log "uci not found; skipping uhttpd configuration"
fi

if [ -x /etc/init.d/cron ]; then
  log "reloading cron daemon"
  /etc/init.d/cron restart >/dev/null 2>&1 || /etc/init.d/cron start >/dev/null 2>&1 || true
fi

log "installation complete"

