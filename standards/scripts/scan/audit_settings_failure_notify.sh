#!/bin/zsh --no-rcs
# =============================================================================
# Rule:      audit_settings_failure_notify
# Source:    800-53r5_high
# Category:  Auditing
# Standards: 800-53r5_high
# Description: Configure Audit Failure Notification
# =============================================================================
# Auto-generated - do not edit manually.
# Exit codes: 0=PASS/OK  1=FAIL/ERROR  2=NOT_APPLICABLE  3=ERROR(root)

if [[ $EUID -ne 0 ]]; then
    printf '{"rule":"audit_settings_failure_notify","status":"ERROR","message":"Must be run as root"}\n'
    exit 3
fi

arch=$(/usr/bin/arch)
CURRENT_USER=$(/usr/bin/defaults read /Library/Preferences/com.apple.loginwindow lastUserName)
CURR_USER_UID=$(/usr/bin/id -u $CURRENT_USER)

result_value=$(/usr/bin/grep -c "logger -s -p" /etc/security/audit_warn
)
expected_value="1"

if [[ "$result_value" == "$expected_value" ]]; then
    printf '{"rule":"audit_settings_failure_notify","status":"PASS","result":"%s","expected":"%s"}\n' "$result_value" "$expected_value"
    exit 0
else
    printf '{"rule":"audit_settings_failure_notify","status":"FAIL","result":"%s","expected":"%s"}\n' "$result_value" "$expected_value"
    exit 1
fi
