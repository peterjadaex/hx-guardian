#!/bin/zsh --no-rcs
# =============================================================================
# Rule:      system_settings_location_services_menu_enforce
# Source:    cis_lvl2
# Category:  System Settings
# Standards: cis_lvl2
# Description: Ensure Location Services Is In the Menu Bar
# =============================================================================
# Auto-generated - do not edit manually.
# Exit codes: 0=PASS/OK  1=FAIL/ERROR  2=NOT_APPLICABLE  3=ERROR(root)

if [[ $EUID -ne 0 ]]; then
    printf '{"rule":"system_settings_location_services_menu_enforce","status":"ERROR","message":"Must be run as root"}\n'
    exit 3
fi

arch=$(/usr/bin/arch)
CURRENT_USER=$(/usr/bin/defaults read /Library/Preferences/com.apple.loginwindow lastUserName)
CURR_USER_UID=$(/usr/bin/id -u $CURRENT_USER)

/usr/bin/defaults write /Library/Preferences/com.apple.locationmenu.plist ShowSystemServices -bool true

printf '{"rule":"system_settings_location_services_menu_enforce","action":"EXECUTED","message":"Fix applied"}\n'
exit 0
