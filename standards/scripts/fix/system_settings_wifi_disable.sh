#!/bin/zsh --no-rcs
# =============================================================================
# Rule:      system_settings_wifi_disable
# Source:    800-53r5_high
# Category:  System Settings
# Standards: cisv8, 800-53r5_high
# Description: Disable Wi-Fi Interface
# =============================================================================
# Exit codes: 0=PASS/OK  1=FAIL/ERROR  2=NOT_APPLICABLE  3=ERROR(root)

if [[ $EUID -ne 0 ]]; then
    printf '{"rule":"system_settings_wifi_disable","status":"ERROR","message":"Must be run as root"}\n'
    exit 3
fi

if ! /usr/sbin/networksetup -listallnetworkservices 2>/dev/null | /usr/bin/grep -qx "Wi-Fi"; then
    printf '{"rule":"system_settings_wifi_disable","action":"NOT_APPLICABLE","message":"No Wi-Fi service present"}\n'
    exit 2
fi

/usr/sbin/networksetup -setnetworkserviceenabled "Wi-Fi" off >/dev/null 2>&1
svc_rc=$?

WIFI_DEV=$(/usr/sbin/networksetup -listallhardwareports 2>/dev/null \
    | /usr/bin/awk '/Hardware Port: Wi-Fi/{getline; print $2}')
if [[ -n "$WIFI_DEV" ]]; then
    /usr/sbin/networksetup -setairportpower "$WIFI_DEV" off >/dev/null 2>&1
fi

if [[ $svc_rc -eq 0 ]]; then
    printf '{"rule":"system_settings_wifi_disable","action":"EXECUTED","message":"Wi-Fi service disabled and radio powered off"}\n'
    exit 0
else
    printf '{"rule":"system_settings_wifi_disable","action":"FAILED","message":"networksetup -setnetworkserviceenabled failed"}\n'
    exit 1
fi
