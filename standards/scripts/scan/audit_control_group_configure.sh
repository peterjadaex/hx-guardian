#!/bin/zsh --no-rcs
# =============================================================================
# Rule:      audit_control_group_configure
# Source:    cisv8
# Category:  Auditing
# Standards: cis_lvl2, cisv8
# Description: Configure Audit_Control Group to Wheel
# =============================================================================
# Auto-generated - do not edit manually.
# Exit codes: 0=PASS/OK  1=FAIL/ERROR  2=NOT_APPLICABLE  3=ERROR(root)

if [[ $EUID -ne 0 ]]; then
    printf '{"rule":"audit_control_group_configure","status":"ERROR","message":"Must be run as root"}\n'
    exit 3
fi

arch=$(/usr/bin/arch)
CURRENT_USER=$(/usr/bin/defaults read /Library/Preferences/com.apple.loginwindow lastUserName)
CURR_USER_UID=$(/usr/bin/id -u $CURRENT_USER)

result_value=$(/bin/ls -dn /etc/security/audit_control | /usr/bin/awk '{print $4}'
)
expected_value="0"

if [[ "$result_value" == "$expected_value" ]]; then
    printf '{"rule":"audit_control_group_configure","status":"PASS","result":"%s","expected":"%s"}\n' "$result_value" "$expected_value"
    exit 0
else
    printf '{"rule":"audit_control_group_configure","status":"FAIL","result":"%s","expected":"%s"}\n' "$result_value" "$expected_value"
    exit 1
fi
