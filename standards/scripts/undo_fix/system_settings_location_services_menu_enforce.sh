#!/bin/zsh --no-rcs
# =============================================================================
# Rule:      system_settings_location_services_menu_enforce (UNDO)
# Category:  System Settings
# Description: Delete the ShowSystemServices override from com.apple.locationmenu.
# =============================================================================
# Exit codes: 0=OK  1=ERROR  3=ERROR(root)

if [[ $EUID -ne 0 ]]; then
    printf '{"rule":"system_settings_location_services_menu_enforce","status":"ERROR","message":"Must be run as root"}\n'
    exit 3
fi

/usr/bin/defaults delete /Library/Preferences/com.apple.locationmenu.plist ShowSystemServices 2>/dev/null

printf '{"rule":"system_settings_location_services_menu_enforce","action":"UNDONE","message":"Undo applied"}\n'
exit 0
