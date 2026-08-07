#!/bin/zsh --no-rcs
# =============================================================================
# Rule:      system_settings_wifi_disable (UNDO)
# Category:  System Settings
# Description: Re-enable the Wi-Fi service and power the radio back on.
# =============================================================================
# Hand-maintained — do not overwrite with generate_scripts.py output.
# Exit codes: 0=OK  1=ERROR  3=ERROR(root)

if [[ $EUID -ne 0 ]]; then
    printf '{"rule":"system_settings_wifi_disable","status":"ERROR","message":"Must be run as root"}\n'
    exit 3
fi

# A disabled service is listed as "*Wi-Fi" — the asterisk is exactly the state
# this undo exists to reverse, so the guard must match it or the undo no-ops.
if ! /usr/sbin/networksetup -listallnetworkservices 2>/dev/null | /usr/bin/grep -qxE '\*?Wi-Fi'; then
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
