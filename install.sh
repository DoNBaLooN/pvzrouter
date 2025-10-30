#!/bin/ash

set -e

SCRIPT_DIR="$(CDPATH= cd -- "$(dirname "$0")" && pwd)"
WWW_SRC="$SCRIPT_DIR/www"
CONFIG_DEST="/etc/config/wifi_auth"
CGI_DIR="/www/cgi-bin"
SESSIONS_FILE="/tmp/active_sessions.txt"
CRON_FILE="/etc/crontabs/root"
CRON_LINE="*/5 * * * * /www/cgi-bin/session_check.sh >/dev/null 2>&1"

require_binary() {
    local bin="$1"
    if ! command -v "$bin" >/dev/null 2>&1; then
        echo "[Ошибка] Требуется установленный $bin" >&2
        return 1
    fi
    return 0
}

check_dependencies() {
    local missing=0
    require_binary nodogsplashctl || missing=1
    require_binary uhttpd || missing=1
    require_binary crond || missing=1
    if [ $missing -ne 0 ]; then
        echo "Установите недостающие пакеты и повторите попытку." >&2
        exit 1
    fi
}

stop_nodogsplash() {
    /etc/init.d/nodogsplash stop >/dev/null 2>&1 || true
    /etc/init.d/nodogsplash disable >/dev/null 2>&1 || true
}

copy_www() {
    mkdir -p /www
    cp -r "$WWW_SRC"/* /www/
}

install_config() {
    mkdir -p /etc/config
    if [ -f "$CONFIG_DEST" ]; then
        . "$CONFIG_DEST"
    fi
    code='0000'
    duration='60'
    nds_enabled='0'
    [ -n "$admin_macs" ] || admin_macs=''
    cat <<CFG > "$CONFIG_DEST"
code='$code'
duration='$duration'
nds_enabled='$nds_enabled'
admin_macs='$admin_macs'
CFG
    chmod 0644 "$CONFIG_DEST"
}

prepare_sessions_file() {
    : > "$SESSIONS_FILE"
}

install_cron() {
    mkdir -p "$(dirname "$CRON_FILE")"
    touch "$CRON_FILE"
    if ! grep -F "$CRON_LINE" "$CRON_FILE" >/dev/null 2>&1; then
        printf '%s\n' "$CRON_LINE" >> "$CRON_FILE"
    fi
    /etc/init.d/cron restart >/dev/null 2>&1 || true
}

make_cgi_executable() {
    mkdir -p "$CGI_DIR"
    cp -r "$WWW_SRC/cgi-bin"/* "$CGI_DIR"/
    chmod 0755 "$CGI_DIR"/*.sh
}

enable_cgi_support() {
    if command -v uci >/dev/null 2>&1; then
        local current
        current="$(uci -q get uhttpd.main.cgi_prefix 2>/dev/null)"
        if [ "$current" != "/cgi-bin" ]; then
            uci set uhttpd.main.cgi_prefix='/cgi-bin'
            uci commit uhttpd
            /etc/init.d/uhttpd restart >/dev/null 2>&1 || true
        fi
    fi
}

main() {
    check_dependencies
    stop_nodogsplash
    copy_www
    make_cgi_executable
    install_config
    prepare_sessions_file
    install_cron
    enable_cgi_support
    echo "Установка завершена. NoDogSplash выключен до ручного включения."
}

main "$@"
