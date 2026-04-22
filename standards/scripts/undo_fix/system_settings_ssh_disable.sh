#!/bin/zsh --no-rcs
# =============================================================================
# Rule:      system_settings_ssh_disable (UNDO)
# Category:  System Settings
# Description: Re-enable SSH (Remote Login).
# =============================================================================
# Exit codes: 0=OK  1=ERROR  3=ERROR(root)

if [[ $EUID -ne 0 ]]; then
    printf '{"rule":"system_settings_ssh_disable","status":"ERROR","message":"Must be run as root"}\n'
    exit 3
fi

/usr/sbin/systemsetup -setremotelogin on >/dev/null 2>&1
/bin/launchctl enable system/com.openssh.sshd

printf '{"rule":"system_settings_ssh_disable","action":"UNDONE","message":"Undo applied"}\n'
exit 0
