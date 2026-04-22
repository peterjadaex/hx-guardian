#!/bin/zsh --no-rcs
# =============================================================================
# Rule:      pwpolicy_minimum_lifetime_enforce (UNDO)
# Category:  Password Policy
# Description: Clear all account policies. Note: the fix writes a composite
#              policy shared with other pwpolicy rules; undoing one undoes all.
# =============================================================================
# Exit codes: 0=OK  1=ERROR  3=ERROR(root)

if [[ $EUID -ne 0 ]]; then
    printf '{"rule":"pwpolicy_minimum_lifetime_enforce","status":"ERROR","message":"Must be run as root"}\n'
    exit 3
fi

/usr/bin/pwpolicy -n /Local/Default -clearaccountpolicies

printf '{"rule":"pwpolicy_minimum_lifetime_enforce","action":"UNDONE","message":"Undo applied"}\n'
exit 0
