#!/bin/zsh --no-rcs
# =============================================================================
# Rule:      os_httpd_disable (UNDO)
# Category:  Operating System
# Description: Re-enable the Apache httpd LaunchDaemon.
# =============================================================================
# Exit codes: 0=OK  1=ERROR  3=ERROR(root)

if [[ $EUID -ne 0 ]]; then
    printf '{"rule":"os_httpd_disable","status":"ERROR","message":"Must be run as root"}\n'
    exit 3
fi

arch=$(/usr/bin/arch)
CURRENT_USER=$(/usr/bin/defaults read /Library/Preferences/com.apple.loginwindow lastUserName)
CURR_USER_UID=$(/usr/bin/id -u $CURRENT_USER)

/bin/launchctl enable system/org.apache.httpd

printf '{"rule":"os_httpd_disable","action":"UNDONE","message":"Undo applied"}\n'
exit 0
