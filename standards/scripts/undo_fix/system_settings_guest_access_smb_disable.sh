#!/bin/zsh --no-rcs
# =============================================================================
# Rule:      system_settings_guest_access_smb_disable (UNDO)
# Category:  System Settings
# Description: Re-enable Guest access to SMB shares.
# =============================================================================
# Exit codes: 0=OK  1=ERROR  3=ERROR(root)

if [[ $EUID -ne 0 ]]; then
    printf '{"rule":"system_settings_guest_access_smb_disable","status":"ERROR","message":"Must be run as root"}\n'
    exit 3
fi

/usr/sbin/sysadminctl -smbGuestAccess on 2>/dev/null

printf '{"rule":"system_settings_guest_access_smb_disable","action":"UNDONE","message":"Undo applied"}\n'
exit 0
