#!/bin/zsh --no-rcs
# =============================================================================
# Rule:      os_sshd_unused_connection_timeout_configure (UNDO)
# Category:  Operating System
# Description: Remove 'unusedconnectiontimeout 900' from 01-mscp-sshd.conf.
# =============================================================================
# Exit codes: 0=OK  1=ERROR  3=ERROR(root)

if [[ $EUID -ne 0 ]]; then
    printf '{"rule":"os_sshd_unused_connection_timeout_configure","status":"ERROR","message":"Must be run as root"}\n'
    exit 3
fi

include_dir=$(/usr/bin/awk '/^Include/ {print $2}' /etc/ssh/sshd_config | /usr/bin/tr -d '*')

if [[ -n $include_dir && -f "${include_dir}01-mscp-sshd.conf" ]]; then
    /usr/bin/sed -i.undo.bak '/^unusedconnectiontimeout 900$/d' "${include_dir}01-mscp-sshd.conf"
fi

printf '{"rule":"os_sshd_unused_connection_timeout_configure","action":"UNDONE","message":"Undo applied"}\n'
exit 0
