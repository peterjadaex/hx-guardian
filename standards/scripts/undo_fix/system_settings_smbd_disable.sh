#!/bin/zsh --no-rcs
# =============================================================================
# Rule:      system_settings_smbd_disable (UNDO)
# Category:  System Settings
# Description: Re-enable the smbd LaunchDaemon.
# =============================================================================
# Exit codes: 0=OK  1=ERROR  3=ERROR(root)

if [[ $EUID -ne 0 ]]; then
    printf '{"rule":"system_settings_smbd_disable","status":"ERROR","message":"Must be run as root"}\n'
    exit 3
fi

/bin/launchctl enable system/com.apple.smbd

printf '{"rule":"system_settings_smbd_disable","action":"UNDONE","message":"Undo applied"}\n'
exit 0
