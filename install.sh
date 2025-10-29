#!/bin/sh

set -eu

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_URL="${REPO_URL:-https://github.com/DoNBaLooN/pvzrouter.git}"
BRANCH="${BRANCH:-main}"
WORKDIR="${WORKDIR:-/tmp/pvzrouter-install}"
SOURCE_DIR="${SOURCE_DIR:-}"
WWW_DST="/www"
CGI_DST="/www/cgi-bin"
CONFIG_DST="/etc/config/wifi_auth"
CRON_FILE="/etc/crontabs/root"
SESS_FILE="/tmp/active_sessions.txt"
LOCK_DIR="/var/lock"

require_root() {
    if [ "$(id -u)" != "0" ]; then
        echo "[!] Запустите установку от имени root." >&2
        exit 1
    fi
}

require_tool() {
    local tool="$1"
    if ! command -v "$tool" >/dev/null 2>&1; then
        echo "[!] Требуется установить утилиту '$tool'." >&2
        exit 1
    fi
}

build_clone_url() {
    local url="$1"
    if [ -n "${GIT_TOKEN:-}" ] && printf '%s' "$url" | grep -q '^https://'; then
        local user="${GIT_USERNAME:-oauth2}"
        printf '%s' "$url" | sed "s#https://#https://${user}:${GIT_TOKEN}@#"
        return
    fi
    printf '%s' "$url"
}

download_archive() {
    require_tool wget
    require_tool tar
    echo "[*] Загружаю архив репозитория..."
    rm -rf "$WORKDIR/src"
    wget -qO "$WORKDIR/archive.tar.gz" "${REPO_URL%.git}/archive/${BRANCH}.tar.gz"
    mkdir -p "$WORKDIR/src"
    tar -xzf "$WORKDIR/archive.tar.gz" -C "$WORKDIR/src" --strip-components=1
}

clone_repo() {
    rm -rf "$WORKDIR"
    mkdir -p "$WORKDIR"
    if command -v git >/dev/null 2>&1; then
        local clone_url
        clone_url="$(build_clone_url "$REPO_URL")"
        if ! GIT_TERMINAL_PROMPT=0 git clone --depth 1 --branch "$BRANCH" "$clone_url" "$WORKDIR/src" >/dev/null 2>&1; then
            if [ -n "${GIT_TOKEN:-}" ]; then
                echo "[!] Не удалось клонировать репозиторий. Проверьте URL и доступ (токен)." >&2
                exit 1
            fi
            echo "[!] Не удалось выполнить git clone. Перехожу к загрузке архива." >&2
            download_archive
        fi
    else
        if [ -n "${GIT_TOKEN:-}" ]; then
            echo "[!] Для установки из приватного репозитория требуется наличие git на устройстве." >&2
            exit 1
        fi
        download_archive
    fi
}

prepare_local_source() {
    local src
    src="${SOURCE_DIR:-$SCRIPT_DIR}"
    if [ ! -d "$src" ]; then
        echo "[!] Локальная директория с исходниками '$src' не найдена." >&2
        exit 1
    fi

    rm -rf "$WORKDIR"
    mkdir -p "$WORKDIR/src"
    cp -R "$src"/. "$WORKDIR/src/"
}

prepare_source() {
    if [ "${USE_LOCAL_SOURCE:-0}" = "1" ]; then
        prepare_local_source
    else
        clone_repo
    fi
}

install_files() {
    mkdir -p "$WWW_DST" "$CGI_DST" "$LOCK_DIR"
    cp -a "$WORKDIR/src/www/." "$WWW_DST/"
    touch "$SESS_FILE"
    chmod 644 "$SESS_FILE"
    for script in "$CGI_DST"/*.sh; do
        [ -e "$script" ] || continue
        chmod 755 "$script"
    done
    [ -e "$WWW_DST/admin.html" ] && chmod 755 "$WWW_DST/admin.html"
}

setup_config() {
    if ! uci -q show wifi_auth.settings >/dev/null 2>&1; then
        uci set wifi_auth.settings=auth
    fi

    if [ -f "$CONFIG_DST" ]; then
        CODE="$(uci -q get wifi_auth.settings.code 2>/dev/null || echo '5921')"
        DURATION="$(uci -q get wifi_auth.settings.duration 2>/dev/null || echo '60')"
        ENABLED="$(uci -q get wifi_auth.settings.enabled 2>/dev/null || echo '1')"
    else
        CODE='5921'
        DURATION='60'
        ENABLED='0'
    fi

    uci set wifi_auth.settings.code="${CODE}"
    uci set wifi_auth.settings.duration="${DURATION}"
    uci set wifi_auth.settings.enabled="${ENABLED}"
    uci set wifi_auth.settings.updated="$(date '+%Y-%m-%d %H:%M')"
    uci commit wifi_auth
}

setup_cron() {
    touch "$CRON_FILE"
    if ! grep -q "session_check.sh" "$CRON_FILE"; then
        echo "*/5 * * * * /www/cgi-bin/session_check.sh >/dev/null 2>&1" >> "$CRON_FILE"
        /etc/init.d/cron restart >/dev/null 2>&1 || true
    fi
}

finalize() {
    if [ -x /etc/init.d/uhttpd ]; then
        /etc/init.d/uhttpd reload >/dev/null 2>&1 || true
    fi
    if [ -x /etc/init.d/nodogsplash ]; then
        /etc/init.d/nodogsplash restart >/dev/null 2>&1 || true
    fi
    cat <<MSG
[+] Установка завершена.
    Портал доступен по адресу: http://192.168.9.1/
    Админ-панель: http://192.168.9.1/admin.html (рекомендуется защитить Basic Auth).
MSG
}

require_root
require_tool uci
prepare_source
install_files
setup_config
setup_cron
finalize
