#!/bin/zsh --no-rcs
# =============================================================================
# Rule:      pwpolicy_alpha_numeric_enforce
# Source:    cisv8
# Category:  Password Policy
# Standards: cis_lvl2, cisv8
# Description: Require Passwords Contain a Minimum of One Numeric Character
# =============================================================================
# Auto-generated - do not edit manually.
# Exit codes: 0=PASS/OK  1=FAIL/ERROR  2=NOT_APPLICABLE  3=ERROR(root)

if [[ $EUID -ne 0 ]]; then
    printf '{"rule":"pwpolicy_alpha_numeric_enforce","status":"ERROR","message":"Must be run as root"}\n'
    exit 3
fi

arch=$(/usr/bin/arch)
CURRENT_USER=$(/usr/bin/defaults read /Library/Preferences/com.apple.loginwindow lastUserName)
CURR_USER_UID=$(/usr/bin/id -u $CURRENT_USER)

result_value=$(/usr/bin/pwpolicy -getaccountpolicies 2> /dev/null | /usr/bin/tail +2 | /usr/bin/xmllint --xpath '//dict/key[text()="policyIdentifier"]/following-sibling::*[1]/text()' - | /usr/bin/grep "requireAlphanumeric" -c
)
expected_value="1"

if [[ "$result_value" == "$expected_value" ]]; then
    printf '{"rule":"pwpolicy_alpha_numeric_enforce","status":"PASS","result":"%s","expected":"%s"}\n' "$result_value" "$expected_value"
    exit 0
else
    printf '{"rule":"pwpolicy_alpha_numeric_enforce","status":"FAIL","result":"%s","expected":"%s"}\n' "$result_value" "$expected_value"
    exit 1
fi
