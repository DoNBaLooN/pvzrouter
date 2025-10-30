#!/bin/ash
# отладка и лог
set -ex
LOG="/tmp/install_wifi.log"
exec >"$LOG" 2>&1
echo "[INFO] Начало установки WiFi-портала..."

require_cmd() {
    if ! command -v "$1" >/dev/null 2>&1; then
        echo "[ERROR] Требуется пакет: $1" >&2
        exit 1
    fi
}

BASE_DIR="$(cd "$(dirname "$0")" && pwd)"

# Проверка нужных команд
command -v nodogsplashctl >/dev/null 2>&1 || {
    if command -v ndsctl >/dev/null 2>&1; then
        echo "[INFO] Создаю обёртку /usr/bin/nodogsplashctl → ndsctl"
        ln -sf "$(command -v ndsctl)" /usr/bin/nodogsplashctl
    else
        echo "[ERROR] Требуется nodogsplashctl или ndsctl" >&2
        exit 1
    fi
}

require_cmd uhttpd
require_cmd crond

# Отключаем NoDogSplash
/etc/init.d/nodogsplash stop >/dev/null 2>&1 || true
/etc/init.d/nodogsplash disable >/dev/null 2>&1 || true

# Создаём каталоги
mkdir -p /etc/nodogsplash/htdocs
mkdir -p /www/cgi-bin/api

# Копируем HTML-файлы
for file in splash.html success.html denied.html admin.html; do
    if [ -f "$BASE_DIR/etc/nodogsplash/htdocs/$file" ]; then
        cp -f "$BASE_DIR/etc/nodogsplash/htdocs/$file" "/etc/nodogsplash/htdocs/$file"
        chmod 0644 "/etc/nodogsplash/htdocs/$file"
    fi
done

# Копируем CGI-скрипты
for script in common.sh auth.sh admin_get.sh admin_update.sh admin_clear.sh admin_nds.sh admin_mac_add.sh admin_status.sh session_check.sh; do
    if [ -f "$BASE_DIR/www/cgi-bin/api/$script" ]; then
        cp -f "$BASE_DIR/www/cgi-bin/api/$script" "/www/cgi-bin/api/$script"
        chmod 0755 "/www/cgi-bin/api/$script"
    fi
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
    CURRENT_INTERPRETERS="$(uci -q get uhttpd.main.interpreter 2>/dev/null || true)"
    case "$CURRENT_INTERPRETERS" in
        *'.sh=/bin/ash'*) echo "[OK] Интерпретатор уже настроен";;
        *) echo "[FIX] Добавляю .sh=/bin/ash"; uci -q add_list uhttpd.main.interpreter='.sh=/bin/ash';;
    esac

    CURRENT_ALIASES="$(uci -q get uhttpd.main.alias 2>/dev/null || true)"
    case "$CURRENT_ALIASES" in
        *'/api=/www/cgi-bin/api'*) echo "[OK] Алиас уже настроен";;
        *) echo "[FIX] Добавляю алиас /api=/www/cgi-bin/api"; uci -q add_list uhttpd.main.alias='/api=/www/cgi-bin/api';;
    esac

    uci commit uhttpd >/dev/null 2>&1
    /etc/init.d/uhttpd restart >/dev/null 2>&1 || /etc/init.d/uhttpd reload >/dev/null 2>&1 || true
else
    echo "[WARN] Раздел uhttpd.main не найден — пропускаю настройку CGI."
fi

echo "[INFO] Проверяю права на каталоги..."
chmod 755 /etc/nodogsplash /etc/nodogsplash/htdocs /www /www/cgi-bin /www/cgi-bin/api 2>/dev/null || true

echo "[INFO] Проверяю настройки uhttpd..."
if ! uci -q get uhttpd.main.interpreter | grep -q '.sh=/bin/ash'; then
    echo "[FIX] Добавляю интерпретатор .sh=/bin/ash"
    uci add_list uhttpd.main.interpreter='.sh=/bin/ash'
    uci commit uhttpd
fi

if ! uci -q get uhttpd.main.alias | grep -q '/api=/www/cgi-bin/api'; then
    echo "[FIX] Добавляю алиас /api=/www/cgi-bin/api"
    uci add_list uhttpd.main.alias='/api=/www/cgi-bin/api'
    uci commit uhttpd
fi

/etc/init.d/uhttpd restart >/dev/null 2>&1 || /etc/init.d/uhttpd reload >/dev/null 2>&1 || true

echo
echo "[OK] Установка завершена успешно."
echo "NoDogSplash отключен."
echo "CGI-доступ: http://$(uci -q get network.lan.ipaddr 2>/dev/null || echo '<роутер>')/api/admin/status.sh"
echo "[INFO] Полный лог: $LOG"
