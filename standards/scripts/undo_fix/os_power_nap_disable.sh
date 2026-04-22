#!/bin/zsh --no-rcs
# =============================================================================
# Rule:      os_power_nap_disable (UNDO)
# Category:  Operating System
# Description: Re-enable Power Nap.
# =============================================================================
# Exit codes: 0=OK  1=ERROR  3=ERROR(root)

if [[ $EUID -ne 0 ]]; then
    printf '{"rule":"os_power_nap_disable","status":"ERROR","message":"Must be run as root"}\n'
    exit 3
fi

arch=$(/usr/bin/arch)
CURRENT_USER=$(/usr/bin/defaults read /Library/Preferences/com.apple.loginwindow lastUserName)
CURR_USER_UID=$(/usr/bin/id -u $CURRENT_USER)

rule_arch="i386"
if [[ "$arch" != "$rule_arch" ]]; then
    printf '{"rule":"os_power_nap_disable","action":"NOT_APPLICABLE","message":"Requires i386 architecture"}\n'
    exit 2
fi

/usr/bin/pmset -a powernap 1

printf '{"rule":"os_power_nap_disable","action":"UNDONE","message":"Undo applied"}\n'
exit 0
