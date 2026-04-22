#!/bin/zsh --no-rcs
# =============================================================================
# Rule:      auth_pam_login_smartcard_enforce (UNDO)
# Category:  Authentication
# Description: Restore /etc/pam.d/login to the macOS default template
#              (no pam_smartcard.so sufficient line).
# =============================================================================
# Exit codes: 0=OK  1=ERROR  3=ERROR(root)

if [[ $EUID -ne 0 ]]; then
    printf '{"rule":"auth_pam_login_smartcard_enforce","status":"ERROR","message":"Must be run as root"}\n'
    exit 3
fi

/bin/cat > /etc/pam.d/login << 'LOGIN_END'
# login: auth account password session
auth        optional       pam_krb5.so use_kcminit
auth        optional       pam_ntlm.so try_first_pass
auth        optional       pam_mount.so try_first_pass
auth        required       pam_opendirectory.so try_first_pass
account     required       pam_nologin.so
account     required       pam_opendirectory.so
password    required       pam_opendirectory.so
session     required       pam_launchd.so
session     required       pam_uwtmp.so
session     optional       pam_mount.so
LOGIN_END

/bin/chmod 644 /etc/pam.d/login
/usr/sbin/chown root:wheel /etc/pam.d/login

printf '{"rule":"auth_pam_login_smartcard_enforce","action":"UNDONE","message":"Undo applied"}\n'
exit 0
