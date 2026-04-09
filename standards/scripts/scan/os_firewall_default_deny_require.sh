#!/bin/zsh --no-rcs
# =============================================================================
# Rule:      os_firewall_default_deny_require
# Source:    800-53r5_high
# Category:  Operating System
# Standards: 800-53r5_high
# Description: Control Connections to Other Systems via a Deny-All and Allow-by-Exception Firewall Policy
# =============================================================================
# Auto-generated - do not edit manually.
# Exit codes: 0=PASS/OK  1=FAIL/ERROR  2=NOT_APPLICABLE  3=ERROR(root)

if [[ $EUID -ne 0 ]]; then
    printf '{"rule":"os_firewall_default_deny_require","status":"ERROR","message":"Must be run as root"}\n'
    exit 3
fi

arch=$(/usr/bin/arch)
CURRENT_USER=$(/usr/bin/defaults read /Library/Preferences/com.apple.loginwindow lastUserName)
CURR_USER_UID=$(/usr/bin/id -u $CURRENT_USER)

result_value=$(/sbin/pfctl -a '*' -sr &> /dev/null | /usr/bin/grep -c "block drop in all"
)
expected_value="1"

if [[ "$result_value" == "$expected_value" ]]; then
    printf '{"rule":"os_firewall_default_deny_require","status":"PASS","result":"%s","expected":"%s"}\n' "$result_value" "$expected_value"
    exit 0
else
    printf '{"rule":"os_firewall_default_deny_require","status":"FAIL","result":"%s","expected":"%s"}\n' "$result_value" "$expected_value"
    exit 1
fi
