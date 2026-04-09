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
    printf '{"rule":"os_sleep_and_display_sleep_apple_silicon_enable","status":"NOT_APPLICABLE","message":"Requires arm64 architecture"}\n'
    exit 2
fi

result_value=$(error_count=0
if /usr/sbin/system_profiler SPHardwareDataType | /usr/bin/grep -q "MacBook"; then
  cpuType=$(/usr/sbin/sysctl -n machdep.cpu.brand_string)
  if echo "$cpuType" | grep -q "Apple"; then
    sleepMode=$(/usr/bin/pmset -b -g | /usr/bin/grep '^\s*sleep' 2>&1 | /usr/bin/awk '{print $2}')
    displaysleepMode=$(/usr/bin/pmset -b -g | /usr/bin/grep displaysleep 2>&1 | /usr/bin/awk '{print $2}')
    if [[ "$sleepMode" == "" ]] || [[ "$sleepMode" -gt 15 ]]; then
      ((error_count++))
    fi
    if [[ "$displaysleepMode" == "" ]] || [[ "$displaysleepMode" -gt 10 ]] || [[ "$displaysleepMode" -gt "$sleepMode" ]]; then
      ((error_count++))
    fi
  fi
fi
echo "$error_count"
)
expected_value="0"

if [[ "$result_value" == "$expected_value" ]]; then
    printf '{"rule":"os_sleep_and_display_sleep_apple_silicon_enable","status":"PASS","result":"%s","expected":"%s"}\n' "$result_value" "$expected_value"
    exit 0
else
    printf '{"rule":"os_sleep_and_display_sleep_apple_silicon_enable","status":"FAIL","result":"%s","expected":"%s"}\n' "$result_value" "$expected_value"
    exit 1
fi
