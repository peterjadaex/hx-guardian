#!/bin/zsh --no-rcs
# =============================================================================
# Rule:      system_settings_loginwindow_loginwindowtext_enable
# Source:    cisv8
# Category:  System Settings
# Standards: cis_lvl2, cisv8
# Description: Configure Login Window to Show A Custom Message
# =============================================================================
# Auto-generated - do not edit manually.
# Exit codes: 0=PASS/OK  1=FAIL/ERROR  2=NOT_APPLICABLE  3=ERROR(root)

if [[ $EUID -ne 0 ]]; then
    printf '{"rule":"system_settings_loginwindow_loginwindowtext_enable","status":"ERROR","message":"Must be run as root"}\n'
    exit 3
fi

arch=$(/usr/bin/arch)
CURRENT_USER=$(/usr/bin/defaults read /Library/Preferences/com.apple.loginwindow lastUserName)
CURR_USER_UID=$(/usr/bin/id -u $CURRENT_USER)

result_value=$(/usr/bin/osascript -l JavaScript << EOS | /usr/bin/base64
$.NSUserDefaults.alloc.initWithSuiteName('com.apple.loginwindow')\
.objectForKey('LoginwindowText').js
EOS
)
expected_value="Q2VudGVyIGZvciBJbnRlcm5ldCBTZWN1cml0eSBUZXN0IE1lc3NhZ2UK"

if [[ "$result_value" == "$expected_value" ]]; then
    printf '{"rule":"system_settings_loginwindow_loginwindowtext_enable","status":"PASS","result":"%s","expected":"%s"}\n' "$result_value" "$expected_value"
    exit 0
else
    printf '{"rule":"system_settings_loginwindow_loginwindowtext_enable","status":"FAIL","result":"%s","expected":"%s"}\n' "$result_value" "$expected_value"
    exit 1
fi
