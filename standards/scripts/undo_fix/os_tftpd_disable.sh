#!/bin/zsh --no-rcs
# =============================================================================
# Rule:      os_tftpd_disable (UNDO)
# Category:  Operating System
# Description: Re-enable the tftpd LaunchDaemon.
# =============================================================================
# Exit codes: 0=OK  1=ERROR  3=ERROR(root)

if [[ $EUID -ne 0 ]]; then
    printf '{"rule":"os_tftpd_disable","status":"ERROR","message":"Must be run as root"}\n'
    exit 3
fi

arch=$(/usr/bin/arch)
CURRENT_USER=$(/usr/bin/defaults read /Library/Preferences/com.apple.loginwindow lastUserName)
CURR_USER_UID=$(/usr/bin/id -u $CURRENT_USER)

/bin/launchctl enable system/com.apple.tftpd
/bin/launchctl bootstrap system /System/Library/LaunchDaemons/tftp.plist 2>/dev/null

printf '{"rule":"os_tftpd_disable","action":"UNDONE","message":"Undo applied"}\n'
exit 0
