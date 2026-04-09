#!/bin/zsh --no-rcs
# =============================================================================
# Rule:      os_anti_virus_installed
# Source:    cisv8
# Category:  Operating System
# Standards: cis_lvl2, cisv8
# Description: Must Use an Approved Antivirus Program
# =============================================================================
# Auto-generated - do not edit manually.
# Exit codes: 0=PASS/OK  1=FAIL/ERROR  2=NOT_APPLICABLE  3=ERROR(root)

if [[ $EUID -ne 0 ]]; then
    printf '{"rule":"os_anti_virus_installed","status":"ERROR","message":"Must be run as root"}\n'
    exit 3
fi

arch=$(/usr/bin/arch)
CURRENT_USER=$(/usr/bin/defaults read /Library/Preferences/com.apple.loginwindow lastUserName)
CURR_USER_UID=$(/usr/bin/id -u $CURRENT_USER)

/bin/launchctl load -w /Library/Apple/System/Library/LaunchDaemons/com.apple.XProtect.daemon.scan.plist
/bin/launchctl load -w /Library/Apple/System/Library/LaunchDaemons/com.apple.XprotectFramework.PluginService.plist

printf '{"rule":"os_anti_virus_installed","action":"EXECUTED","message":"Fix applied"}\n'
exit 0
