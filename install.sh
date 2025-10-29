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

PKG_MANAGER=""
PKG_IS_APK=0
PKG_REFRESHED=0

if command -v apk >/dev/null 2>&1; then
    PKG_MANAGER="apk"
    PKG_IS_APK=1
elif command -v opkg >/dev/null 2>&1; then
    PKG_MANAGER="opkg"
fi

msg() {
    printf '\033[32;1m%s\033[0m\n' "$1"
}

warn() {
    printf '\033[33;1m%s\033[0m\n' "$1" >&2
}

err() {
    printf '\033[31;1m%s\033[0m\n' "$1" >&2
    exit 1
}

pkg_is_installed() {
    [ -n "$PKG_MANAGER" ] || return 1
    local pkg="$1"

    case "$PKG_MANAGER" in
        apk)
            apk info -e "$pkg" >/dev/null 2>&1
            ;;
        opkg)
            opkg status "$pkg" >/dev/null 2>&1
            ;;
        *)
            return 1
            ;;
    esac
}

pkg_update() {
    [ -n "$PKG_MANAGER" ] || return 0
    if [ "$PKG_REFRESHED" -eq 1 ]; then
        return 0
    fi

    case "$PKG_MANAGER" in
        apk)
            msg "Обновляю списки пакетов apk..."
            if ! apk update >/dev/null 2>&1; then
                warn "Не удалось обновить списки пакетов apk."
            fi
            ;;
        opkg)
            msg "Обновляю списки пакетов opkg..."
            if ! opkg update >/dev/null 2>&1; then
                warn "Не удалось обновить списки пакетов opkg."
            fi
            ;;
    esac

    PKG_REFRESHED=1
}

pkg_install() {
    [ -n "$PKG_MANAGER" ] || return 1
    local pkg="$1"

    if pkg_is_installed "$pkg"; then
        return 0
    fi

    case "$PKG_MANAGER" in
        apk)
            if ! apk add "$pkg" >/dev/null 2>&1; then
                err "Не удалось установить пакет '$pkg' через apk."
            fi
            ;;
        opkg)
            if ! opkg install "$pkg" >/dev/null 2>&1; then
                err "Не удалось установить пакет '$pkg' через opkg."
            fi
            ;;
    esac
}

check_network() {
    [ "${USE_LOCAL_SOURCE:-0}" = "1" ] && return 0

    if command -v nslookup >/dev/null 2>&1; then
        if ! nslookup openwrt.org >/dev/null 2>&1; then
            err "DNS не отвечает. Проверьте подключение к интернету."
        fi
        return 0
    fi

    if command -v ping >/dev/null 2>&1; then
        if ! ping -c 1 -W 3 8.8.8.8 >/dev/null 2>&1; then
            err "Не удалось проверить соединение с интернетом (ping 8.8.8.8)."
        fi
        return 0
    fi

    warn "Не найдено nslookup или ping для проверки сети. Пропускаю проверку."
}

check_system() {
    if [ -r /tmp/sysinfo/model ]; then
        msg "Маршрутизатор: $(cat /tmp/sysinfo/model)"
    fi

    if [ -r /etc/openwrt_release ]; then
        local release major
        release=$(grep "^DISTRIB_RELEASE" /etc/openwrt_release | cut -d"'" -f2)
        [ -n "$release" ] && msg "Версия OpenWrt: $release"
        major=$(printf '%s' "$release" | cut -d'.' -f1)
        if [ -n "$major" ] && [ "$major" -lt 24 ]; then
            err "Требуется OpenWrt версии 24.10 или новее."
        fi
        case "$release" in
            23.*)
                err "OpenWrt 23.x не поддерживается."
                ;;
        esac
    else
        warn "Не удалось определить версию OpenWrt."
    fi

    if df /overlay >/dev/null 2>&1; then
        local available required
        available=$(df /overlay | awk 'NR==2 {print $4}')
        required=4096
        if [ -n "$available" ] && [ "$available" -lt "$required" ]; then
            err "Недостаточно свободного места во флеше (нужно ~4 МБ)."
        fi
    else
        warn "Не удалось проверить свободное место на разделе overlay."
    fi

    check_network
}

ensure_dependencies() {
    local required_packages=""

    if ! command -v uhttpd >/dev/null 2>&1 && [ ! -x /etc/init.d/uhttpd ]; then
        required_packages="$required_packages uhttpd"
    fi

    if ! command -v nodogsplash >/dev/null 2>&1 && \
       ! command -v nodogsplashctl >/dev/null 2>&1 && \
       [ ! -x /etc/init.d/nodogsplash ]; then
        required_packages="$required_packages nodogsplash"
    fi

    if [ -z "$required_packages" ]; then
        return 0
    fi

    if [ -z "$PKG_MANAGER" ]; then
        warn "Не удалось определить пакетный менеджер. Установите вручную: $required_packages"
        return 0
    fi

    pkg_update
    for pkg in $required_packages; do
        pkg_install "$pkg"
    done
}

require_root() {
    if [ "$(id -u)" != "0" ]; then
        err "Запустите установку от имени root."
    fi
}

require_tool() {
    local tool="$1"
    if ! command -v "$tool" >/dev/null 2>&1; then
        err "Требуется установить утилиту '$tool'."
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

download_file() {
    local url="$1"
    local dest="$2"
    local tried=0

    if command -v curl >/dev/null 2>&1; then
        tried=1
        if curl -fsSL "$url" -o "$dest"; then
            return 0
        fi
    fi

    if command -v wget >/dev/null 2>&1; then
        tried=1
        if wget -qO "$dest" "$url"; then
            return 0
        fi
        if wget --no-check-certificate -qO "$dest" "$url"; then
            return 0
        fi
    fi

    if command -v uclient-fetch >/dev/null 2>&1; then
        tried=1
        if uclient-fetch -q -O "$dest" "$url"; then
            return 0
        fi
        if uclient-fetch --no-check-certificate -q -O "$dest" "$url"; then
            return 0
        fi
    fi

    if [ "$tried" -eq 0 ]; then
        err "Не найден ни один из загрузчиков: curl, wget или uclient-fetch."
    else
        err "Не удалось загрузить '$url'."
    fi
}

download_archive() {
    require_tool tar
    msg "Загружаю архив репозитория..."
    rm -rf "$WORKDIR/src"
    mkdir -p "$WORKDIR/src"

    local archive_url
    archive_url="${ARCHIVE_URL:-${REPO_URL%.git}/archive/${BRANCH}.tar.gz}"

    download_file "$archive_url" "$WORKDIR/archive.tar.gz"
    # BusyBox tar не поддерживает --strip-components, поэтому распаковываем полностью
    tar -xzf "$WORKDIR/archive.tar.gz" -C "$WORKDIR/src"
    # Переносим содержимое из вложенной директории (pvzrouter-main/*) в src/
    mv "$WORKDIR/src"/*/* "$WORKDIR/src"/ 2>/dev/null || true
}

clone_repo() {
    rm -rf "$WORKDIR"
    mkdir -p "$WORKDIR"
    if command -v git >/dev/null 2>&1; then
        local clone_url
        clone_url="$(build_clone_url "$REPO_URL")"
        if ! GIT_TERMINAL_PROMPT=0 git clone --depth 1 --branch "$BRANCH" "$clone_url" "$WORKDIR/src" >/dev/null 2>&1; then
            if [ -n "${GIT_TOKEN:-}" ]; then
                err "Не удалось клонировать репозиторий. Проверьте URL и доступ (токен)."
            fi
            warn "Не удалось выполнить git clone. Перехожу к загрузке архива."
            download_archive
        fi
    else
        if [ -n "${GIT_TOKEN:-}" ]; then
            err "Для установки из приватного репозитория требуется наличие git на устройстве."
        fi
        download_archive
    fi
}

prepare_local_source() {
    local src
    src="${SOURCE_DIR:-$SCRIPT_DIR}"
    if [ ! -d "$src" ]; then
        err "Локальная директория с исходниками '$src' не найдена."
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
    msg "Копирую файлы портала..."
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
    msg "Настраиваю конфигурацию wifi_auth..."
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
    msg "Обновляю задания cron..."
    touch "$CRON_FILE"
    if ! grep -q "session_check.sh" "$CRON_FILE"; then
        echo "*/5 * * * * /www/cgi-bin/session_check.sh >/dev/null 2>&1" >> "$CRON_FILE"
        /etc/init.d/cron restart >/dev/null 2>&1 || true
    fi
}

finalize() {
    msg "Перезапускаю веб-интерфейс и портал..."
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

main() {
    require_root
    require_tool uci
    check_system
    ensure_dependencies
    prepare_source
    install_files
    setup_config
    setup_cron
    finalize
}

main "$@"
