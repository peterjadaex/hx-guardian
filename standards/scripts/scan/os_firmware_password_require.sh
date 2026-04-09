#!/bin/zsh --no-rcs
# =============================================================================
# Rule:      os_firmware_password_require
# Source:    800-53r5_high
# Category:  Operating System
# Standards: 800-53r5_high
# Description: Enable Firmware Password
# =============================================================================
# Auto-generated - do not edit manually.
# Exit codes: 0=PASS/OK  1=FAIL/ERROR  2=NOT_APPLICABLE  3=ERROR(root)

if [[ $EUID -ne 0 ]]; then
    printf '{"rule":"os_firmware_password_require","status":"ERROR","message":"Must be run as root"}\n'
    exit 3
fi

arch=$(/usr/bin/arch)
CURRENT_USER=$(/usr/bin/defaults read /Library/Preferences/com.apple.loginwindow lastUserName)
CURR_USER_UID=$(/usr/bin/id -u $CURRENT_USER)

rule_arch="i386"
if [[ "$arch" != "$rule_arch" ]]; then
    printf '{"rule":"os_firmware_password_require","status":"NOT_APPLICABLE","message":"Requires i386 architecture"}\n'
    exit 2
fi

result_value=$(/usr/sbin/firmwarepasswd -check | /usr/bin/grep -c "Password Enabled: Yes"
)
expected_value="1"

if [[ "$result_value" == "$expected_value" ]]; then
    printf '{"rule":"os_firmware_password_require","status":"PASS","result":"%s","expected":"%s"}\n' "$result_value" "$expected_value"
    exit 0
else
    printf '{"rule":"os_firmware_password_require","status":"FAIL","result":"%s","expected":"%s"}\n' "$result_value" "$expected_value"
    exit 1
fi
