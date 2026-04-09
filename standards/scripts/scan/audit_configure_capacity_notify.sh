#!/bin/zsh --no-rcs
# =============================================================================
# Rule:      audit_configure_capacity_notify
# Source:    800-53r5_high
# Category:  Auditing
# Standards: 800-53r5_high
# Description: Configure Audit Capacity Warning
# =============================================================================
# Auto-generated - do not edit manually.
# Exit codes: 0=PASS/OK  1=FAIL/ERROR  2=NOT_APPLICABLE  3=ERROR(root)

if [[ $EUID -ne 0 ]]; then
    printf '{"rule":"audit_configure_capacity_notify","status":"ERROR","message":"Must be run as root"}\n'
    exit 3
fi

arch=$(/usr/bin/arch)
CURRENT_USER=$(/usr/bin/defaults read /Library/Preferences/com.apple.loginwindow lastUserName)
CURR_USER_UID=$(/usr/bin/id -u $CURRENT_USER)

result_value=$(/usr/bin/awk -F: '/^minfree/{print $2}' /etc/security/audit_control
)
expected_value="25"

if [[ "$result_value" == "$expected_value" ]]; then
    printf '{"rule":"audit_configure_capacity_notify","status":"PASS","result":"%s","expected":"%s"}\n' "$result_value" "$expected_value"
    exit 0
else
    printf '{"rule":"audit_configure_capacity_notify","status":"FAIL","result":"%s","expected":"%s"}\n' "$result_value" "$expected_value"
    exit 1
fi
