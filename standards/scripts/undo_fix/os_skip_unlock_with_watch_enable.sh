#!/bin/zsh --no-rcs
# =============================================================================
# Rule:      os_skip_unlock_with_watch_enable (UNDO)
# Category:  Operating System
# Description: Remove the SkipSetupItems override (shared key — see note).
# =============================================================================
# Exit codes: 0=OK  1=ERROR  3=ERROR(root)

if [[ $EUID -ne 0 ]]; then
    printf '{"rule":"os_skip_unlock_with_watch_enable","status":"ERROR","message":"Must be run as root"}\n'
    exit 3
fi

/usr/bin/defaults delete "/Library/Managed Preferences/com.apple.SetupAssistant.managed" SkipSetupItems 2>/dev/null

printf '{"rule":"os_skip_unlock_with_watch_enable","action":"UNDONE","message":"Undo applied"}\n'
exit 0
