#!/bin/ash
. /www/cgi-bin/api/common.sh

ensure_session_store
: > "$SESSION_FILE"
nodogsplashctl clear >/dev/null 2>&1
send_json '{"ok":true,"msg":"Все сессии удалены"}'
