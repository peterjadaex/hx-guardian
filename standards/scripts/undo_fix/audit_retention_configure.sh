#!/bin/zsh --no-rcs
# =============================================================================
# Rule:      audit_retention_configure (UNDO)
# Category:  Auditing
# Description: Remove the enforced 7-day expire-after line (returns to audit
#              subsystem default).
# =============================================================================
# Exit codes: 0=OK  1=ERROR  3=ERROR(root)

if [[ $EUID -ne 0 ]]; then
    printf '{"rule":"audit_retention_configure","status":"ERROR","message":"Must be run as root"}\n'
    exit 3
fi

arch=$(/usr/bin/arch)
CURRENT_USER=$(/usr/bin/defaults read /Library/Preferences/com.apple.loginwindow lastUserName)
CURR_USER_UID=$(/usr/bin/id -u $CURRENT_USER)

/usr/bin/sed -i.undo.bak -E 's/^expire-after:7d$/expire-after:10M/' /etc/security/audit_control; /usr/sbin/audit -s

printf '{"rule":"audit_retention_configure","action":"UNDONE","message":"Undo applied"}\n'
exit 0
