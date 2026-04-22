#!/bin/zsh --no-rcs
# =============================================================================
# Rule:      system_settings_screen_sharing_disable (UNDO)
# Category:  System Settings
# Description: Re-enable the screensharing LaunchDaemon.
# =============================================================================
# Exit codes: 0=OK  1=ERROR  3=ERROR(root)

if [[ $EUID -ne 0 ]]; then
    printf '{"rule":"system_settings_screen_sharing_disable","status":"ERROR","message":"Must be run as root"}\n'
    exit 3
fi

/bin/launchctl enable system/com.apple.screensharing
/bin/launchctl bootstrap system /System/Library/LaunchDaemons/com.apple.screensharing.plist 2>/dev/null

printf '{"rule":"system_settings_screen_sharing_disable","action":"UNDONE","message":"Undo applied"}\n'
exit 0
