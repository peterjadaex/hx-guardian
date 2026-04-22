#!/bin/zsh --no-rcs
# =============================================================================
# Rule:      os_account_modification_disable (UNDO)
# Category:  Operating System
# Description: Remove the allowAccountModification override.
# =============================================================================
# Exit codes: 0=OK  1=ERROR  3=ERROR(root)

if [[ $EUID -ne 0 ]]; then
    printf '{"rule":"os_account_modification_disable","status":"ERROR","message":"Must be run as root"}\n'
    exit 3
fi

/usr/bin/defaults delete "/Library/Managed Preferences/com.apple.applicationaccess" allowAccountModification 2>/dev/null

printf '{"rule":"os_account_modification_disable","action":"UNDONE","message":"Undo applied"}\n'
exit 0
