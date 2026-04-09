#!/bin/zsh --no-rcs
# =============================================================================
# Rule:      os_guest_folder_removed
# Source:    cis_lvl2
# Category:  Operating System
# Standards: cis_lvl2
# Description: Remove Guest Folder if Present
# =============================================================================
# Auto-generated - do not edit manually.
# Exit codes: 0=PASS/OK  1=FAIL/ERROR  2=NOT_APPLICABLE  3=ERROR(root)

if [[ $EUID -ne 0 ]]; then
    printf '{"rule":"os_guest_folder_removed","status":"ERROR","message":"Must be run as root"}\n'
    exit 3
fi

arch=$(/usr/bin/arch)
CURRENT_USER=$(/usr/bin/defaults read /Library/Preferences/com.apple.loginwindow lastUserName)
CURR_USER_UID=$(/usr/bin/id -u $CURRENT_USER)

/bin/rm -Rf /Users/Guest

printf '{"rule":"os_guest_folder_removed","action":"EXECUTED","message":"Fix applied"}\n'
exit 0
