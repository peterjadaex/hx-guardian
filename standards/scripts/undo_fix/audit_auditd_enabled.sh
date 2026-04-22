#!/bin/zsh --no-rcs
# =============================================================================
# Rule:      audit_auditd_enabled (UNDO)
# Category:  Auditing
# Description: Disable the auditd LaunchDaemon. Note: this turns off security
#              auditing and is a compliance regression; gated behind 2FA in UI.
# =============================================================================
# Exit codes: 0=OK  1=ERROR  3=ERROR(root)

if [[ $EUID -ne 0 ]]; then
    printf '{"rule":"audit_auditd_enabled","status":"ERROR","message":"Must be run as root"}\n'
    exit 3
fi

arch=$(/usr/bin/arch)
CURRENT_USER=$(/usr/bin/defaults read /Library/Preferences/com.apple.loginwindow lastUserName)
CURR_USER_UID=$(/usr/bin/id -u $CURRENT_USER)

/bin/launchctl bootout system /System/Library/LaunchDaemons/com.apple.auditd.plist 2>/dev/null
/bin/launchctl disable system/com.apple.auditd

printf '{"rule":"audit_auditd_enabled","action":"UNDONE","message":"Undo applied"}\n'
exit 0
