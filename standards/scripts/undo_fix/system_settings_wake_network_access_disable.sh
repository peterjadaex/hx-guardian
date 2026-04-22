#!/bin/zsh --no-rcs
# =============================================================================
# Rule:      system_settings_wake_network_access_disable (UNDO)
# Category:  System Settings
# Description: Re-enable Wake for Network Access.
# =============================================================================
# Exit codes: 0=OK  1=ERROR  3=ERROR(root)

if [[ $EUID -ne 0 ]]; then
    printf '{"rule":"system_settings_wake_network_access_disable","status":"ERROR","message":"Must be run as root"}\n'
    exit 3
fi

/usr/bin/pmset -a womp 1

printf '{"rule":"system_settings_wake_network_access_disable","action":"UNDONE","message":"Undo applied"}\n'
exit 0
