#!/bin/ash
CONFIG_FILE="/etc/config/wifi_auth"
SESSION_FILE="/tmp/active_sessions.txt"
WHITELIST_FILE="/etc/nodogsplash/whitelist_macs"

ensure_config() {
    if [ ! -f "$CONFIG_FILE" ]; then
        mkdir -p "$(dirname "$CONFIG_FILE")"
        cat <<'CFG' > "$CONFIG_FILE"
code='0000'
duration='60'
nds_enabled='0'
CFG
    fi
}

ensure_session_store() {
    if [ ! -f "$SESSION_FILE" ]; then
        mkdir -p "$(dirname "$SESSION_FILE")"
        : > "$SESSION_FILE"
    fi
    if [ ! -f "$WHITELIST_FILE" ]; then
        mkdir -p "$(dirname "$WHITELIST_FILE")"
        : > "$WHITELIST_FILE"
    fi
}

get_config_value() {
    local key="$1"
    ensure_config
    sed -n "s/^${key}='\(.*\)'$/\1/p" "$CONFIG_FILE" | tail -n 1
}

write_config() {
    local code="$1"
    local duration="$2"
    local nds_enabled="$3"
    cat <<CFG > "$CONFIG_FILE"
code='${code}'
duration='${duration}'
nds_enabled='${nds_enabled}'
CFG
}

send_json() {
    local payload="$1"
    printf 'Content-Type: application/json; charset=utf-8\n\n%s' "$payload"
}

json_escape() {
    printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g'
}

read_body() {
    cat
}

parse_json_string() {
    local key="$1"
    local data="$2"
    printf '%s' "$data" | sed -n "s/.*\"${key}\"[[:space:]]*:[[:space:]]*\"\([^\"]*\)\".*/\1/p"
}

parse_json_number() {
    local key="$1"
    local data="$2"
    printf '%s' "$data" | sed -n "s/.*\"${key}\"[[:space:]]*:[[:space:]]*\([0-9]\+\).*/\1/p"
}

uppercase_mac() {
    printf '%s' "$1" | tr 'a-f' 'A-F'
}

remove_session_for_mac() {
    local mac="$1"
    [ -f "$SESSION_FILE" ] || return 0
    grep -vi "^${mac} " "$SESSION_FILE" > "${SESSION_FILE}.tmp" && mv "${SESSION_FILE}.tmp" "$SESSION_FILE"
}

append_session() {
    local mac="$1"
    local expiry="$2"
    ensure_session_store
    remove_session_for_mac "$mac"
    printf '%s %s\n' "$mac" "$expiry" >> "$SESSION_FILE"
}

mac_in_whitelist() {
    local mac="$1"
    [ -f "$WHITELIST_FILE" ] || return 1
    grep -qi "^${mac}$" "$WHITELIST_FILE"
}

add_whitelist_mac() {
    local mac="$1"
    ensure_session_store
    if ! mac_in_whitelist "$mac"; then
        printf '%s\n' "$mac" >> "$WHITELIST_FILE"
    fi
}

count_sessions() {
    [ -f "$SESSION_FILE" ] || { printf '0'; return; }
    grep -c '^[0-9A-F:][0-9A-F:]* ' "$SESSION_FILE" 2>/dev/null || printf '0'
}

get_nds_enabled_flag() {
    local value
    value="$(get_config_value nds_enabled)"
    if [ -n "$value" ]; then
        printf '%s' "$value"
    else
        printf '0'
    fi
}
