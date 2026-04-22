#!/bin/zsh --no-rcs
# =============================================================================
# Rule:      os_firewall_default_deny_require (UNDO)
# Category:  Operating System
# Description: Remove the hxguardian pf anchor and its pf.conf references,
#              then reload pf.
# =============================================================================
# Exit codes: 0=OK  1=ERROR  3=ERROR(root)

if [[ $EUID -ne 0 ]]; then
    printf '{"rule":"os_firewall_default_deny_require","status":"ERROR","message":"Must be run as root"}\n'
    exit 3
fi

/bin/rm -f /etc/pf.anchors/hxguardian

/usr/bin/sed -i.undo.bak \
    -e '/# HX-Guardian: default-deny inbound firewall/d' \
    -e '/^anchor "hxguardian"$/d' \
    -e '/^load anchor "hxguardian" from/d' \
    /etc/pf.conf

/sbin/pfctl -f /etc/pf.conf 2>/dev/null

printf '{"rule":"os_firewall_default_deny_require","action":"UNDONE","message":"Undo applied"}\n'
exit 0
