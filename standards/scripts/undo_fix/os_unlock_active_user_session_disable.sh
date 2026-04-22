#!/bin/zsh --no-rcs
# =============================================================================
# Rule:      os_unlock_active_user_session_disable (UNDO)
# Category:  Operating System
# Description: Restore the macOS default screensaver authorization
#              (authenticate-session-owner-or-admin).
# =============================================================================
# Exit codes: 0=OK  1=ERROR  3=ERROR(root)

if [[ $EUID -ne 0 ]]; then
    printf '{"rule":"os_unlock_active_user_session_disable","status":"ERROR","message":"Must be run as root"}\n'
    exit 3
fi

arch=$(/usr/bin/arch)
CURRENT_USER=$(/usr/bin/defaults read /Library/Preferences/com.apple.loginwindow lastUserName)
CURR_USER_UID=$(/usr/bin/id -u $CURRENT_USER)

/usr/bin/security -q authorizationdb write system.login.screensaver "authenticate-session-owner-or-admin" 2>&1 >/dev/null

printf '{"rule":"os_unlock_active_user_session_disable","action":"UNDONE","message":"Undo applied"}\n'
exit 0
