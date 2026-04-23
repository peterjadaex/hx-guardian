#!/bin/zsh --no-rcs
# =============================================================================
# Rule:      system_settings_ssh_disable
# Source:    800-53r5_high
# Category:  System Settings
# Standards: cis_lvl2, cisv8, 800-53r5_high
# Description: Disable SSH Server for Remote Access Sessions
# =============================================================================
# Auto-generated - do not edit manually.
# Exit codes: 0=PASS/OK  1=FAIL/ERROR  2=NOT_APPLICABLE  3=ERROR(root)

if [[ $EUID -ne 0 ]]; then
    printf '{"rule":"system_settings_ssh_disable","status":"ERROR","message":"Must be run as root"}\n'
    exit 3
fi

# Is sshd explicitly enabled in the disabled list?
# launchctl print-disabled outputs "=> true" (enabled) or "=> false" (disabled).
sshd_disabled_line=$(/bin/launchctl print-disabled system 2>/dev/null | /usr/bin/grep '"com.openssh.sshd"')
sshd_enabled=0
if [[ "$sshd_disabled_line" == *"=> true"* || "$sshd_disabled_line" == *"=> enabled"* ]]; then
    sshd_enabled=1
fi

# Is sshd actually running? Check launchctl list: PID column is "-" when not running.
# Avoid `launchctl print system/com.openssh.sshd` — on Tahoe it outputs info even
# for disabled services, making a stopped daemon look running.
sshd_pid=$(/bin/launchctl list 2>/dev/null | /usr/bin/awk '/com\.openssh\.sshd/{print $1}')
sshd_running=0
if [[ -n "$sshd_pid" && "$sshd_pid" != "-" ]]; then
    sshd_running=1
fi

if [[ $sshd_running -eq 0 && $sshd_enabled -eq 0 ]]; then
    result_value="PASS"
else
    result_value="FAIL"
fi
expected_value="PASS"

if [[ "$result_value" == "$expected_value" ]]; then
    printf '{"rule":"system_settings_ssh_disable","status":"PASS","result":"%s","expected":"%s"}\n' "$result_value" "$expected_value"
    exit 0
else
    printf '{"rule":"system_settings_ssh_disable","status":"FAIL","result":"%s","expected":"%s"}\n' "$result_value" "$expected_value"
    exit 1
fi
