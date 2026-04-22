#!/bin/zsh --no-rcs
# =============================================================================
# Rule:      system_settings_loginwindow_loginwindowtext_enable (UNDO)
# Category:  System Settings
# Description: Delete the LoginwindowText override from Managed Preferences.
# =============================================================================
# Exit codes: 0=OK  1=ERROR  3=ERROR(root)

if [[ $EUID -ne 0 ]]; then
    printf '{"rule":"system_settings_loginwindow_loginwindowtext_enable","status":"ERROR","message":"Must be run as root"}\n'
    exit 3
fi

/usr/bin/defaults delete "/Library/Managed Preferences/com.apple.loginwindow" LoginwindowText 2>/dev/null

printf '{"rule":"system_settings_loginwindow_loginwindowtext_enable","action":"UNDONE","message":"Undo applied"}\n'
exit 0
