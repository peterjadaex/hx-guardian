#!/bin/zsh --no-rcs
# =============================================================================
# Rule:      os_policy_banner_loginwindow_enforce (UNDO)
# Category:  Operating System
# Description: Remove /Library/Security/PolicyBanner.rtfd created by the fix.
# =============================================================================
# Exit codes: 0=OK  1=ERROR  3=ERROR(root)

if [[ $EUID -ne 0 ]]; then
    printf '{"rule":"os_policy_banner_loginwindow_enforce","status":"ERROR","message":"Must be run as root"}\n'
    exit 3
fi

/bin/rm -rf /Library/Security/PolicyBanner.rtfd

printf '{"rule":"os_policy_banner_loginwindow_enforce","action":"UNDONE","message":"Undo applied"}\n'
exit 0
