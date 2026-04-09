#!/bin/zsh --no-rcs
# =============================================================================
# Rule:      audit_flags_fw_configure
# Source:    800-53r5_high
# Category:  Auditing
# Standards: cis_lvl2, cisv8, 800-53r5_high
# Description: Configure System to Audit All Failed Write Actions on the System
# =============================================================================
# Auto-generated - do not edit manually.
# Exit codes: 0=PASS/OK  1=FAIL/ERROR  2=NOT_APPLICABLE  3=ERROR(root)

if [[ $EUID -ne 0 ]]; then
    printf '{"rule":"audit_flags_fw_configure","status":"ERROR","message":"Must be run as root"}\n'
    exit 3
fi

arch=$(/usr/bin/arch)
CURRENT_USER=$(/usr/bin/defaults read /Library/Preferences/com.apple.loginwindow lastUserName)
CURR_USER_UID=$(/usr/bin/id -u $CURRENT_USER)

result_value=$(/usr/bin/awk -F':' '/^flags/ { print $NF }' /etc/security/audit_control | /usr/bin/tr ',' '\n' | /usr/bin/grep -Ec '\-fw'
)
expected_value="1"

if [[ "$result_value" == "$expected_value" ]]; then
    printf '{"rule":"audit_flags_fw_configure","status":"PASS","result":"%s","expected":"%s"}\n' "$result_value" "$expected_value"
    exit 0
else
    printf '{"rule":"audit_flags_fw_configure","status":"FAIL","result":"%s","expected":"%s"}\n' "$result_value" "$expected_value"
    exit 1
fi
