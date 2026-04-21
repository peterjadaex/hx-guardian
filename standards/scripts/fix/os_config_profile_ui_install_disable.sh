#!/bin/zsh --no-rcs
# =============================================================================
# Rule:      os_config_profile_ui_install_disable
# Source:    800-53r5_high
# Category:  Operating System
# Standards: 800-53r5_high
# Description: Disable Installation of Configuration Profiles through the User Interface
# =============================================================================
# Exit codes: 0=PASS/OK  1=FAIL/ERROR  2=NOT_APPLICABLE  3=ERROR(root)

if [[ $EUID -ne 0 ]]; then
    printf '{"rule":"os_config_profile_ui_install_disable","status":"ERROR","message":"Must be run as root"}\n'
    exit 3
fi

mkdir -p "/Library/Managed Preferences"
/usr/bin/defaults write "/Library/Managed Preferences/com.apple.applicationaccess" \
    allowUIConfigurationProfileInstallation -bool false

if [[ $? -eq 0 ]]; then
    printf '{"rule":"os_config_profile_ui_install_disable","action":"EXECUTED","message":"Fix applied"}\n'
    exit 0
else
    printf '{"rule":"os_config_profile_ui_install_disable","action":"FAILED","message":"defaults write failed"}\n'
    exit 1
fi
