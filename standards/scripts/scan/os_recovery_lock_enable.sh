#!/bin/zsh --no-rcs
# =============================================================================
# Rule:      os_recovery_lock_enable
# Source:    800-53r5_high
# Category:  Operating System
# Standards: 800-53r5_high
# Description: Enable Recovery Lock
# =============================================================================
# Auto-generated - do not edit manually.
# Exit codes: 0=PASS/OK  1=FAIL/ERROR  2=NOT_APPLICABLE  3=ERROR(root)

if [[ $EUID -ne 0 ]]; then
    printf '{"rule":"os_recovery_lock_enable","status":"ERROR","message":"Must be run as root"}\n'
    exit 3
fi

arch=$(/usr/bin/arch)
CURRENT_USER=$(/usr/bin/defaults read /Library/Preferences/com.apple.loginwindow lastUserName)
CURR_USER_UID=$(/usr/bin/id -u $CURRENT_USER)

rule_arch="arm64"
if [[ "$arch" != "$rule_arch" ]]; then
    printf '{"rule":"os_recovery_lock_enable","status":"NOT_APPLICABLE","message":"Requires arm64 architecture"}\n'
    exit 2
fi

result_value=$(/usr/libexec/mdmclient QuerySecurityInfo 2>/dev/null | /usr/bin/grep -c "IsRecoveryLockEnabled = 1"
)
expected_value="1"

if [[ "$result_value" == "$expected_value" ]]; then
    printf '{"rule":"os_recovery_lock_enable","status":"PASS","result":"%s","expected":"%s"}\n' "$result_value" "$expected_value"
    exit 0
else
    printf '{"rule":"os_recovery_lock_enable","status":"FAIL","result":"%s","expected":"%s"}\n' "$result_value" "$expected_value"
    exit 1
fi
