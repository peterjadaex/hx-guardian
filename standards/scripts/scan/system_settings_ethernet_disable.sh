#!/bin/zsh --no-rcs
# =============================================================================
# Rule:      system_settings_ethernet_disable
# Source:    hxguardian
# Category:  System Settings
# Standards: hxguardian
# Description: Disable Ethernet Interface
# =============================================================================
# Exit codes: 0=PASS  1=FAIL  2=NOT_APPLICABLE  3=ERROR(root)

if [[ $EUID -ne 0 ]]; then
    printf '{"rule":"system_settings_ethernet_disable","status":"ERROR","message":"Must be run as root"}\n'
    exit 3
fi

if ! /usr/sbin/networksetup -listallnetworkservices 2>/dev/null | /usr/bin/grep -qx "Ethernet"; then
    printf '{"rule":"system_settings_ethernet_disable","status":"NOT_APPLICABLE","message":"No Ethernet service present"}\n'
    exit 2
fi

state=$(/usr/sbin/networksetup -getnetworkserviceenabled "Ethernet" 2>/dev/null)
expected="Disabled"

if [[ "$state" == "$expected" ]]; then
    printf '{"rule":"system_settings_ethernet_disable","status":"PASS","result":"%s","expected":"%s"}\n' "$state" "$expected"
    exit 0
else
    printf '{"rule":"system_settings_ethernet_disable","status":"FAIL","result":"%s","expected":"%s"}\n' "$state" "$expected"
    exit 1
fi
