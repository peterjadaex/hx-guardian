#!/bin/zsh --no-rcs
# =============================================================================
# Rule:      os_httpd_disable
# Source:    800-53r5_high
# Category:  Operating System
# Standards: cis_lvl2, cisv8, 800-53r5_high
# Description: Disable the Built-in Web Server
# =============================================================================
# Hand-maintained — do not overwrite with generate_scripts.py output.
# Exit codes: 0=PASS/OK  1=FAIL/ERROR  2=NOT_APPLICABLE  3=ERROR(root)

if [[ $EUID -ne 0 ]]; then
    printf '{"rule":"os_httpd_disable","status":"ERROR","message":"Must be run as root"}\n'
    exit 3
fi

# Is Apache enabled? launchctl print-disabled lists the per-service override as
# service => is-disabled:
#   "=> true"  / "=> disabled" → the service IS disabled
#   "=> false" / "=> enabled"  → the service is enabled
# No entry means launchd default, and org.apache.httpd ships disabled.
httpd_disabled_line=$(/bin/launchctl print-disabled system 2>/dev/null | /usr/bin/grep '"org.apache.httpd"')
httpd_enabled=0
if [[ "$httpd_disabled_line" == *"=> false"* || "$httpd_disabled_line" == *"=> enabled"* ]]; then
    httpd_enabled=1
fi

# Is Apache actually running? launchctl list columns are: PID Status Label.
# Exact-match the label and stop at the first hit. Avoid
# `launchctl print system/org.apache.httpd` — on Tahoe it outputs info even for
# disabled services, which made this check FAIL permanently.
httpd_pid=$(/bin/launchctl list 2>/dev/null | /usr/bin/awk '$3 == "org.apache.httpd" { print $1; exit }')
httpd_running=0
if [[ -n "$httpd_pid" && "$httpd_pid" != "-" ]]; then
    httpd_running=1
fi
# Also catch an httpd started outside launchd (e.g. apachectl on a dev box).
if /usr/bin/pgrep -qx httpd 2>/dev/null; then
    httpd_running=1
fi

if [[ $httpd_running -eq 0 && $httpd_enabled -eq 0 ]]; then
    result_value="PASS"
else
    result_value="FAIL"
fi
expected_value="PASS"

if [[ "$result_value" == "$expected_value" ]]; then
    printf '{"rule":"os_httpd_disable","status":"PASS","result":"%s","expected":"%s"}\n' "$result_value" "$expected_value"
    exit 0
else
    printf '{"rule":"os_httpd_disable","status":"FAIL","result":"%s","expected":"%s"}\n' "$result_value" "$expected_value"
    exit 1
fi
