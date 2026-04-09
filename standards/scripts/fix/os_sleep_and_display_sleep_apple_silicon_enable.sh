#!/bin/zsh --no-rcs
# =============================================================================
# Rule:      os_sleep_and_display_sleep_apple_silicon_enable
# Source:    cisv8
# Category:  Operating System
# Standards: cis_lvl2, cisv8
# Description: Ensure Sleep and Display Sleep Is Enabled on Apple Silicon Devices
# =============================================================================
# Auto-generated - do not edit manually.
# Exit codes: 0=PASS/OK  1=FAIL/ERROR  2=NOT_APPLICABLE  3=ERROR(root)

if [[ $EUID -ne 0 ]]; then
    printf '{"rule":"os_sleep_and_display_sleep_apple_silicon_enable","status":"ERROR","message":"Must be run as root"}\n'
    exit 3
fi

arch=$(/usr/bin/arch)
CURRENT_USER=$(/usr/bin/defaults read /Library/Preferences/com.apple.loginwindow lastUserName)
CURR_USER_UID=$(/usr/bin/id -u $CURRENT_USER)

rule_arch="arm64"
if [[ "$arch" != "$rule_arch" ]]; then
    printf '{"rule":"os_sleep_and_display_sleep_apple_silicon_enable","action":"NOT_APPLICABLE","message":"Requires arm64 architecture"}\n'
    exit 2
fi

/usr/bin/pmset -a sleep 15
/usr/bin/pmset -a displaysleep 10

printf '{"rule":"os_sleep_and_display_sleep_apple_silicon_enable","action":"EXECUTED","message":"Fix applied"}\n'
exit 0
