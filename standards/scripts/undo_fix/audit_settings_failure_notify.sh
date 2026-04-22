#!/bin/zsh --no-rcs
# =============================================================================
# Rule:      audit_settings_failure_notify (UNDO)
# Category:  Auditing
# Description: Reverse 'logger -s -p' back to 'logger -p' in /etc/security/audit_warn.
# =============================================================================
# Exit codes: 0=OK  1=ERROR  3=ERROR(root)

if [[ $EUID -ne 0 ]]; then
    printf '{"rule":"audit_settings_failure_notify","status":"ERROR","message":"Must be run as root"}\n'
    exit 3
fi

arch=$(/usr/bin/arch)
CURRENT_USER=$(/usr/bin/defaults read /Library/Preferences/com.apple.loginwindow lastUserName)
CURR_USER_UID=$(/usr/bin/id -u $CURRENT_USER)

/usr/bin/sed -i.undo.bak 's/logger -s -p/logger -p/' /etc/security/audit_warn; /usr/sbin/audit -s

printf '{"rule":"audit_settings_failure_notify","action":"UNDONE","message":"Undo applied"}\n'
exit 0
