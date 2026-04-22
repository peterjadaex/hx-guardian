#!/bin/zsh --no-rcs
# =============================================================================
# Rule:      os_time_server_enabled (UNDO)
# Category:  Operating System
# Description: Unload the timed LaunchDaemon (disables time sync).
# =============================================================================
# Exit codes: 0=OK  1=ERROR  3=ERROR(root)

if [[ $EUID -ne 0 ]]; then
    printf '{"rule":"os_time_server_enabled","status":"ERROR","message":"Must be run as root"}\n'
    exit 3
fi

arch=$(/usr/bin/arch)
CURRENT_USER=$(/usr/bin/defaults read /Library/Preferences/com.apple.loginwindow lastUserName)
CURR_USER_UID=$(/usr/bin/id -u $CURRENT_USER)

/bin/launchctl unload -w /System/Library/LaunchDaemons/com.apple.timed.plist 2>/dev/null

printf '{"rule":"os_time_server_enabled","action":"UNDONE","message":"Undo applied"}\n'
exit 0
