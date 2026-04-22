#!/bin/zsh --no-rcs
# =============================================================================
# Rule:      system_settings_rae_disable (UNDO)
# Category:  System Settings
# Description: Re-enable Remote Apple Events.
# =============================================================================
# Exit codes: 0=OK  1=ERROR  3=ERROR(root)

if [[ $EUID -ne 0 ]]; then
    printf '{"rule":"system_settings_rae_disable","status":"ERROR","message":"Must be run as root"}\n'
    exit 3
fi

/usr/sbin/systemsetup -setremoteappleevents on >/dev/null 2>&1
/bin/launchctl enable system/com.apple.AEServer

printf '{"rule":"system_settings_rae_disable","action":"UNDONE","message":"Undo applied"}\n'
exit 0
