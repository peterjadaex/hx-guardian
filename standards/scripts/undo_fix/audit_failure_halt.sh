#!/bin/zsh --no-rcs
# =============================================================================
# Rule:      audit_failure_halt (UNDO)
# Category:  Auditing
# Description: Revert audit policy from 'ahlt,argv' to macOS default 'cnt,argv'.
# =============================================================================
# Exit codes: 0=OK  1=ERROR  3=ERROR(root)

if [[ $EUID -ne 0 ]]; then
    printf '{"rule":"audit_failure_halt","status":"ERROR","message":"Must be run as root"}\n'
    exit 3
fi

arch=$(/usr/bin/arch)
CURRENT_USER=$(/usr/bin/defaults read /Library/Preferences/com.apple.loginwindow lastUserName)
CURR_USER_UID=$(/usr/bin/id -u $CURRENT_USER)

/usr/bin/sed -i.undo.bak 's/^policy: ahlt,argv$/policy: cnt,argv/' /etc/security/audit_control; /usr/sbin/audit -s

printf '{"rule":"audit_failure_halt","action":"UNDONE","message":"Undo applied"}\n'
exit 0
