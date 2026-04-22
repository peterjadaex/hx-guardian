#!/bin/zsh --no-rcs
# =============================================================================
# Rule:      os_config_profile_ui_install_disable (UNDO)
# Category:  Operating System
# Description: Remove the allowUIConfigurationProfileInstallation override.
# =============================================================================
# Exit codes: 0=OK  1=ERROR  3=ERROR(root)

if [[ $EUID -ne 0 ]]; then
    printf '{"rule":"os_config_profile_ui_install_disable","status":"ERROR","message":"Must be run as root"}\n'
    exit 3
fi

/usr/bin/defaults delete "/Library/Managed Preferences/com.apple.applicationaccess" allowUIConfigurationProfileInstallation 2>/dev/null

printf '{"rule":"os_config_profile_ui_install_disable","action":"UNDONE","message":"Undo applied"}\n'
exit 0
