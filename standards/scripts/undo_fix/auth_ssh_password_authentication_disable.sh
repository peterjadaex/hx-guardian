#!/bin/zsh --no-rcs
# =============================================================================
# Rule:      auth_ssh_password_authentication_disable (UNDO)
# Category:  Authentication
# Description: Remove 'passwordauthentication no' and 'kbdinteractiveauthentication
#              no' lines from 01-mscp-sshd.conf.
# =============================================================================
# Exit codes: 0=OK  1=ERROR  3=ERROR(root)

if [[ $EUID -ne 0 ]]; then
    printf '{"rule":"auth_ssh_password_authentication_disable","status":"ERROR","message":"Must be run as root"}\n'
    exit 3
fi

include_dir=$(/usr/bin/awk '/^Include/ {print $2}' /etc/ssh/sshd_config | /usr/bin/tr -d '*')

if [[ -n $include_dir && -f "${include_dir}01-mscp-sshd.conf" ]]; then
    /usr/bin/sed -i.undo.bak \
        -e '/^passwordauthentication no$/d' \
        -e '/^kbdinteractiveauthentication no$/d' \
        "${include_dir}01-mscp-sshd.conf"
fi

printf '{"rule":"auth_ssh_password_authentication_disable","action":"UNDONE","message":"Undo applied"}\n'
exit 0
