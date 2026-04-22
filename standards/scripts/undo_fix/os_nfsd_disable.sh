#!/bin/zsh --no-rcs
# =============================================================================
# Rule:      os_nfsd_disable (UNDO)
# Category:  Operating System
# Description: Re-enable the nfsd LaunchDaemon. Note: /etc/exports was removed
#              by the fix and is not restored here; recreate manually if needed.
# =============================================================================
# Exit codes: 0=OK  1=ERROR  3=ERROR(root)

if [[ $EUID -ne 0 ]]; then
    printf '{"rule":"os_nfsd_disable","status":"ERROR","message":"Must be run as root"}\n'
    exit 3
fi

arch=$(/usr/bin/arch)
CURRENT_USER=$(/usr/bin/defaults read /Library/Preferences/com.apple.loginwindow lastUserName)
CURR_USER_UID=$(/usr/bin/id -u $CURRENT_USER)

/bin/launchctl enable system/com.apple.nfsd

printf '{"rule":"os_nfsd_disable","action":"UNDONE","message":"Undo applied (note: /etc/exports not restored)"}\n'
exit 0
