#!/bin/zsh --no-rcs
# =============================================================================
# Rule:      system_settings_token_removal_enforce (UNDO)
# Category:  System Settings
# Description: Delete the tokenRemovalAction Managed Preferences override.
# =============================================================================
# Exit codes: 0=OK  1=ERROR  3=ERROR(root)

if [[ $EUID -ne 0 ]]; then
    printf '{"rule":"system_settings_token_removal_enforce","status":"ERROR","message":"Must be run as root"}\n'
    exit 3
fi

/usr/bin/defaults delete "/Library/Managed Preferences/com.apple.security.smartcard" tokenRemovalAction 2>/dev/null

printf '{"rule":"system_settings_token_removal_enforce","action":"UNDONE","message":"Undo applied"}\n'
exit 0
