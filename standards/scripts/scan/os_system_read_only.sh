#!/bin/zsh --no-rcs
# =============================================================================
# Rule:      os_system_read_only
# Source:    800-53r5_high
# Category:  Operating System
# Standards: 800-53r5_high
# Description: Ensure System Volume is Read Only
# =============================================================================
# Auto-generated - do not edit manually.
# Exit codes: 0=PASS/OK  1=FAIL/ERROR  2=NOT_APPLICABLE  3=ERROR(root)

if [[ $EUID -ne 0 ]]; then
    printf '{"rule":"os_system_read_only","status":"ERROR","message":"Must be run as root"}\n'
    exit 3
fi

arch=$(/usr/bin/arch)
CURRENT_USER=$(/usr/bin/defaults read /Library/Preferences/com.apple.loginwindow lastUserName)
CURR_USER_UID=$(/usr/bin/id -u $CURRENT_USER)

result_value=$(/usr/sbin/system_profiler SPStorageDataType | /usr/bin/awk '/Mount Point: \/$/{x=NR+2}(NR==x){print $2}'
)
expected_value="No"

if [[ "$result_value" == "$expected_value" ]]; then
    printf '{"rule":"os_system_read_only","status":"PASS","result":"%s","expected":"%s"}\n' "$result_value" "$expected_value"
    exit 0
else
    printf '{"rule":"os_system_read_only","status":"FAIL","result":"%s","expected":"%s"}\n' "$result_value" "$expected_value"
    exit 1
fi
