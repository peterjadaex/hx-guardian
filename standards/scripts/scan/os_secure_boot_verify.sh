#!/bin/zsh --no-rcs
# =============================================================================
# Rule:      os_secure_boot_verify
# Source:    800-53r5_high
# Category:  Operating System
# Standards: 800-53r5_high
# Description: Ensure Secure Boot Level Set to Full
# =============================================================================
# Auto-generated - do not edit manually.
# Exit codes: 0=PASS/OK  1=FAIL/ERROR  2=NOT_APPLICABLE  3=ERROR(root)

if [[ $EUID -ne 0 ]]; then
    printf '{"rule":"os_secure_boot_verify","status":"ERROR","message":"Must be run as root"}\n'
    exit 3
fi

arch=$(/usr/bin/arch)
CURRENT_USER=$(/usr/bin/defaults read /Library/Preferences/com.apple.loginwindow lastUserName)
CURR_USER_UID=$(/usr/bin/id -u $CURRENT_USER)

result_value=$(/usr/libexec/mdmclient QuerySecurityInfo 2>/dev/null | /usr/bin/grep -c "SecureBootLevel = full"
)
expected_value="1"

if [[ "$result_value" == "$expected_value" ]]; then
    printf '{"rule":"os_secure_boot_verify","status":"PASS","result":"%s","expected":"%s"}\n' "$result_value" "$expected_value"
    exit 0
else
    printf '{"rule":"os_secure_boot_verify","status":"FAIL","result":"%s","expected":"%s"}\n' "$result_value" "$expected_value"
    exit 1
fi
