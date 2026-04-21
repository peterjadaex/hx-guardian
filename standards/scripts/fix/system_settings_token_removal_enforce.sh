#!/bin/zsh --no-rcs
# =============================================================================
# Rule:      system_settings_token_removal_enforce
# Source:    800-53r5_high
# Category:  System Settings
# Standards: 800-53r5_high
# Description: Configure User Session Lock When a Smart Token is Removed
# =============================================================================
# Exit codes: 0=PASS/OK  1=FAIL/ERROR  2=NOT_APPLICABLE  3=ERROR(root)

if [[ $EUID -ne 0 ]]; then
    printf '{"rule":"system_settings_token_removal_enforce","status":"ERROR","message":"Must be run as root"}\n'
    exit 3
fi

mkdir -p "/Library/Managed Preferences"
/usr/bin/defaults write "/Library/Managed Preferences/com.apple.security.smartcard" \
    tokenRemovalAction -int 1

if [[ $? -eq 0 ]]; then
    printf '{"rule":"system_settings_token_removal_enforce","action":"EXECUTED","message":"Fix applied"}\n'
    exit 0
else
    printf '{"rule":"system_settings_token_removal_enforce","action":"FAILED","message":"defaults write failed"}\n'
    exit 1
fi
