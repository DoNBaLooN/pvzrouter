#!/bin/ash
set -e

require_cmd() {
    if ! command -v "$1" >/dev/null 2>&1; then
        echo "[ERROR] Требуется пакет: $1" >&2
        exit 1
    fi
}

require_cmd nodogsplashctl
require_cmd uhttpd
require_cmd crond

/etc/init.d/nodogsplash stop >/dev/null 2>&1 || true
/etc/init.d/nodogsplash disable >/dev/null 2>&1 || true

install -d /etc/nodogsplash/htdocs
install -d /www/cgi-bin/api

for file in splash.html success.html denied.html admin.html; do
    install -m 0644 "etc/nodogsplash/htdocs/$file" "/etc/nodogsplash/htdocs/$file"
done

for script in common.sh auth.sh admin_get.sh admin_update.sh admin_clear.sh admin_nds.sh admin_mac_add.sh admin_status.sh session_check.sh; do
    install -m 0755 "/www/cgi-bin/api/$script" "/www/cgi-bin/api/$script"
done

CONFIG_FILE="/etc/config/wifi_auth"
if [ ! -f "$CONFIG_FILE" ]; then
    cat <<'CFG' > "$CONFIG_FILE"
code='0000'
duration='60'
nds_enabled='0'
CFG
else
    grep -q "^code='" "$CONFIG_FILE" || echo "code='0000'" >> "$CONFIG_FILE"
    grep -q "^duration='" "$CONFIG_FILE" || echo "duration='60'" >> "$CONFIG_FILE"
    grep -q "^nds_enabled='" "$CONFIG_FILE" || echo "nds_enabled='0'" >> "$CONFIG_FILE"
fi

touch /tmp/active_sessions.txt

CRON_LINE='*/5 * * * * /www/cgi-bin/api/session_check.sh >/dev/null 2>&1'
if [ -f /etc/crontabs/root ]; then
    grep -Fq "$CRON_LINE" /etc/crontabs/root || echo "$CRON_LINE" >> /etc/crontabs/root
else
    echo "$CRON_LINE" > /etc/crontabs/root
fi

if uci -q get uhttpd.main >/dev/null 2>&1; then
    uci -q set uhttpd.main.cgi_prefix='/cgi-bin'
    CURRENT_INTERPRETERS="$(uci -q get uhttpd.main.interpreter 2>/dev/null)"
    echo "$CURRENT_INTERPRETERS" | grep -q '.sh=/bin/ash' || uci -q add_list uhttpd.main.interpreter='.sh=/bin/ash'
    CURRENT_ALIASES="$(uci -q get uhttpd.main.alias 2>/dev/null)"
    echo "$CURRENT_ALIASES" | grep -q '/api=/www/cgi-bin/api' || uci -q add_list uhttpd.main.alias='/api=/www/cgi-bin/api'
    uci commit uhttpd >/dev/null 2>&1
    /etc/init.d/uhttpd restart >/dev/null 2>&1 || /etc/init.d/uhttpd reload >/dev/null 2>&1 || true
fi

echo "Установка завершена. NoDogSplash отключен. Включите через /api/admin/nds."
