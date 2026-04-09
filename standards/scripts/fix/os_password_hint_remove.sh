#!/bin/zsh --no-rcs
# =============================================================================
# Rule:      os_password_hint_remove
# Source:    cisv8
# Category:  Operating System
# Standards: cis_lvl2, cisv8
# Description: Remove Password Hint From User Accounts
# =============================================================================
# Auto-generated - do not edit manually.
# Exit codes: 0=PASS/OK  1=FAIL/ERROR  2=NOT_APPLICABLE  3=ERROR(root)

if [[ $EUID -ne 0 ]]; then
    printf '{"rule":"os_password_hint_remove","status":"ERROR","message":"Must be run as root"}\n'
    exit 3
fi

arch=$(/usr/bin/arch)
CURRENT_USER=$(/usr/bin/defaults read /Library/Preferences/com.apple.loginwindow lastUserName)
CURR_USER_UID=$(/usr/bin/id -u $CURRENT_USER)

for u in $(/usr/bin/dscl . -list /Users UniqueID | /usr/bin/awk '$2 > 500 {print $1}'); do
  /usr/bin/dscl . -delete /Users/$u hint
done

printf '{"rule":"os_password_hint_remove","action":"EXECUTED","message":"Fix applied"}\n'
exit 0
