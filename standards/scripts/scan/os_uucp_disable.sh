#!/bin/zsh --no-rcs
# =============================================================================
# Rule:      os_uucp_disable
# Source:    800-53r5_high
# Category:  Operating System
# Standards: cisv8, 800-53r5_high
# Description: Disable Unix-to-Unix Copy Protocol Service
# =============================================================================
# Auto-generated - do not edit manually.
# Exit codes: 0=PASS/OK  1=FAIL/ERROR  2=NOT_APPLICABLE  3=ERROR(root)

if [[ $EUID -ne 0 ]]; then
    printf '{"rule":"os_uucp_disable","status":"ERROR","message":"Must be run as root"}\n'
    exit 3
fi

arch=$(/usr/bin/arch)
CURRENT_USER=$(/usr/bin/defaults read /Library/Preferences/com.apple.loginwindow lastUserName)
CURR_USER_UID=$(/usr/bin/id -u $CURRENT_USER)

result_value=$(result="FAIL"
enabled=$(/bin/launchctl print-disabled system | /usr/bin/grep '"com.apple.uucp" => enabled')
running=$(/bin/launchctl print system/com.apple.uucp 2>/dev/null)

if [[ -z "$running" ]] && [[ -z "$enabled" ]]; then
  result="PASS"
elif [[ -n "$running" ]]; then
  result=result+" RUNNING"
elif [[ -n "$enabled" ]]; then
  result=result+" ENABLED"
fi
echo $result
)
expected_value="PASS"

if [[ "$result_value" == "$expected_value" ]]; then
    printf '{"rule":"os_uucp_disable","status":"PASS","result":"%s","expected":"%s"}\n' "$result_value" "$expected_value"
    exit 0
else
    printf '{"rule":"os_uucp_disable","status":"FAIL","result":"%s","expected":"%s"}\n' "$result_value" "$expected_value"
    exit 1
fi
