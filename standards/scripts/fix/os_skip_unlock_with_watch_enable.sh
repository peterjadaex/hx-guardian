#!/bin/zsh --no-rcs
# =============================================================================
# Rule:      os_skip_unlock_with_watch_enable
# Source:    800-53r5_high
# Category:  Operating System
# Standards: cisv8, 800-53r5_high
# Description: Disable Unlock with Apple Watch During Setup Assistant
# =============================================================================
# Exit codes: 0=PASS/OK  1=FAIL/ERROR  2=NOT_APPLICABLE  3=ERROR(root)

if [[ $EUID -ne 0 ]]; then
    printf '{"rule":"os_skip_unlock_with_watch_enable","status":"ERROR","message":"Must be run as root"}\n'
    exit 3
fi

mkdir -p "/Library/Managed Preferences"
/usr/bin/defaults write "/Library/Managed Preferences/com.apple.SetupAssistant.managed" \
    SkipSetupItems -array AppleID iCloudStorage Privacy Siri Intelligence WatchMigration

if [[ $? -eq 0 ]]; then
    printf '{"rule":"os_skip_unlock_with_watch_enable","action":"EXECUTED","message":"Fix applied"}\n'
    exit 0
else
    printf '{"rule":"os_skip_unlock_with_watch_enable","action":"FAILED","message":"defaults write failed"}\n'
    exit 1
fi
