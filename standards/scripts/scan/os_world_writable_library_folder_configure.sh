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

result_value=$(/usr/bin/find /Library -type d -perm -002 ! -perm -1000 ! -xattrname com.apple.rootless 2>/dev/null | /usr/bin/wc -l | /usr/bin/xargs
)
expected_value="0"

if [[ "$result_value" == "$expected_value" ]]; then
    printf '{"rule":"os_world_writable_library_folder_configure","status":"PASS","result":"%s","expected":"%s"}\n' "$result_value" "$expected_value"
    exit 0
else
    printf '{"rule":"os_world_writable_library_folder_configure","status":"FAIL","result":"%s","expected":"%s"}\n' "$result_value" "$expected_value"
    exit 1
fi
