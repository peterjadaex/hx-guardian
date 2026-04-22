#!/bin/zsh --no-rcs
# =============================================================================
# Rule:      system_settings_bluetooth_sharing_disable (UNDO)
# Category:  System Settings
# Description: Delete the PrefKeyServicesEnabled override for the active user.
# =============================================================================
# Exit codes: 0=OK  1=ERROR  3=ERROR(root)

if [[ $EUID -ne 0 ]]; then
    printf '{"rule":"system_settings_bluetooth_sharing_disable","status":"ERROR","message":"Must be run as root"}\n'
    exit 3
fi

CURRENT_USER=$(/usr/bin/defaults read /Library/Preferences/com.apple.loginwindow lastUserName)

/usr/bin/sudo -u "$CURRENT_USER" /usr/bin/defaults -currentHost delete com.apple.Bluetooth PrefKeyServicesEnabled 2>/dev/null

printf '{"rule":"system_settings_bluetooth_sharing_disable","action":"UNDONE","message":"Undo applied"}\n'
exit 0
