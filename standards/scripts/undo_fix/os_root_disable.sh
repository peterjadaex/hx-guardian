#!/bin/zsh --no-rcs
# =============================================================================
# Rule:      os_root_disable (UNDO)
# Category:  Operating System
# Description: Remove the UserShell override on root (returns to macOS default
#              shell lookup). Note: root remains disabled at the OS level unless
#              separately re-enabled via Directory Utility.
# =============================================================================
# Exit codes: 0=OK  1=ERROR  3=ERROR(root)

if [[ $EUID -ne 0 ]]; then
    printf '{"rule":"os_root_disable","status":"ERROR","message":"Must be run as root"}\n'
    exit 3
fi

arch=$(/usr/bin/arch)
CURRENT_USER=$(/usr/bin/defaults read /Library/Preferences/com.apple.loginwindow lastUserName)
CURR_USER_UID=$(/usr/bin/id -u $CURRENT_USER)

/usr/bin/dscl . -delete /Users/root UserShell 2>/dev/null

printf '{"rule":"os_root_disable","action":"UNDONE","message":"Undo applied"}\n'
exit 0
