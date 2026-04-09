#!/bin/zsh --no-rcs
# =============================================================================
# Rule:      os_world_writable_system_folder_configure
# Source:    cisv8
# Category:  Operating System
# Standards: cis_lvl2, cisv8
# Description: Ensure No World Writable Files Exist in the System Folder
# =============================================================================
# Auto-generated - do not edit manually.
# Exit codes: 0=PASS/OK  1=FAIL/ERROR  2=NOT_APPLICABLE  3=ERROR(root)

if [[ $EUID -ne 0 ]]; then
    printf '{"rule":"os_world_writable_system_folder_configure","status":"ERROR","message":"Must be run as root"}\n'
    exit 3
fi

arch=$(/usr/bin/arch)
CURRENT_USER=$(/usr/bin/defaults read /Library/Preferences/com.apple.loginwindow lastUserName)
CURR_USER_UID=$(/usr/bin/id -u $CURRENT_USER)

IFS=$'\n'
for sysPermissions in $( /usr/bin/find /System/Volumes/Data/System -type d -perm -2 | /usr/bin/grep -vE "downloadDir|locks" ); do
  /bin/chmod -R o-w "$sysPermissions"
done

printf '{"rule":"os_world_writable_system_folder_configure","action":"EXECUTED","message":"Fix applied"}\n'
exit 0
