#!/bin/zsh --no-rcs
# =============================================================================
# Rule:      os_asl_log_files_permissions_configure
# Source:    800-53r5_high
# Category:  Operating System
# Standards: 800-53r5_high
# Description: Configure Apple System Log Files To Mode 640 or Less Permissive
# =============================================================================
# Auto-generated - do not edit manually.
# Exit codes: 0=PASS/OK  1=FAIL/ERROR  2=NOT_APPLICABLE  3=ERROR(root)

if [[ $EUID -ne 0 ]]; then
    printf '{"rule":"os_asl_log_files_permissions_configure","status":"ERROR","message":"Must be run as root"}\n'
    exit 3
fi

arch=$(/usr/bin/arch)
CURRENT_USER=$(/usr/bin/defaults read /Library/Preferences/com.apple.loginwindow lastUserName)
CURR_USER_UID=$(/usr/bin/id -u $CURRENT_USER)

/bin/chmod 640 $(/usr/bin/stat -f '%A:%N' $(/usr/bin/grep -e '^>' /etc/asl.conf /etc/asl/* | /usr/bin/awk '{ print $2 }') 2> /dev/null | /usr/bin/awk -F":" '!/640/{print $2}')

printf '{"rule":"os_asl_log_files_permissions_configure","action":"EXECUTED","message":"Fix applied"}\n'
exit 0
