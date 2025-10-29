#!/bin/sh

set -e

REPO_RAW="https://raw.githubusercontent.com/DoNBaLooN/pvzrouter/main"
WWW_DIR="/www"
CGI_DIR="$WWW_DIR/cgi-bin"
CONFIG_FILE="/etc/config/wifi_auth"
CRON_FILE="/etc/crontabs/root"
SESS_FILE="/tmp/active_sessions.txt"

need_root() {
    if [ "$(id -u)" != "0" ]; then
        echo "❌ Запустите установку от имени root." >&2
        exit 1
    fi
}

ensure_tool() {
    tool="$1"
    if ! command -v "$tool" >/dev/null 2>&1; then
        echo "❌ Требуется утилита '$tool'. Установите её и повторите попытку." >&2
        exit 1
    fi
}

download() {
    url="$1"
    dest="$2"

    if command -v wget >/dev/null 2>&1; then
        if wget -qO "$dest" "$url"; then
            return 0
        fi
        wget --no-check-certificate -qO "$dest" "$url"
        return
    fi

    if command -v curl >/dev/null 2>&1; then
        curl -fsSL "$url" -o "$dest"
        return
    fi

    if command -v uclient-fetch >/dev/null 2>&1; then
        if uclient-fetch -q -O "$dest" "$url"; then
            return 0
        fi
        uclient-fetch --no-check-certificate -q -O "$dest" "$url"
        return
    fi

    echo "❌ Не найден инструмент для загрузки (wget/curl/uclient-fetch)." >&2
    exit 1
}

setup_directories() {
    echo "📁 Создаю каталоги..."
    mkdir -p "$WWW_DIR" "$CGI_DIR"
}

install_www_files() {
    echo "⬇️  Загружаю HTML-файлы..."
    download "$REPO_RAW/www/index.html" "$WWW_DIR/index.html"
    download "$REPO_RAW/www/success.html" "$WWW_DIR/success.html"
    download "$REPO_RAW/www/admin.html" "$WWW_DIR/admin.html"
}

install_cgi_files() {
    echo "⬇️  Загружаю CGI-скрипты..."
    for file in \
        admin_panel.sh \
        clear_sessions.sh \
        restart_portal.sh \
        session_check.sh \
        toggle_protection.sh \
        update_code.sh \
        wifi_auth.sh
    do
        download "$REPO_RAW/www/cgi-bin/$file" "$CGI_DIR/$file"
    done

    chmod +x "$WWW_DIR/admin.html" "$CGI_DIR"/*.sh
}

install_config() {
    if [ ! -f "$CONFIG_FILE" ]; then
        echo "🛠️  Устанавливаю конфигурацию wifi_auth..."
        mkdir -p "$(dirname "$CONFIG_FILE")"
        download "$REPO_RAW/etc/config/wifi_auth" "$CONFIG_FILE"
    else
        echo "ℹ️  Конфигурация wifi_auth уже существует — оставляю без изменений."
    fi
}

prepare_runtime() {
    echo "🗂️  Готовлю рабочие файлы..."
    touch "$SESS_FILE"
    chmod 644 "$SESS_FILE"
}

setup_cron() {
    echo "⏰ Обновляю cron..."
    touch "$CRON_FILE"
    if ! grep -q "session_check.sh" "$CRON_FILE"; then
        echo "*/5 * * * * /www/cgi-bin/session_check.sh >/dev/null 2>&1" >> "$CRON_FILE"
        /etc/init.d/cron restart >/dev/null 2>&1 || true
    fi
}

ensure_uhttpd_interpreter() {
    echo "🌐 Проверяю поддержку .sh в uhttpd..."
    if ! uci get uhttpd.main.interpreter 2>/dev/null | grep -q "/bin/sh"; then
        echo "➕ Добавляю обработку .sh в uhttpd..."
        uci add_list uhttpd.main.interpreter='.sh=/bin/sh'
        uci commit uhttpd
    else
        echo "✅ Поддержка .sh уже включена."
    fi
}

restart_services() {
    echo "🔁 Перезапускаю службы..."
    if [ -x /etc/init.d/uhttpd ]; then
        /etc/init.d/uhttpd restart >/dev/null 2>&1 || true
    fi
    if [ -x /etc/init.d/nodogsplash ]; then
        /etc/init.d/nodogsplash restart >/dev/null 2>&1 || true
    fi
}

main() {
    need_root
    ensure_tool uci
    setup_directories
    install_www_files
    install_cgi_files
    install_config
    prepare_runtime
    setup_cron
    ensure_uhttpd_interpreter
    restart_services
    echo "✅ Установка завершена. Портал доступен по адресу: http://<router_ip>/"
}

main "$@"
