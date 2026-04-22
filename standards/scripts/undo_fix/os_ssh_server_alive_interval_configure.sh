#!/bin/zsh --no-rcs
# =============================================================================
# Rule:      os_ssh_server_alive_interval_configure (UNDO)
# Category:  Operating System
# Description: Remove 'ServerAliveInterval 900' from 01-mscp-ssh.conf.
# =============================================================================
# Exit codes: 0=OK  1=ERROR  3=ERROR(root)

if [[ $EUID -ne 0 ]]; then
    printf '{"rule":"os_ssh_server_alive_interval_configure","status":"ERROR","message":"Must be run as root"}\n'
    exit 3
fi

include_dir=$(/usr/bin/awk '/^Include/ {print $2}' /etc/ssh/ssh_config | /usr/bin/tr -d '*')

if [[ -n $include_dir && -f "${include_dir}01-mscp-ssh.conf" ]]; then
    /usr/bin/sed -i.undo.bak '/^ServerAliveInterval 900$/Id' "${include_dir}01-mscp-ssh.conf"
fi

printf '{"rule":"os_ssh_server_alive_interval_configure","action":"UNDONE","message":"Undo applied"}\n'
exit 0
