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

# Console user via scutil — loginwindow's lastUserName can be stale or empty,
# which would silently check the wrong user's Dock preferences.
CURRENT_USER=$(/usr/sbin/scutil <<< "show State:/Users/ConsoleUser" | /usr/bin/awk '/Name :/ && ! /loginwindow/ { print $3 }')
if [[ -z "$CURRENT_USER" ]]; then
    printf '{"rule":"system_settings_hot_corners_secure","status":"ERROR","message":"No console user — cannot read per-user Dock preferences"}\n'
    exit 1
fi

result_value=$(bl_corner="$(/usr/bin/defaults read /Users/"$CURRENT_USER"/Library/Preferences/com.apple.dock wvous-bl-corner 2>/dev/null)"
tl_corner="$(/usr/bin/defaults read /Users/"$CURRENT_USER"/Library/Preferences/com.apple.dock wvous-tl-corner 2>/dev/null)"
tr_corner="$(/usr/bin/defaults read /Users/"$CURRENT_USER"/Library/Preferences/com.apple.dock wvous-tr-corner 2>/dev/null)"
br_corner="$(/usr/bin/defaults read /Users/"$CURRENT_USER"/Library/Preferences/com.apple.dock wvous-br-corner 2>/dev/null)"

if [[ "$bl_corner" != "6" ]] && [[ "$tl_corner" != "6" ]] && [[ "$tr_corner" != "6" ]] && [[ "$br_corner" != "6" ]]; then
  echo "0"
fi
)
expected_value="0"

if [[ "$result_value" == "$expected_value" ]]; then
    printf '{"rule":"system_settings_hot_corners_secure","status":"PASS","result":"%s","expected":"%s"}\n' "$result_value" "$expected_value"
    exit 0
else
    printf '{"rule":"system_settings_hot_corners_secure","status":"FAIL","result":"%s","expected":"%s"}\n' "$result_value" "$expected_value"
    exit 1
fi
