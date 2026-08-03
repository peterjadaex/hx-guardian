#!/bin/zsh
# HX-Guardian SD Card Bundle Preparation Script
# Run this on an internet-connected Mac BEFORE transferring to the airgap device.
#
# Usage:
#   zsh app/prepare_sd_card.sh
#
# Must be run from the hx-guardian repo root directory.
# Output: hxg-install.zip at the repository root.

set -euo pipefail

# Ensure core tools resolve regardless of caller's PATH configuration.
export PATH="/usr/bin:/bin:/usr/sbin:/sbin:${PATH:-}"

APP_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(dirname "$APP_DIR")"
DIST_DIR="$APP_DIR/dist"
ZIP_PATH="$REPO_ROOT/hxg-install.zip"
LEGACY_TRANSFER_DIR="$REPO_ROOT/transfer"
STAGING_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/hxg-transfer.XXXXXX")"
BUNDLE_DIR="$STAGING_ROOT/hxg-install"

cleanup() {
    rm -rf "$STAGING_ROOT"
}
trap cleanup EXIT

# Never leave a stale archive that could be mistaken for the current build.
rm -f "$ZIP_PATH"

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo " HX-Guardian — SD Card Bundle Preparation"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

if [[ ! -f "$APP_DIR/install.sh" ]]; then
    echo "ERROR: Must be run from the hx-guardian repo root."
    echo "  cd /path/to/hx-guardian && zsh app/prepare_sd_card.sh"
    exit 1
fi

# ── 1. Build binaries (always rebuild fresh so bundle has latest code) ───────
echo "[1/4] Building binaries..."
echo ""
zsh "$APP_DIR/build.sh"
echo ""

# ── 2. Assemble minimal bundle ────────────────────────────────────────────────
echo ""
echo "[2/4] Assembling bundle..."

rm -rf "$LEGACY_TRANSFER_DIR"
mkdir -p \
    "$BUNDLE_DIR/app/dist" \
    "$BUNDLE_DIR/app/launchd" \
    "$BUNDLE_DIR/standards/launchd"

# Binary directories (onedir mode — each is a folder containing the executable + deps)
cp -R "$DIST_DIR/hxg-server"        "$BUNDLE_DIR/app/dist/"
cp -R "$DIST_DIR/hxg-runner"        "$BUNDLE_DIR/app/dist/"
cp -R "$DIST_DIR/hxg-usb-watcher"   "$BUNDLE_DIR/app/dist/"
cp -R "$DIST_DIR/hxg-shell-watcher" "$BUNDLE_DIR/app/dist/"

# Installer + management scripts
cp "$APP_DIR/install.sh"                                          "$BUNDLE_DIR/app/"
cp "$APP_DIR/update.sh"                                           "$BUNDLE_DIR/app/"
cp "$APP_DIR/start.sh"                                            "$BUNDLE_DIR/app/"
cp "$APP_DIR/stop.sh"                                             "$BUNDLE_DIR/app/"
cp "$APP_DIR/restart.sh"                                          "$BUNDLE_DIR/app/"
cp "$APP_DIR/rules_setup.sh"                                      "$BUNDLE_DIR/app/"
cp "$APP_DIR/relax-for-testing.sh"                                "$BUNDLE_DIR/app/"
# Server plist is generated inline by install.sh (with UserName substituted) — not copied here
cp "$APP_DIR/launchd/com.hxguardian.runner.plist"                   "$BUNDLE_DIR/app/launchd/"
cp "$REPO_ROOT/standards/launchd/com.hxguardian.usbwatcher.plist"   "$BUNDLE_DIR/standards/launchd/"
cp "$REPO_ROOT/standards/launchd/com.hxguardian.shellwatcher.plist" "$BUNDLE_DIR/standards/launchd/"

# Standards scripts (scan/fix shell scripts + manifest)
cp -R "$REPO_ROOT/standards/scripts" "$BUNDLE_DIR/standards/"

# MDM profiles (mobileconfig files for profile-only rules)
for standard in 800-53r5_high cisv8 cis_lvl2; do
    mc_dir="$REPO_ROOT/standards/$standard/mobileconfigs/unsigned"
    if [[ -d "$mc_dir" ]]; then
        mkdir -p "$BUNDLE_DIR/standards/$standard/mobileconfigs"
        cp -R "$mc_dir" "$BUNDLE_DIR/standards/$standard/mobileconfigs/"
    fi
done

# Unified MDM profile (merged from all standards)
if [[ -d "$REPO_ROOT/standards/unified" ]]; then
    cp -R "$REPO_ROOT/standards/unified" "$BUNDLE_DIR/standards/unified"
fi

# Admin/operator runbook (markdown source + styled, offline-viewable HTML).
# Placed at the TOP of the transfer bundle (not under standards/) so the admin
# sees the readme immediately when opening the SD card.
for doc in airgap_readme.md airgap_readme.html; do
    if [[ -f "$REPO_ROOT/standards/$doc" ]]; then
        cp "$REPO_ROOT/standards/$doc" "$BUNDLE_DIR/$doc"
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
    mkdir -p "$BUNDLE_DIR/app/vendor/clt"
    cp "$CLT_SRC"/*.dmg "$BUNDLE_DIR/app/vendor/clt/" 2>/dev/null || true
    cp "$CLT_SRC"/*.pkg "$BUNDLE_DIR/app/vendor/clt/" 2>/dev/null || true
    CLT_SIZE=$(du -sh "$BUNDLE_DIR/app/vendor/clt" | awk '{print $1}')
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

echo "  ✓ Staged package: $BUNDLE_DIR"
du -sh "$BUNDLE_DIR" | awk '{print "  Size: " $1}'

# ── 3. Verify ─────────────────────────────────────────────────────────────────
echo ""
echo "[3/4] Verifying package..."

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
check "app/dist/hxg-server"                          "$BUNDLE_DIR/app/dist/hxg-server/hxg-server"
check "app/dist/hxg-runner"                          "$BUNDLE_DIR/app/dist/hxg-runner/hxg-runner"
check "app/dist/hxg-usb-watcher"                     "$BUNDLE_DIR/app/dist/hxg-usb-watcher/hxg-usb-watcher"
check "app/dist/hxg-shell-watcher"                   "$BUNDLE_DIR/app/dist/hxg-shell-watcher/hxg-shell-watcher"
check "app/install.sh"                               "$BUNDLE_DIR/app/install.sh"
check "app/update.sh"                                "$BUNDLE_DIR/app/update.sh"
check "app/start.sh"                                 "$BUNDLE_DIR/app/start.sh"
check "app/stop.sh"                                  "$BUNDLE_DIR/app/stop.sh"
check "app/restart.sh"                               "$BUNDLE_DIR/app/restart.sh"
check "app/rules_setup.sh"                           "$BUNDLE_DIR/app/rules_setup.sh"
check "app/relax-for-testing.sh"                     "$BUNDLE_DIR/app/relax-for-testing.sh"
check "app/launchd/com.hxguardian.runner.plist"      "$BUNDLE_DIR/app/launchd/com.hxguardian.runner.plist"
check "standards/launchd/usbwatcher.plist"           "$BUNDLE_DIR/standards/launchd/com.hxguardian.usbwatcher.plist"
check "standards/launchd/shellwatcher.plist"         "$BUNDLE_DIR/standards/launchd/com.hxguardian.shellwatcher.plist"
check "standards/scripts/manifest.json"              "$BUNDLE_DIR/standards/scripts/manifest.json"
check "fix/pwpolicy_account_inactivity_enforce"      "$BUNDLE_DIR/standards/scripts/fix/pwpolicy_account_inactivity_enforce.sh"
check "fix/os_account_modification_disable"          "$BUNDLE_DIR/standards/scripts/fix/os_account_modification_disable.sh"
check "fix/os_firewall_default_deny_require"         "$BUNDLE_DIR/standards/scripts/fix/os_firewall_default_deny_require.sh"
check "fix/os_recover_lock_enable"                   "$BUNDLE_DIR/standards/scripts/fix/os_recover_lock_enable.sh"
check "scan/os_recover_lock_enable"                  "$BUNDLE_DIR/standards/scripts/scan/os_recover_lock_enable.sh"
check "fix/system_settings_filevault_enforce"        "$BUNDLE_DIR/standards/scripts/fix/system_settings_filevault_enforce.sh"
check "fix/system_settings_find_my_disable"          "$BUNDLE_DIR/standards/scripts/fix/system_settings_find_my_disable.sh"
check "fix/system_settings_loginwindow_text"         "$BUNDLE_DIR/standards/scripts/fix/system_settings_loginwindow_loginwindowtext_enable.sh"
check "fix/system_settings_token_removal_enforce"    "$BUNDLE_DIR/standards/scripts/fix/system_settings_token_removal_enforce.sh"
check "standards/mobileconfigs (800-53r5_high)"      "$BUNDLE_DIR/standards/800-53r5_high/mobileconfigs/unsigned"
check "standards/unified (unified profile)"          "$BUNDLE_DIR/standards/unified/com.hxguardian.unified.mobileconfig"
check "standards/unified (testing profile)"          "$BUNDLE_DIR/standards/unified/com.hxguardian.unified-testing.mobileconfig"
check "airgap_readme.md (top level)"                 "$BUNDLE_DIR/airgap_readme.md"
check "airgap_readme.html (top level)"               "$BUNDLE_DIR/airgap_readme.html"

# CLT bundling is optional (warned above if missing) — just report status.
if [[ -d "$BUNDLE_DIR/app/vendor/clt" ]] \
   && ls "$BUNDLE_DIR/app/vendor/clt"/*.{dmg,pkg}(.N) >/dev/null 2>&1; then
    echo "  [✓] app/vendor/clt (Xcode Command Line Tools installer)"
else
    echo "  [!] app/vendor/clt — NOT bundled (install.sh will fail on CLT-less airgap devices)"
fi

if [[ "$MISSING" == "true" ]]; then
    echo "  Some items missing. Re-run to retry."
    exit 1
fi

echo ""
echo "[4/4] Creating ZIP archive..."
/usr/bin/ditto -c -k --keepParent "$BUNDLE_DIR" "$ZIP_PATH"
/usr/bin/unzip -tq "$ZIP_PATH"
echo "  ✓ Archive: $ZIP_PATH"
du -sh "$ZIP_PATH" | awk '{print "  Size: " $1}'

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo " Ready! Copy the ZIP archive to the SD card:"
echo ""
echo "   cp hxg-install.zip /Volumes/<SD_CARD>/"
echo ""
echo " On the airgap device:"
echo ""
echo "   ditto -x -k /Volumes/<SD_CARD>/hxg-install.zip ~/"
echo "   sudo zsh ~/hxg-install/app/install.sh"
echo "   open ~/hxg-install/standards/unified/com.hxguardian.unified.mobileconfig"
echo "   # → System Settings will open — go to Privacy & Security → Profiles → Install"
echo "   rm -rf ~/hxg-install   ← optional: remove after install"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
