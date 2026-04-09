#!/bin/zsh --no-rcs
# =============================================================================
# Rule:      os_sudoers_timestamp_type_configure
# Source:    800-53r5_high
# Category:  Operating System
# Standards: cis_lvl2, cisv8, 800-53r5_high
# Description: Configure Sudoers Timestamp Type
# =============================================================================
# Auto-generated - do not edit manually.
# Exit codes: 0=PASS/OK  1=FAIL/ERROR  2=NOT_APPLICABLE  3=ERROR(root)

if [[ $EUID -ne 0 ]]; then
    printf '{"rule":"os_sudoers_timestamp_type_configure","status":"ERROR","message":"Must be run as root"}\n'
    exit 3
fi

arch=$(/usr/bin/arch)
CURRENT_USER=$(/usr/bin/defaults read /Library/Preferences/com.apple.loginwindow lastUserName)
CURR_USER_UID=$(/usr/bin/id -u $CURRENT_USER)

/usr/bin/find /etc/sudoers* -type f -exec sed -i '' '/timestamp_type/d; /!tty_tickets/d' '{}' \;

printf '{"rule":"os_sudoers_timestamp_type_configure","action":"EXECUTED","message":"Fix applied"}\n'
exit 0
