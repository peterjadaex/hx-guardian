#!/bin/zsh --no-rcs
# =============================================================================
# Rule:      auth_ssh_password_authentication_disable
# Source:    800-53r5_high
# Category:  Authentication
# Standards: cisv8, 800-53r5_high
# Description: Disable Password Authentication for SSH
# =============================================================================
# Auto-generated - do not edit manually.
# Exit codes: 0=PASS/OK  1=FAIL/ERROR  2=NOT_APPLICABLE  3=ERROR(root)

if [[ $EUID -ne 0 ]]; then
    printf '{"rule":"auth_ssh_password_authentication_disable","status":"ERROR","message":"Must be run as root"}\n'
    exit 3
fi

arch=$(/usr/bin/arch)
CURRENT_USER=$(/usr/bin/defaults read /Library/Preferences/com.apple.loginwindow lastUserName)
CURR_USER_UID=$(/usr/bin/id -u $CURRENT_USER)

result_value=$(/usr/sbin/sshd -G | /usr/bin/grep -Ec '^(passwordauthentication\s+no|kbdinteractiveauthentication\s+no)'
)
expected_value="2"

if [[ "$result_value" == "$expected_value" ]]; then
    printf '{"rule":"auth_ssh_password_authentication_disable","status":"PASS","result":"%s","expected":"%s"}\n' "$result_value" "$expected_value"
    exit 0
else
    printf '{"rule":"auth_ssh_password_authentication_disable","status":"FAIL","result":"%s","expected":"%s"}\n' "$result_value" "$expected_value"
    exit 1
fi
