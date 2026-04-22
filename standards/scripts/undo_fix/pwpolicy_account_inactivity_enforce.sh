#!/bin/zsh --no-rcs
# =============================================================================
# Rule:      pwpolicy_account_inactivity_enforce (UNDO)
# Category:  Password Policy
# Description: Clear all account policies (shared composite — see note).
# =============================================================================
# Exit codes: 0=OK  1=ERROR  3=ERROR(root)

if [[ $EUID -ne 0 ]]; then
    printf '{"rule":"pwpolicy_account_inactivity_enforce","status":"ERROR","message":"Must be run as root"}\n'
    exit 3
fi

/usr/bin/pwpolicy -n /Local/Default -clearaccountpolicies

printf '{"rule":"pwpolicy_account_inactivity_enforce","action":"UNDONE","message":"Undo applied"}\n'
exit 0
