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
cp -R "$DIST_DIR/hxg-server"      "$TRANSFER_DIR/app/dist/"
cp -R "$DIST_DIR/hxg-runner"      "$TRANSFER_DIR/app/dist/"
cp -R "$DIST_DIR/hxg-usb-watcher" "$TRANSFER_DIR/app/dist/"

# Installer + management scripts
cp "$APP_DIR/install.sh"                                          "$TRANSFER_DIR/app/"
cp "$APP_DIR/update.sh"                                           "$TRANSFER_DIR/app/"
cp "$APP_DIR/start.sh"                                            "$TRANSFER_DIR/app/"
cp "$APP_DIR/stop.sh"                                             "$TRANSFER_DIR/app/"
cp "$APP_DIR/restart.sh"                                          "$TRANSFER_DIR/app/"
# Server plist is generated inline by install.sh (with UserName substituted) — not copied here
cp "$APP_DIR/launchd/com.hxguardian.runner.plist"                 "$TRANSFER_DIR/app/launchd/"
cp "$REPO_ROOT/standards/launchd/com.hxguardian.usbwatcher.plist" "$TRANSFER_DIR/standards/launchd/"

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
check "app/install.sh"                               "$TRANSFER_DIR/app/install.sh"
check "app/update.sh"                               "$TRANSFER_DIR/app/update.sh"
check "app/launchd/com.hxguardian.runner.plist"     "$TRANSFER_DIR/app/launchd/com.hxguardian.runner.plist"
check "standards/launchd/usbwatcher.plist"           "$TRANSFER_DIR/standards/launchd/com.hxguardian.usbwatcher.plist"
check "standards/scripts/manifest.json"              "$TRANSFER_DIR/standards/scripts/manifest.json"
check "standards/mobileconfigs (800-53r5_high)"      "$TRANSFER_DIR/standards/800-53r5_high/mobileconfigs/unsigned"
check "standards/unified (unified profile)"          "$TRANSFER_DIR/standards/unified/com.hxguardian.unified.mobileconfig"

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
echo "   rm -rf ~/hxg-install   ← optional: remove after install"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
