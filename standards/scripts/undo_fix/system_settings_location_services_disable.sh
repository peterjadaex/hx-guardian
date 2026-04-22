#!/bin/zsh --no-rcs
# =============================================================================
# Rule:      system_settings_location_services_disable (UNDO)
# Category:  System Settings
# Description: Re-enable Location Services.
# =============================================================================
# Exit codes: 0=OK  1=ERROR  3=ERROR(root)

if [[ $EUID -ne 0 ]]; then
    printf '{"rule":"system_settings_location_services_disable","status":"ERROR","message":"Must be run as root"}\n'
    exit 3
fi

/usr/bin/defaults write /var/db/locationd/Library/Preferences/ByHost/com.apple.locationd LocationServicesEnabled -bool true
pid=$(/bin/launchctl print system | /usr/bin/awk '/\tcom.apple.locationd/ {print $1}')
[[ -n $pid ]] && kill -9 $pid

printf '{"rule":"system_settings_location_services_disable","action":"UNDONE","message":"Undo applied"}\n'
exit 0
