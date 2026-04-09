#!/bin/zsh --no-rcs
# =============================================================================
# Rule:      audit_auditd_enabled
# Source:    800-53r5_high
# Category:  Auditing
# Standards: cis_lvl2, cisv8, 800-53r5_high
# Description: Enable Security Auditing
# =============================================================================
# Auto-generated - do not edit manually.
# Exit codes: 0=PASS/OK  1=FAIL/ERROR  2=NOT_APPLICABLE  3=ERROR(root)

if [[ $EUID -ne 0 ]]; then
    printf '{"rule":"audit_auditd_enabled","status":"ERROR","message":"Must be run as root"}\n'
    exit 3
fi

arch=$(/usr/bin/arch)
CURRENT_USER=$(/usr/bin/defaults read /Library/Preferences/com.apple.loginwindow lastUserName)
CURR_USER_UID=$(/usr/bin/id -u $CURRENT_USER)

result_value=$(LAUNCHD_RUNNING=$(/bin/launchctl print system | /usr/bin/grep -c -E '\tcom.apple.auditd')
AUDITD_RUNNING=$(/usr/sbin/audit -c | /usr/bin/grep -c "AUC_AUDITING")
if [[ $LAUNCHD_RUNNING == 1 ]] && [[ -e /etc/security/audit_control ]] && [[ $AUDITD_RUNNING == 1 ]]; then
  echo "pass"
else
  echo "fail"
fi
)
expected_value="pass"

if [[ "$result_value" == "$expected_value" ]]; then
    printf '{"rule":"audit_auditd_enabled","status":"PASS","result":"%s","expected":"%s"}\n' "$result_value" "$expected_value"
    exit 0
else
    printf '{"rule":"audit_auditd_enabled","status":"FAIL","result":"%s","expected":"%s"}\n' "$result_value" "$expected_value"
    exit 1
fi
