#!/bin/zsh --no-rcs
# =============================================================================
# Rule:      system_settings_printer_sharing_disable (UNDO)
# Category:  System Settings
# Description: Re-enable printer sharing.
# =============================================================================
# Exit codes: 0=OK  1=ERROR  3=ERROR(root)

if [[ $EUID -ne 0 ]]; then
    printf '{"rule":"system_settings_printer_sharing_disable","status":"ERROR","message":"Must be run as root"}\n'
    exit 3
fi

/usr/sbin/cupsctl --share-printers

printf '{"rule":"system_settings_printer_sharing_disable","action":"UNDONE","message":"Undo applied"}\n'
exit 0
