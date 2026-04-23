#!/bin/zsh --no-rcs
# =============================================================================
# Rule:      system_settings_wifi_disable (UNDO)
# Category:  System Settings
# Description: Re-enable the Wi-Fi service and power the radio back on.
# =============================================================================
# Exit codes: 0=OK  1=ERROR  3=ERROR(root)

if [[ $EUID -ne 0 ]]; then
    printf '{"rule":"system_settings_wifi_disable","status":"ERROR","message":"Must be run as root"}\n'
    exit 3
fi

if ! /usr/sbin/networksetup -listallnetworkservices 2>/dev/null | /usr/bin/grep -qx "Wi-Fi"; then
    printf '{"rule":"system_settings_wifi_disable","action":"UNDONE","message":"No Wi-Fi service present"}\n'
    exit 0
fi

/usr/sbin/networksetup -setnetworkserviceenabled "Wi-Fi" on >/dev/null 2>&1

WIFI_DEV=$(/usr/sbin/networksetup -listallhardwareports 2>/dev/null \
    | /usr/bin/awk '/Hardware Port: Wi-Fi/{getline; print $2}')
if [[ -n "$WIFI_DEV" ]]; then
    /usr/sbin/networksetup -setairportpower "$WIFI_DEV" on >/dev/null 2>&1
fi

printf '{"rule":"system_settings_wifi_disable","action":"UNDONE","message":"Wi-Fi service re-enabled"}\n'
exit 0
