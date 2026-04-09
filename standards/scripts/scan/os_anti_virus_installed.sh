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

result_value=$(/usr/bin/xprotect status | /usr/bin/grep -cE "(launch scans: enabled|background scans: enabled)"
)
expected_value="2"

if [[ "$result_value" == "$expected_value" ]]; then
    printf '{"rule":"os_anti_virus_installed","status":"PASS","result":"%s","expected":"%s"}\n' "$result_value" "$expected_value"
    exit 0
else
    printf '{"rule":"os_anti_virus_installed","status":"FAIL","result":"%s","expected":"%s"}\n' "$result_value" "$expected_value"
    exit 1
fi
