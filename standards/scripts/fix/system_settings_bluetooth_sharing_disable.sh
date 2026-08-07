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

# Console user via scutil — must match the user whose ByHost preference the
# scan reads, or the fix and the scan talk about different accounts.
CURRENT_USER=$(/usr/sbin/scutil <<< "show State:/Users/ConsoleUser" | /usr/bin/awk '/Name :/ && ! /loginwindow/ { print $3 }')
if [[ -z "$CURRENT_USER" ]]; then
    printf '{"rule":"system_settings_bluetooth_sharing_disable","action":"ERROR","message":"No console user — cannot write per-user ByHost preference"}\n'
    exit 1
fi

if ! /usr/bin/sudo -u "$CURRENT_USER" /usr/bin/defaults -currentHost write com.apple.Bluetooth PrefKeyServicesEnabled -bool false; then
    printf '{"rule":"system_settings_bluetooth_sharing_disable","action":"ERROR","message":"defaults write failed for user %s"}\n' "$CURRENT_USER"
    exit 1
fi

# Flush the user's preference daemon so a cached in-memory value cannot be
# flushed back over the change — the usual reason this setting "reverts".
/usr/bin/killall -u "$CURRENT_USER" cfprefsd 2>/dev/null || true

printf '{"rule":"system_settings_bluetooth_sharing_disable","action":"EXECUTED","message":"Fix applied"}\n'
exit 0
