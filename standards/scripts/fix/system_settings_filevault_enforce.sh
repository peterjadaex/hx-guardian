#!/bin/zsh --no-rcs
# =============================================================================
# Rule:      system_settings_filevault_enforce
# Source:    800-53r5_high
# Category:  System Settings
# Standards: cis_lvl2, cisv8, 800-53r5_high
# Description: Enforce FileVault
# =============================================================================
# Exit codes: 0=PASS/OK  1=FAIL/ERROR  2=NOT_APPLICABLE  3=ERROR(root)

if [[ $EUID -ne 0 ]]; then
    printf '{"rule":"system_settings_filevault_enforce","status":"ERROR","message":"Must be run as root"}\n'
    exit 3
fi

HXG_DATA="/Library/Application Support/hxguardian/data"

# Step 1: Set managed pref to prevent FileVault being disabled
mkdir -p "/Library/Managed Preferences"
/usr/bin/defaults write "/Library/Managed Preferences/com.apple.MCX" \
    dontAllowFDEDisable -bool true

# Step 2: Enable FileVault if not already on
FV_STATUS=$(/usr/bin/fdesetup status 2>/dev/null | /usr/bin/grep -c "FileVault is On.")

if [[ $FV_STATUS -eq 1 ]]; then
    printf '{"rule":"system_settings_filevault_enforce","action":"EXECUTED","message":"FileVault already enabled. dontAllowFDEDisable enforced via managed preferences."}\n'
    exit 0
fi

# FileVault is off — defer enablement to next user login (no password required)
mkdir -p "$HXG_DATA"
/usr/bin/fdesetup enable \
    -defer "$HXG_DATA/fv_deferred.plist" \
    -forceatlogin 0 \
    -dontaskatlogout \
    2>/dev/null
DEFER_STATUS=$?

if [[ $DEFER_STATUS -eq 0 ]]; then
    printf '{"rule":"system_settings_filevault_enforce","action":"EXECUTED","message":"FileVault enablement deferred — will activate at next user login. dontAllowFDEDisable enforced."}\n'
    exit 0
else
    printf '{"rule":"system_settings_filevault_enforce","action":"FAILED","message":"fdesetup defer failed. Enable FileVault manually in System Settings > Privacy & Security > FileVault."}\n'
    exit 1
fi
