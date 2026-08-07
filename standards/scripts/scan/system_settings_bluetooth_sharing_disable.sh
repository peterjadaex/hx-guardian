#!/bin/zsh --no-rcs
# =============================================================================
# Rule:      system_settings_bluetooth_sharing_disable
# Source:    800-53r5_high
# Category:  System Settings
# Standards: cis_lvl2, cisv8, 800-53r5_high
# Description: Disable Bluetooth Sharing
# =============================================================================
# Hand-maintained — do not overwrite with generate_scripts.py output.
# Exit codes: 0=PASS/OK  1=FAIL/ERROR  2=NOT_APPLICABLE  3=ERROR(root)

if [[ $EUID -ne 0 ]]; then
    printf '{"rule":"system_settings_bluetooth_sharing_disable","status":"ERROR","message":"Must be run as root"}\n'
    exit 3
fi

# Console user via scutil — loginwindow's lastUserName is only the name shown at
# the login window, which can be stale or empty; reading another user's ByHost
# preference makes this check disagree with the fix.
CURRENT_USER=$(/usr/sbin/scutil <<< "show State:/Users/ConsoleUser" | /usr/bin/awk '/Name :/ && ! /loginwindow/ { print $3 }')
if [[ -z "$CURRENT_USER" ]]; then
    printf '{"rule":"system_settings_bluetooth_sharing_disable","status":"ERROR","message":"No console user — cannot read per-user ByHost preference"}\n'
    exit 1
fi

result_value=$(/usr/bin/sudo -u "$CURRENT_USER" /usr/bin/defaults -currentHost read com.apple.Bluetooth PrefKeyServicesEnabled 2>/dev/null
)
expected_value="0"

if [[ "$result_value" == "$expected_value" ]]; then
    printf '{"rule":"system_settings_bluetooth_sharing_disable","status":"PASS","result":"%s","expected":"%s"}\n' "$result_value" "$expected_value"
    exit 0
else
    printf '{"rule":"system_settings_bluetooth_sharing_disable","status":"FAIL","result":"%s","expected":"%s"}\n' "$result_value" "$expected_value"
    exit 1
fi
