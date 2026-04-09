#!/bin/zsh --no-rcs
# =============================================================================
# Rule:      os_world_writable_library_folder_configure
# Source:    cisv8
# Category:  Operating System
# Standards: cis_lvl2, cisv8
# Description: Ensure No World Writable Files Exist in the Library Folder
# =============================================================================
# Auto-generated - do not edit manually.
# Exit codes: 0=PASS/OK  1=FAIL/ERROR  2=NOT_APPLICABLE  3=ERROR(root)

if [[ $EUID -ne 0 ]]; then
    printf '{"rule":"os_world_writable_library_folder_configure","status":"ERROR","message":"Must be run as root"}\n'
    exit 3
fi

arch=$(/usr/bin/arch)
CURRENT_USER=$(/usr/bin/defaults read /Library/Preferences/com.apple.loginwindow lastUserName)
CURR_USER_UID=$(/usr/bin/id -u $CURRENT_USER)

IFS=$'\n'
for libPermissions in $(/usr/bin/find /Library -type d -perm -002 ! -perm -1000 ! -xattrname com.apple.rootless 2>/dev/null); do
  /bin/chmod -R o-w "$libPermissions"
done

printf '{"rule":"os_world_writable_library_folder_configure","action":"EXECUTED","message":"Fix applied"}\n'
exit 0
