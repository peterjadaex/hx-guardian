#!/bin/zsh --no-rcs
# =============================================================================
# Rule:      os_sleep_and_display_sleep_apple_silicon_enable (UNDO)
# Category:  Operating System
# Description: Disable auto-sleep (set sleep=0 and displaysleep=0).
# =============================================================================
# Exit codes: 0=OK  1=ERROR  3=ERROR(root)

if [[ $EUID -ne 0 ]]; then
    printf '{"rule":"os_sleep_and_display_sleep_apple_silicon_enable","status":"ERROR","message":"Must be run as root"}\n'
    exit 3
fi

arch=$(/usr/bin/arch)
CURRENT_USER=$(/usr/bin/defaults read /Library/Preferences/com.apple.loginwindow lastUserName)
CURR_USER_UID=$(/usr/bin/id -u $CURRENT_USER)

rule_arch="arm64"
if [[ "$arch" != "$rule_arch" ]]; then
    printf '{"rule":"os_sleep_and_display_sleep_apple_silicon_enable","action":"NOT_APPLICABLE","message":"Requires arm64 architecture"}\n'
    exit 2
fi

/usr/bin/pmset -a sleep 0
/usr/bin/pmset -a displaysleep 0

printf '{"rule":"os_sleep_and_display_sleep_apple_silicon_enable","action":"UNDONE","message":"Undo applied"}\n'
exit 0
