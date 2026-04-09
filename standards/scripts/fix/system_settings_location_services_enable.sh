#!/bin/zsh --no-rcs
# =============================================================================
# Rule:      system_settings_location_services_enable
# Source:    cisv8
# Category:  System Settings
# Standards: cis_lvl2, cisv8
# Description: Enable Location Services
# =============================================================================
# Auto-generated - do not edit manually.
# Exit codes: 0=PASS/OK  1=FAIL/ERROR  2=NOT_APPLICABLE  3=ERROR(root)

if [[ $EUID -ne 0 ]]; then
    printf '{"rule":"system_settings_location_services_enable","status":"ERROR","message":"Must be run as root"}\n'
    exit 3
fi

arch=$(/usr/bin/arch)
CURRENT_USER=$(/usr/bin/defaults read /Library/Preferences/com.apple.loginwindow lastUserName)
CURR_USER_UID=$(/usr/bin/id -u $CURRENT_USER)

/usr/bin/defaults write /var/db/locationd/Library/Preferences/ByHost/com.apple.locationd LocationServicesEnabled -bool true; 
pid=$(/bin/launchctl print system | /usr/bin/awk '/\tcom.apple.locationd/ {print $1}')
kill -9 $pid

printf '{"rule":"system_settings_location_services_enable","action":"EXECUTED","message":"Fix applied"}\n'
exit 0
