#!/bin/zsh
# HX-Guardian — Toggle the AnyDesk-friendly testing posture.
#
# Companion artifact:
#   standards/unified/com.hxguardian.unified-testing.mobileconfig
# Operator must swap the MDM profile manually in System Settings → Device
# Management; Apple's profile-install flow on Tahoe cannot be scripted.
#
# Usage:
#   sudo zsh app/relax-for-testing.sh enable      # turn ON testing posture
#   sudo zsh app/relax-for-testing.sh revert      # restore production posture

set -euo pipefail

ANYDESK_APP="/Applications/AnyDesk.app"
ALF="/usr/libexec/ApplicationFirewall/socketfilterfw"
NS="/usr/sbin/networksetup"

if [[ $EUID -ne 0 ]]; then
    echo "ERROR: must run as root. Use: sudo zsh $0 ${1:-enable}"
    exit 1
fi

case "${1:-}" in
    enable)
        echo "━━━ HX-Guardian — enabling testing posture ━━━"

        echo "[1/3] Enabling Wi-Fi..."
        $NS -setairportpower en0 on              2>/dev/null || true
        $NS -setnetworkserviceenabled "Wi-Fi" on 2>/dev/null || true

        echo "[2/3] Allow AnyDesk through application firewall..."
        if [[ -d "$ANYDESK_APP" ]]; then
            $ALF --add        "$ANYDESK_APP" >/dev/null 2>&1 || true
            $ALF --unblockapp "$ANYDESK_APP" >/dev/null 2>&1 || true
            $ALF --listapps | /usr/bin/grep -A1 -i AnyDesk || true
        else
            echo "  ⚠ AnyDesk not installed at $ANYDESK_APP"
            echo "    Install AnyDesk first (PKG via SD card), then re-run this script."
        fi

        echo "[3/3] Manual follow-ups (cannot be scripted):"
        echo "  • System Settings → Privacy & Security:"
        echo "      Screen Recording  → enable AnyDesk"
        echo "      Accessibility     → enable AnyDesk"
        echo "      Full Disk Access  → enable AnyDesk (only if file transfer needs ~/Library)"
        echo "  • System Settings → General → Device Management:"
        echo "      Remove   HX-Guardian Unified"
        echo "      Install  standards/unified/com.hxguardian.unified-testing.mobileconfig"
        echo ""
        echo "Done. HX-Guardian compliance scans will now show a few expected FAILs"
        echo "(system_settings_wifi_disable, os_firewall_default_deny_require, possibly"
        echo "os_bonjour_disable). This is the correct, expected signal for testing posture."
        ;;

    revert)
        echo "━━━ HX-Guardian — reverting to production posture ━━━"

        echo "[1/3] Removing AnyDesk firewall allow-list entry..."
        if [[ -d "$ANYDESK_APP" ]]; then
            $ALF --remove "$ANYDESK_APP" >/dev/null 2>&1 || true
        fi

        echo "[2/3] Disabling Wi-Fi..."
        $NS -setairportpower en0 off              2>/dev/null || true
        $NS -setnetworkserviceenabled "Wi-Fi" off 2>/dev/null || true

        echo "[3/3] Manual follow-ups:"
        echo "  • System Settings → General → Device Management:"
        echo "      Remove   HX-Guardian Unified — Testing"
        echo "      Install  standards/unified/com.hxguardian.unified.mobileconfig"
        echo "  • Optional cleanup:  sudo rm -rf $ANYDESK_APP"
        echo ""
        echo "Done. Trigger a full HX-Guardian scan — all rules should return to PASS."
        ;;

    *)
        echo "Usage: sudo zsh $0 enable | revert"
        exit 1
        ;;
esac
