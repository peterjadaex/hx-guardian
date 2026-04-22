#!/bin/zsh --no-rcs
# =============================================================================
# Rule:      os_sudo_timeout_configure (UNDO)
# Category:  Operating System
# Description: Remove the 'Defaults timestamp_timeout=0' entry from
#              /etc/sudoers.d/mscp. Lines the fix deleted from other sudoers
#              files are NOT restored — those were unknown prior state.
# =============================================================================
# Exit codes: 0=OK  1=ERROR  3=ERROR(root)

if [[ $EUID -ne 0 ]]; then
    printf '{"rule":"os_sudo_timeout_configure","status":"ERROR","message":"Must be run as root"}\n'
    exit 3
fi

if [[ -f /etc/sudoers.d/mscp ]]; then
    /usr/bin/sed -i.undo.bak '/^Defaults timestamp_timeout=0$/d' /etc/sudoers.d/mscp
    # If file is empty after removal, clean it up
    if [[ ! -s /etc/sudoers.d/mscp ]]; then
        /bin/rm -f /etc/sudoers.d/mscp /etc/sudoers.d/mscp.undo.bak
    fi
fi

printf '{"rule":"os_sudo_timeout_configure","action":"UNDONE","message":"Undo applied"}\n'
exit 0
