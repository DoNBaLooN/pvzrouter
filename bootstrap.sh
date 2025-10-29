#!/bin/sh

set -eu

RAW_BASE="${RAW_BASE:-https://raw.githubusercontent.com/DoNBaLooN/pvzrouter}"
BRANCH="${BRANCH:-main}"
INSTALL_SCRIPT_URL="${INSTALL_SCRIPT_URL:-$RAW_BASE/$BRANCH/install.sh}"

cleanup() {
    [ -n "${TMP_INSTALLER:-}" ] && [ -f "$TMP_INSTALLER" ] && rm -f "$TMP_INSTALLER"
}

trap cleanup EXIT INT TERM HUP

require_tool() {
    local tool="$1"
    if ! command -v "$tool" >/dev/null 2>&1; then
        echo "[!] Требуется утилита '$tool' для загрузки установщика." >&2
        exit 1
    fi
}

download_with_wget() {
    require_tool wget
    wget -qO "$TMP_INSTALLER" "$INSTALL_SCRIPT_URL"
}

download_with_curl() {
    require_tool curl
    curl -fsSL "$INSTALL_SCRIPT_URL" -o "$TMP_INSTALLER"
}

download_installer() {
    if command -v wget >/dev/null 2>&1; then
        download_with_wget && return
    fi

    if command -v curl >/dev/null 2>&1; then
        download_with_curl && return
    fi

    echo "[!] Не удалось загрузить установщик: отсутствуют wget и curl." >&2
    exit 1
}

main() {
    echo "[*] Загружаю установочный скрипт из $INSTALL_SCRIPT_URL"
    TMP_INSTALLER="$(mktemp -t pvzrouter-install.XXXXXX)"
    download_installer
    echo "[*] Запускаю установщик"
    sh "$TMP_INSTALLER" "$@"
}

main "$@"
