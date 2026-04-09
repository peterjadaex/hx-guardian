#!/bin/zsh --no-rcs
# =============================================================================
# Rule:      auth_smartcard_certificate_trust_enforce_high
# Source:    800-53r5_high
# Category:  Authentication
# Standards: 800-53r5_high
# Description: Set Smartcard Certificate Trust to High
# =============================================================================
# Auto-generated - do not edit manually.
# Exit codes: 0=PASS/OK  1=FAIL/ERROR  2=NOT_APPLICABLE  3=ERROR(root)

if [[ $EUID -ne 0 ]]; then
    printf '{"rule":"auth_smartcard_certificate_trust_enforce_high","status":"ERROR","message":"Must be run as root"}\n'
    exit 3
fi

arch=$(/usr/bin/arch)
CURRENT_USER=$(/usr/bin/defaults read /Library/Preferences/com.apple.loginwindow lastUserName)
CURR_USER_UID=$(/usr/bin/id -u $CURRENT_USER)

result_value=$(/usr/bin/osascript -l JavaScript << EOS
$.NSUserDefaults.alloc.initWithSuiteName('com.apple.security.smartcard')\
.objectForKey('checkCertificateTrust').js
EOS
)
expected_value="3"

if [[ "$result_value" == "$expected_value" ]]; then
    printf '{"rule":"auth_smartcard_certificate_trust_enforce_high","status":"PASS","result":"%s","expected":"%s"}\n' "$result_value" "$expected_value"
    exit 0
else
    printf '{"rule":"auth_smartcard_certificate_trust_enforce_high","status":"FAIL","result":"%s","expected":"%s"}\n' "$result_value" "$expected_value"
    exit 1
fi
