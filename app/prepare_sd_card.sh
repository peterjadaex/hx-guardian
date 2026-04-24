#!/bin/zsh
# HX-Guardian SD Card Bundle Preparation Script
# Run this on an internet-connected Mac BEFORE transferring to the airgap device.
#
# Usage:
#   zsh app/prepare_sd_card.sh
#
# Must be run from the hx-guardian repo root directory.
# Output: a minimal transfer/ directory — copy only that to the SD card.

set -euo pipefail

# Ensure core tools resolve regardless of caller's PATH configuration.
export PATH="/usr/bin:/bin:/usr/sbin:/sbin:${PATH:-}"

APP_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(dirname "$APP_DIR")"
DIST_DIR="$APP_DIR/dist"
TRANSFER_DIR="$REPO_ROOT/transfer"

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo " HX-Guardian — SD Card Bundle Preparation"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

if [[ ! -f "$APP_DIR/install.sh" ]]; then
    echo "ERROR: Must be run from the hx-guardian repo root."
    echo "  cd /path/to/hx-guardian && zsh app/prepare_sd_card.sh"
    exit 1
fi

# ── 1. Build binaries (always rebuild fresh so transfer has latest code) ─────
echo "[1/3] Building binaries..."
echo ""
zsh "$APP_DIR/build.sh"
echo ""

# ── 2. Assemble minimal transfer package ─────────────────────────────────────
echo ""
echo "[2/3] Assembling transfer package..."

rm -rf "$TRANSFER_DIR"
mkdir -p \
    "$TRANSFER_DIR/app/dist" \
    "$TRANSFER_DIR/app/launchd" \
    "$TRANSFER_DIR/standards/launchd"

# Binary directories (onedir mode — each is a folder containing the executable + deps)
cp -R "$DIST_DIR/hxg-server"        "$TRANSFER_DIR/app/dist/"
cp -R "$DIST_DIR/hxg-runner"        "$TRANSFER_DIR/app/dist/"
cp -R "$DIST_DIR/hxg-usb-watcher"   "$TRANSFER_DIR/app/dist/"
cp -R "$DIST_DIR/hxg-shell-watcher" "$TRANSFER_DIR/app/dist/"

# Installer + management scripts
cp "$APP_DIR/install.sh"                                          "$TRANSFER_DIR/app/"
cp "$APP_DIR/update.sh"                                           "$TRANSFER_DIR/app/"
cp "$APP_DIR/start.sh"                                            "$TRANSFER_DIR/app/"
cp "$APP_DIR/stop.sh"                                             "$TRANSFER_DIR/app/"
cp "$APP_DIR/restart.sh"                                          "$TRANSFER_DIR/app/"
cp "$APP_DIR/rules_setup.sh"                                      "$TRANSFER_DIR/app/"
# Server plist is generated inline by install.sh (with UserName substituted) — not copied here
cp "$APP_DIR/launchd/com.hxguardian.runner.plist"                   "$TRANSFER_DIR/app/launchd/"
cp "$REPO_ROOT/standards/launchd/com.hxguardian.usbwatcher.plist"   "$TRANSFER_DIR/standards/launchd/"
cp "$REPO_ROOT/standards/launchd/com.hxguardian.shellwatcher.plist" "$TRANSFER_DIR/standards/launchd/"

# Standards scripts (scan/fix shell scripts + manifest)
cp -R "$REPO_ROOT/standards/scripts" "$TRANSFER_DIR/standards/"

# MDM profiles (mobileconfig files for profile-only rules)
for standard in 800-53r5_high cisv8 cis_lvl2; do
    mc_dir="$REPO_ROOT/standards/$standard/mobileconfigs/unsigned"
    if [[ -d "$mc_dir" ]]; then
        mkdir -p "$TRANSFER_DIR/standards/$standard/mobileconfigs"
        cp -R "$mc_dir" "$TRANSFER_DIR/standards/$standard/mobileconfigs/"
    fi
done

# Unified MDM profile (merged from all standards)
if [[ -d "$REPO_ROOT/standards/unified" ]]; then
    cp -R "$REPO_ROOT/standards/unified" "$TRANSFER_DIR/standards/unified"
fi

# Admin/operator runbook (markdown source + styled, offline-viewable HTML).
# Placed at the TOP of the transfer bundle (not under standards/) so the admin
# sees the readme immediately when opening the SD card.
for doc in airgap_readme.md airgap_readme.html; do
    if [[ -f "$REPO_ROOT/standards/$doc" ]]; then
        cp "$REPO_ROOT/standards/$doc" "$TRANSFER_DIR/$doc"
    fi
done

# Bundle the Xcode Command Line Tools installer.
# Airgap devices don't have CLT out of the box, and /usr/bin/xmllint is a CLT
# shim that pops the xcode-select GUI. Rather than ship a bare xmllint binary
# (blocked by arm64e codesigning requirements on Apple Silicon), we ship the
# official CLT installer and install.sh installs it silently — only if
# /usr/bin/xmllint on the airgap device is still a stub.
CLT_SRC="$APP_DIR/vendor/clt"
if [[ -d "$CLT_SRC" ]] && ls "$CLT_SRC"/*.{dmg,pkg}(.N) >/dev/null 2>&1; then
    mkdir -p "$TRANSFER_DIR/app/vendor/clt"
    cp "$CLT_SRC"/*.dmg "$TRANSFER_DIR/app/vendor/clt/" 2>/dev/null || true
    cp "$CLT_SRC"/*.pkg "$TRANSFER_DIR/app/vendor/clt/" 2>/dev/null || true
    CLT_SIZE=$(du -sh "$TRANSFER_DIR/app/vendor/clt" | awk '{print $1}')
    echo "  ✓ CLT installer bundled from $CLT_SRC ($CLT_SIZE)"
else
    echo ""
    echo "  WARNING: No Xcode Command Line Tools installer found at $CLT_SRC/"
    echo "           install.sh will fail on airgap devices that don't already have CLT."
    echo ""
    echo "  To stage the installer for future bundles:"
    echo "    1. Download 'Command Line Tools for Xcode' .dmg from"
    echo "       https://developer.apple.com/download/all/ (match the airgap macOS version)."
    echo "    2. Place the .dmg at: $CLT_SRC/"
    echo "    3. Re-run this script."
    echo ""
fi

echo "  ✓ Transfer package: $TRANSFER_DIR"
du -sh "$TRANSFER_DIR" | awk '{print "  Size: " $1}'

# ── 3. Verify ─────────────────────────────────────────────────────────────────
echo ""
echo "[3/3] Verifying package..."

check() {
    local label="$1"; local path="$2"
    if [[ -e "$path" ]]; then
        echo "  [✓] $label"
    else
        echo "  [✗] MISSING: $label"
        MISSING=true
    fi
}

MISSING=false
check "app/dist/hxg-server"                          "$TRANSFER_DIR/app/dist/hxg-server/hxg-server"
check "app/dist/hxg-runner"                          "$TRANSFER_DIR/app/dist/hxg-runner/hxg-runner"
check "app/dist/hxg-usb-watcher"                     "$TRANSFER_DIR/app/dist/hxg-usb-watcher/hxg-usb-watcher"
check "app/dist/hxg-shell-watcher"                   "$TRANSFER_DIR/app/dist/hxg-shell-watcher/hxg-shell-watcher"
check "app/install.sh"                               "$TRANSFER_DIR/app/install.sh"
check "app/update.sh"                               "$TRANSFER_DIR/app/update.sh"
check "app/start.sh"                                 "$TRANSFER_DIR/app/start.sh"
check "app/stop.sh"                                  "$TRANSFER_DIR/app/stop.sh"
check "app/restart.sh"                               "$TRANSFER_DIR/app/restart.sh"
check "app/rules_setup.sh"                          "$TRANSFER_DIR/app/rules_setup.sh"
check "app/launchd/com.hxguardian.runner.plist"     "$TRANSFER_DIR/app/launchd/com.hxguardian.runner.plist"
check "standards/launchd/usbwatcher.plist"           "$TRANSFER_DIR/standards/launchd/com.hxguardian.usbwatcher.plist"
check "standards/launchd/shellwatcher.plist"         "$TRANSFER_DIR/standards/launchd/com.hxguardian.shellwatcher.plist"
check "standards/scripts/manifest.json"              "$TRANSFER_DIR/standards/scripts/manifest.json"
check "fix/pwpolicy_account_inactivity_enforce"      "$TRANSFER_DIR/standards/scripts/fix/pwpolicy_account_inactivity_enforce.sh"
check "fix/os_account_modification_disable"          "$TRANSFER_DIR/standards/scripts/fix/os_account_modification_disable.sh"
check "fix/os_firewall_default_deny_require"         "$TRANSFER_DIR/standards/scripts/fix/os_firewall_default_deny_require.sh"
check "fix/os_recover_lock_enable"                   "$TRANSFER_DIR/standards/scripts/fix/os_recover_lock_enable.sh"
check "scan/os_recover_lock_enable"                  "$TRANSFER_DIR/standards/scripts/scan/os_recover_lock_enable.sh"
check "fix/system_settings_filevault_enforce"        "$TRANSFER_DIR/standards/scripts/fix/system_settings_filevault_enforce.sh"
check "fix/system_settings_find_my_disable"          "$TRANSFER_DIR/standards/scripts/fix/system_settings_find_my_disable.sh"
check "fix/system_settings_loginwindow_text"         "$TRANSFER_DIR/standards/scripts/fix/system_settings_loginwindow_loginwindowtext_enable.sh"
check "fix/system_settings_token_removal_enforce"    "$TRANSFER_DIR/standards/scripts/fix/system_settings_token_removal_enforce.sh"
check "standards/mobileconfigs (800-53r5_high)"      "$TRANSFER_DIR/standards/800-53r5_high/mobileconfigs/unsigned"
check "standards/unified (unified profile)"          "$TRANSFER_DIR/standards/unified/com.hxguardian.unified.mobileconfig"
check "airgap_readme.md (top level)"                 "$TRANSFER_DIR/airgap_readme.md"
check "airgap_readme.html (top level)"               "$TRANSFER_DIR/airgap_readme.html"

# CLT bundling is optional (warned above if missing) — just report status.
if [[ -d "$TRANSFER_DIR/app/vendor/clt" ]] \
   && ls "$TRANSFER_DIR/app/vendor/clt"/*.{dmg,pkg}(.N) >/dev/null 2>&1; then
    echo "  [✓] app/vendor/clt (Xcode Command Line Tools installer)"
else
    echo "  [!] app/vendor/clt — NOT bundled (install.sh will fail on CLT-less airgap devices)"
fi

if [[ "$MISSING" == "true" ]]; then
    echo "  Some items missing. Re-run to retry."
    exit 1
fi

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo " Ready! Copy only the transfer/ directory:"
echo ""
echo "   cp -R transfer/ /Volumes/<SD_CARD>/hxg-install"
echo ""
echo " On the airgap device:"
echo ""
echo "   cp -R /Volumes/<SD_CARD>/hxg-install ~/hxg-install"
echo "   sudo zsh ~/hxg-install/app/install.sh"
echo "   open ~/hxg-install/standards/unified/com.hxguardian.unified.mobileconfig"
echo "   # → System Settings will open — go to Privacy & Security → Profiles → Install"
echo "   rm -rf ~/hxg-install   ← optional: remove after install"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
