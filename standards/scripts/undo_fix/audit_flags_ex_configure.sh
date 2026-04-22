#!/bin/zsh --no-rcs
# =============================================================================
# Rule:      audit_flags_ex_configure (UNDO)
# Category:  Auditing
# Description: Remove ',-ex' token from /etc/security/audit_control flags line.
# =============================================================================
# Exit codes: 0=OK  1=ERROR  3=ERROR(root)

if [[ $EUID -ne 0 ]]; then
    printf '{"rule":"audit_flags_ex_configure","status":"ERROR","message":"Must be run as root"}\n'
    exit 3
fi

arch=$(/usr/bin/arch)
CURRENT_USER=$(/usr/bin/defaults read /Library/Preferences/com.apple.loginwindow lastUserName)
CURR_USER_UID=$(/usr/bin/id -u $CURRENT_USER)

/usr/bin/sed -i.undo.bak -E '/^flags/ s/,-ex//g' /etc/security/audit_control; /usr/sbin/audit -s

printf '{"rule":"audit_flags_ex_configure","action":"UNDONE","message":"Undo applied"}\n'
exit 0
