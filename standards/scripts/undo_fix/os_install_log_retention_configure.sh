#!/bin/zsh --no-rcs
# =============================================================================
# Rule:      os_install_log_retention_configure (UNDO)
# Category:  Operating System
# Description: Strip the 'ttl=365' retention token from the install.log ASL
#              config (returns to macOS default retention behaviour).
# =============================================================================
# Exit codes: 0=OK  1=ERROR  3=ERROR(root)

if [[ $EUID -ne 0 ]]; then
    printf '{"rule":"os_install_log_retention_configure","status":"ERROR","message":"Must be run as root"}\n'
    exit 3
fi

/usr/bin/sed -i.undo.bak -E 's/ ttl=365//' /etc/asl/com.apple.install

printf '{"rule":"os_install_log_retention_configure","action":"UNDONE","message":"Undo applied"}\n'
exit 0
