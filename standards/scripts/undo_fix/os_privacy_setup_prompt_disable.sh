#!/bin/zsh --no-rcs
# =============================================================================
# Rule:      os_privacy_setup_prompt_disable (UNDO)
# Category:  Operating System
# Description: Remove the SkipSetupItems override. Note: this key is shared
#              with other Setup Assistant skip rules; undoing one removes them all.
# =============================================================================
# Exit codes: 0=OK  1=ERROR  3=ERROR(root)

if [[ $EUID -ne 0 ]]; then
    printf '{"rule":"os_privacy_setup_prompt_disable","status":"ERROR","message":"Must be run as root"}\n'
    exit 3
fi

/usr/bin/defaults delete "/Library/Managed Preferences/com.apple.SetupAssistant.managed" SkipSetupItems 2>/dev/null

printf '{"rule":"os_privacy_setup_prompt_disable","action":"UNDONE","message":"Undo applied"}\n'
exit 0
