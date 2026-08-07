#!/bin/zsh --no-rcs
# =============================================================================
# Rule:      system_settings_hot_corners_secure
# Source:    cisv8
# Category:  System Settings
# Standards: cis_lvl2, cisv8
# Description: Secure Hot Corners
# =============================================================================
# Hand-maintained — do not overwrite with generate_scripts.py output.
# Exit codes: 0=PASS/OK  1=FAIL/ERROR  2=NOT_APPLICABLE  3=ERROR(root)

if [[ $EUID -ne 0 ]]; then
    printf '{"rule":"system_settings_hot_corners_secure","status":"ERROR","message":"Must be run as root"}\n'
    exit 3
fi

# Console user via scutil — must match the user the scan reads, or the fix
# edits one account's Dock preferences while the scan checks another's.
CURRENT_USER=$(/usr/sbin/scutil <<< "show State:/Users/ConsoleUser" | /usr/bin/awk '/Name :/ && ! /loginwindow/ { print $3 }')
if [[ -z "$CURRENT_USER" ]]; then
    printf '{"rule":"system_settings_hot_corners_secure","action":"ERROR","message":"No console user — cannot edit per-user Dock preferences"}\n'
    exit 1
fi

# `defaults delete` of an absent key exits non-zero; that is fine here — the
# goal state is "key absent" — so errors are suppressed per corner.
/usr/bin/sudo -u "$CURRENT_USER" /usr/bin/defaults delete /Users/"$CURRENT_USER"/Library/Preferences/com.apple.dock wvous-bl-corner 2>/dev/null
/usr/bin/sudo -u "$CURRENT_USER" /usr/bin/defaults delete /Users/"$CURRENT_USER"/Library/Preferences/com.apple.dock wvous-tl-corner 2>/dev/null
/usr/bin/sudo -u "$CURRENT_USER" /usr/bin/defaults delete /Users/"$CURRENT_USER"/Library/Preferences/com.apple.dock wvous-tr-corner 2>/dev/null
/usr/bin/sudo -u "$CURRENT_USER" /usr/bin/defaults delete /Users/"$CURRENT_USER"/Library/Preferences/com.apple.dock wvous-br-corner 2>/dev/null

# Flush the user's preference daemon so a cached value cannot be written back.
/usr/bin/killall -u "$CURRENT_USER" cfprefsd 2>/dev/null || true

printf '{"rule":"system_settings_hot_corners_secure","action":"EXECUTED","message":"Fix applied"}\n'
exit 0
