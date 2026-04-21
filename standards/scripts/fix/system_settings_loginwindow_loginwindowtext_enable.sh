#!/bin/zsh --no-rcs
# =============================================================================
# Rule:      system_settings_loginwindow_loginwindowtext_enable
# Source:    cisv8
# Category:  System Settings
# Standards: cis_lvl2, cisv8
# Description: Configure Login Window to Show A Custom Message
# =============================================================================
# Exit codes: 0=PASS/OK  1=FAIL/ERROR  2=NOT_APPLICABLE  3=ERROR(root)

if [[ $EUID -ne 0 ]]; then
    printf '{"rule":"system_settings_loginwindow_loginwindowtext_enable","status":"ERROR","message":"Must be run as root"}\n'
    exit 3
fi

mkdir -p "/Library/Managed Preferences"
/usr/bin/defaults write "/Library/Managed Preferences/com.apple.loginwindow" \
    LoginwindowText \
    "This system is for authorized use only. All activity is monitored and recorded. Unauthorized access is prohibited and subject to prosecution."

if [[ $? -eq 0 ]]; then
    printf '{"rule":"system_settings_loginwindow_loginwindowtext_enable","action":"EXECUTED","message":"Fix applied"}\n'
    exit 0
else
    printf '{"rule":"system_settings_loginwindow_loginwindowtext_enable","action":"FAILED","message":"defaults write failed"}\n'
    exit 1
fi
