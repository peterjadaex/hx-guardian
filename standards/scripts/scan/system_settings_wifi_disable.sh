#!/bin/zsh --no-rcs
# =============================================================================
# Rule:      system_settings_wifi_disable
# Source:    800-53r5_high
# Category:  System Settings
# Standards: cisv8, 800-53r5_high
# Description: Disable Wi-Fi Interface
# =============================================================================
# Exit codes: 0=PASS  1=FAIL  2=NOT_APPLICABLE  3=ERROR(root)

if [[ $EUID -ne 0 ]]; then
    printf '{"rule":"system_settings_wifi_disable","status":"ERROR","message":"Must be run as root"}\n'
    exit 3
fi

if ! /usr/sbin/networksetup -listallnetworkservices 2>/dev/null | /usr/bin/grep -qx "Wi-Fi"; then
    # No Wi-Fi service listed. This is the desired end-state — either the MDM
    # profile has removed the service or the hardware has none. The rule's
    # goal (Wi-Fi disabled) is satisfied either way.
    printf '{"rule":"system_settings_wifi_disable","status":"PASS","result":"Wi-Fi service absent","expected":"Disabled or absent"}\n'
    exit 0
fi

state=$(/usr/sbin/networksetup -getnetworkserviceenabled "Wi-Fi" 2>/dev/null)
expected="Disabled"

if [[ "$state" == "$expected" ]]; then
    printf '{"rule":"system_settings_wifi_disable","status":"PASS","result":"%s","expected":"%s"}\n' "$state" "$expected"
    exit 0
else
    printf '{"rule":"system_settings_wifi_disable","status":"FAIL","result":"%s","expected":"%s"}\n' "$state" "$expected"
    exit 1
fi
