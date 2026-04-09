#!/bin/zsh --no-rcs
# =============================================================================
# Rule:      pwpolicy_account_inactivity_enforce
# Source:    800-53r5_high
# Category:  Password Policy
# Standards: cisv8, 800-53r5_high
# Description: Disable Accounts after *ODV* Days of Inactivity
# =============================================================================
# Auto-generated - do not edit manually.
# Exit codes: 0=PASS/OK  1=FAIL/ERROR  2=NOT_APPLICABLE  3=ERROR(root)

if [[ $EUID -ne 0 ]]; then
    printf '{"rule":"pwpolicy_account_inactivity_enforce","status":"ERROR","message":"Must be run as root"}\n'
    exit 3
fi

arch=$(/usr/bin/arch)
CURRENT_USER=$(/usr/bin/defaults read /Library/Preferences/com.apple.loginwindow lastUserName)
CURR_USER_UID=$(/usr/bin/id -u $CURRENT_USER)

/usr/bin/pwpolicy setaccountpolicies $pwpolicy_file

printf '{"rule":"pwpolicy_account_inactivity_enforce","action":"EXECUTED","message":"Fix applied"}\n'
exit 0
