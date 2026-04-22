#!/bin/zsh --no-rcs
# =============================================================================
# Rule:      auth_pam_sudo_smartcard_enforce (UNDO)
# Category:  Authentication
# Description: Restore /etc/pam.d/sudo to the macOS default template.
# =============================================================================
# Exit codes: 0=OK  1=ERROR  3=ERROR(root)

if [[ $EUID -ne 0 ]]; then
    printf '{"rule":"auth_pam_sudo_smartcard_enforce","status":"ERROR","message":"Must be run as root"}\n'
    exit 3
fi

/bin/cat > /etc/pam.d/sudo << 'SUDO_END'
# sudo: auth account password session
auth        include        sudo_local
auth        sufficient     pam_smartcard.so
auth        required       pam_opendirectory.so
account     required       pam_permit.so
password    required       pam_deny.so
session     required       pam_permit.so
SUDO_END

/bin/chmod 444 /etc/pam.d/sudo
/usr/sbin/chown root:wheel /etc/pam.d/sudo

printf '{"rule":"auth_pam_sudo_smartcard_enforce","action":"UNDONE","message":"Undo applied"}\n'
exit 0
