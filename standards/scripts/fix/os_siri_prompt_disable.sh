#!/bin/zsh --no-rcs
# =============================================================================
# Rule:      os_siri_prompt_disable
# Source:    800-53r5_high
# Category:  Operating System
# Standards: cisv8, 800-53r5_high
# Description: Disable Siri Setup during Setup Assistant
# =============================================================================
# Exit codes: 0=PASS/OK  1=FAIL/ERROR  2=NOT_APPLICABLE  3=ERROR(root)

if [[ $EUID -ne 0 ]]; then
    printf '{"rule":"os_siri_prompt_disable","status":"ERROR","message":"Must be run as root"}\n'
    exit 3
fi

# Cannot be applied by script: cfprefsd/mdmclient revert direct writes to /Library/Managed Preferences.
# Install the HX-Guardian Unified profile and approve it in System Settings to satisfy this rule.
printf '{"rule":"os_siri_prompt_disable","action":"NOT_APPLICABLE","message":"Install /Library/Application Support/hxguardian/unified/com.hxguardian.unified.mobileconfig and approve in System Settings > General > Device Management."}\n'
exit 2
