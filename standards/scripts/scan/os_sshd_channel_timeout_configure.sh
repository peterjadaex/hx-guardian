#!/bin/zsh --no-rcs
# =============================================================================
# Rule:      os_sshd_channel_timeout_configure
# Source:    800-53r5_high
# Category:  Operating System
# Standards: 800-53r5_high
# Description: Configure SSHD Channel Timeout to *ODV*
# =============================================================================
# Auto-generated - do not edit manually.
# Exit codes: 0=PASS/OK  1=FAIL/ERROR  2=NOT_APPLICABLE  3=ERROR(root)

if [[ $EUID -ne 0 ]]; then
    printf '{"rule":"os_sshd_channel_timeout_configure","status":"ERROR","message":"Must be run as root"}\n'
    exit 3
fi

arch=$(/usr/bin/arch)
CURRENT_USER=$(/usr/bin/defaults read /Library/Preferences/com.apple.loginwindow lastUserName)
CURR_USER_UID=$(/usr/bin/id -u $CURRENT_USER)

result_value=$(/usr/sbin/sshd -G | /usr/bin/awk '/channeltimeout/{print $2}'
)
expected_value="session:*=900"

if [[ "$result_value" == "$expected_value" ]]; then
    printf '{"rule":"os_sshd_channel_timeout_configure","status":"PASS","result":"%s","expected":"%s"}\n' "$result_value" "$expected_value"
    exit 0
else
    printf '{"rule":"os_sshd_channel_timeout_configure","status":"FAIL","result":"%s","expected":"%s"}\n' "$result_value" "$expected_value"
    exit 1
fi
