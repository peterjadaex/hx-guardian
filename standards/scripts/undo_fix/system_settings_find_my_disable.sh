#!/bin/zsh --no-rcs
# =============================================================================
# Rule:      system_settings_find_my_disable (UNDO)
# Category:  System Settings
# Description: Delete the Find My Managed Preferences overrides.
# =============================================================================
# Exit codes: 0=OK  1=ERROR  3=ERROR(root)

if [[ $EUID -ne 0 ]]; then
    printf '{"rule":"system_settings_find_my_disable","status":"ERROR","message":"Must be run as root"}\n'
    exit 3
fi

/usr/bin/defaults delete "/Library/Managed Preferences/com.apple.applicationaccess" allowFindMyDevice 2>/dev/null
/usr/bin/defaults delete "/Library/Managed Preferences/com.apple.applicationaccess" allowFindMyFriends 2>/dev/null
/usr/bin/defaults delete "/Library/Managed Preferences/com.apple.icloud.managed" DisableFMMiCloudSetting 2>/dev/null

printf '{"rule":"system_settings_find_my_disable","action":"UNDONE","message":"Undo applied"}\n'
exit 0
