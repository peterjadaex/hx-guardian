#!/bin/zsh --no-rcs
# =============================================================================
# Rule:      auth_pam_su_smartcard_enforce (UNDO)
# Category:  Authentication
# Description: Restore /etc/pam.d/su to the macOS default template.
# =============================================================================
# Exit codes: 0=OK  1=ERROR  3=ERROR(root)

if [[ $EUID -ne 0 ]]; then
    printf '{"rule":"auth_pam_su_smartcard_enforce","status":"ERROR","message":"Must be run as root"}\n'
    exit 3
fi

/bin/cat > /etc/pam.d/su << 'SU_END'
# su: auth account password session
auth        sufficient     pam_rootok.so
auth        required       pam_opendirectory.so
account     required       pam_permit.so
account     required       pam_opendirectory.so no_check_shell
password    required       pam_opendirectory.so
session     required       pam_launchd.so
SU_END

/bin/chmod 644 /etc/pam.d/su
/usr/sbin/chown root:wheel /etc/pam.d/su

printf '{"rule":"auth_pam_su_smartcard_enforce","action":"UNDONE","message":"Undo applied"}\n'
exit 0
