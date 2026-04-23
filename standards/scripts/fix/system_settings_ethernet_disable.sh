#!/bin/zsh --no-rcs
# =============================================================================
# Rule:      system_settings_ethernet_disable
# Source:    hxguardian
# Category:  System Settings
# Standards: hxguardian
# Description: Disable Ethernet Interface
# =============================================================================
# Exit codes: 0=PASS/OK  1=FAIL/ERROR  2=NOT_APPLICABLE  3=ERROR(root)

if [[ $EUID -ne 0 ]]; then
    printf '{"rule":"system_settings_ethernet_disable","status":"ERROR","message":"Must be run as root"}\n'
    exit 3
fi

if ! /usr/sbin/networksetup -listallnetworkservices 2>/dev/null | /usr/bin/grep -qx "Ethernet"; then
    printf '{"rule":"system_settings_ethernet_disable","action":"NOT_APPLICABLE","message":"No Ethernet service present"}\n'
    exit 2
fi

/usr/sbin/networksetup -setnetworkserviceenabled "Ethernet" off >/dev/null 2>&1
rc=$?

if [[ $rc -eq 0 ]]; then
    printf '{"rule":"system_settings_ethernet_disable","action":"EXECUTED","message":"Ethernet service disabled"}\n'
    exit 0
else
    printf '{"rule":"system_settings_ethernet_disable","action":"FAILED","message":"networksetup -setnetworkserviceenabled failed"}\n'
    exit 1
fi
