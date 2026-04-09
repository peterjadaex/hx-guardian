#!/bin/zsh --no-rcs
# =============================================================================
# Rule:      system_settings_rae_disable
# Source:    800-53r5_high
# Category:  System Settings
# Standards: cis_lvl2, cisv8, 800-53r5_high
# Description: Disable Remote Apple Events
# =============================================================================
# Auto-generated - do not edit manually.
# Exit codes: 0=PASS/OK  1=FAIL/ERROR  2=NOT_APPLICABLE  3=ERROR(root)

if [[ $EUID -ne 0 ]]; then
    printf '{"rule":"system_settings_rae_disable","status":"ERROR","message":"Must be run as root"}\n'
    exit 3
fi

arch=$(/usr/bin/arch)
CURRENT_USER=$(/usr/bin/defaults read /Library/Preferences/com.apple.loginwindow lastUserName)
CURR_USER_UID=$(/usr/bin/id -u $CURRENT_USER)

/usr/sbin/systemsetup -setremoteappleevents off
/bin/launchctl disable system/com.apple.AEServer

printf '{"rule":"system_settings_rae_disable","action":"EXECUTED","message":"Fix applied"}\n'
exit 0
