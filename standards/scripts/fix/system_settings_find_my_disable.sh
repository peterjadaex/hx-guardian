#!/bin/zsh --no-rcs
# =============================================================================
# Rule:      system_settings_find_my_disable
# Source:    800-53r5_high
# Category:  System Settings
# Standards: cisv8, 800-53r5_high
# Description: Disable Find My Service
# =============================================================================
# Exit codes: 0=PASS/OK  1=FAIL/ERROR  2=NOT_APPLICABLE  3=ERROR(root)

if [[ $EUID -ne 0 ]]; then
    printf '{"rule":"system_settings_find_my_disable","status":"ERROR","message":"Must be run as root"}\n'
    exit 3
fi

mkdir -p "/Library/Managed Preferences"

/usr/bin/defaults write "/Library/Managed Preferences/com.apple.applicationaccess" \
    allowFindMyDevice -bool false
/usr/bin/defaults write "/Library/Managed Preferences/com.apple.applicationaccess" \
    allowFindMyFriends -bool false
/usr/bin/defaults write "/Library/Managed Preferences/com.apple.icloud.managed" \
    DisableFMMiCloudSetting -bool true

if [[ $? -eq 0 ]]; then
    printf '{"rule":"system_settings_find_my_disable","action":"EXECUTED","message":"Fix applied"}\n'
    exit 0
else
    printf '{"rule":"system_settings_find_my_disable","action":"FAILED","message":"defaults write failed"}\n'
    exit 1
fi
