#!/bin/zsh --no-rcs
# =============================================================================
# Rule:      os_firewall_default_deny_require
# Source:    800-53r5_high
# Category:  Operating System
# Standards: 800-53r5_high
# Description: Control Connections to Other Systems via a Deny-All and Allow-by-Exception Firewall Policy
# =============================================================================
# Exit codes: 0=PASS/OK  1=FAIL/ERROR  2=NOT_APPLICABLE  3=ERROR(root)

if [[ $EUID -ne 0 ]]; then
    printf '{"rule":"os_firewall_default_deny_require","status":"ERROR","message":"Must be run as root"}\n'
    exit 3
fi

# Write pf anchor rules:
#   block drop in all  — default-deny all inbound traffic
#   pass in quick on lo0 all  — exempts loopback so localhost services keep working
mkdir -p /etc/pf.anchors
cat > /etc/pf.anchors/hxguardian << 'PFRULES'
block drop in all
pass in quick on lo0 all
PFRULES

# Add anchor reference to pf.conf if not already present
if ! /usr/bin/grep -q 'anchor "hxguardian"' /etc/pf.conf; then
    printf '\n# HX-Guardian: default-deny inbound firewall\nanchor "hxguardian"\nload anchor "hxguardian" from "/etc/pf.anchors/hxguardian"\n' >> /etc/pf.conf
fi

# Load rules into the live pf ruleset immediately (persists via pf.conf on reboot)
/sbin/pfctl -f /etc/pf.conf 2>/dev/null
LOAD_STATUS=$?

if [[ $LOAD_STATUS -eq 0 ]]; then
    printf '{"rule":"os_firewall_default_deny_require","action":"EXECUTED","message":"pf anchor hxguardian loaded with block drop in all + loopback exemption"}\n'
    exit 0
else
    printf '{"rule":"os_firewall_default_deny_require","action":"FAILED","message":"pfctl -f /etc/pf.conf returned non-zero"}\n'
    exit 1
fi
