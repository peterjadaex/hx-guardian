#!/bin/zsh --no-rcs
# =============================================================================
# Rule:      os_policy_banner_ssh_configure (UNDO)
# Category:  Operating System
# Description: Remove /etc/banner (the policy banner file created by the fix).
# =============================================================================
# Exit codes: 0=OK  1=ERROR  3=ERROR(root)

if [[ $EUID -ne 0 ]]; then
    printf '{"rule":"os_policy_banner_ssh_configure","status":"ERROR","message":"Must be run as root"}\n'
    exit 3
fi

/bin/rm -f /etc/banner

printf '{"rule":"os_policy_banner_ssh_configure","action":"UNDONE","message":"Undo applied"}\n'
exit 0
