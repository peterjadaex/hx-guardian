#!/bin/zsh --no-rcs
# =============================================================================
# Rule:      system_settings_ethernet_disable (UNDO)
# Category:  System Settings
# Description: Re-enable the Ethernet service.
# =============================================================================
# Hand-maintained — do not overwrite with generate_scripts.py output.
# A disabled service is listed as "*Ethernet"; the guard must match it too.
# Exit codes: 0=OK  1=ERROR  3=ERROR(root)

if [[ $EUID -ne 0 ]]; then
    printf '{"rule":"system_settings_ethernet_disable","status":"ERROR","message":"Must be run as root"}\n'
    exit 3
fi

if ! /usr/sbin/networksetup -listallnetworkservices 2>/dev/null | /usr/bin/grep -qxE '\*?Ethernet'; then
    printf '{"rule":"system_settings_ethernet_disable","action":"UNDONE","message":"No Ethernet service present"}\n'
    exit 0
fi

/usr/sbin/networksetup -setnetworkserviceenabled "Ethernet" on >/dev/null 2>&1

printf '{"rule":"system_settings_ethernet_disable","action":"UNDONE","message":"Ethernet service re-enabled"}\n'
exit 0
