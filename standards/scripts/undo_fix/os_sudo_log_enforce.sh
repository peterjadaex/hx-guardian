#!/bin/zsh --no-rcs
# =============================================================================
# Rule:      os_sudo_log_enforce (UNDO)
# Category:  Operating System
# Description: Remove the 'Defaults log_allowed' entry from
#              /etc/sudoers.d/mscp. Any '!log_allowed' lines the fix commented
#              out in other sudoers files are NOT un-commented.
# =============================================================================
# Exit codes: 0=OK  1=ERROR  3=ERROR(root)

if [[ $EUID -ne 0 ]]; then
    printf '{"rule":"os_sudo_log_enforce","status":"ERROR","message":"Must be run as root"}\n'
    exit 3
fi

if [[ -f /etc/sudoers.d/mscp ]]; then
    /usr/bin/sed -i.undo.bak '/^Defaults log_allowed$/d' /etc/sudoers.d/mscp
    if [[ ! -s /etc/sudoers.d/mscp ]]; then
        /bin/rm -f /etc/sudoers.d/mscp /etc/sudoers.d/mscp.undo.bak
    fi
fi

printf '{"rule":"os_sudo_log_enforce","action":"UNDONE","message":"Undo applied"}\n'
exit 0
