#!/bin/zsh
# HX-Guardian SD Card Bundle Preparation Script
# Run this on an internet-connected Mac BEFORE transferring to the airgap device.
#
# Usage:
#   zsh app/prepare_sd_card.sh              # Python wheels + Python installer
#   zsh app/prepare_sd_card.sh --with-node  # Also download Node.js installer
#
# Must be run from the hx-guardian repo root directory.

set -euo pipefail

APP_DIR="$(cd "$(dirname "$0")" && pwd)"
BACKEND_DIR="$APP_DIR/backend"
VENDOR_PYTHON="$BACKEND_DIR/vendor/python"
VENDOR_INSTALLERS="$BACKEND_DIR/vendor/installers"
WITH_NODE=false

for arg in "$@"; do
    [[ "$arg" == "--with-node" ]] && WITH_NODE=true
done

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo " HX-Guardian — SD Card Bundle Preparation"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

# Verify we're at the repo root
if [[ ! -f "$APP_DIR/install.sh" ]]; then
    echo "ERROR: Must be run from the hx-guardian repo root."
    echo "  cd /path/to/hx-guardian && zsh app/prepare_sd_card.sh"
    exit 1
fi

mkdir -p "$VENDOR_PYTHON" "$VENDOR_INSTALLERS"

# ── 1. Python wheels ──────────────────────────────────────────────────────────
echo "[1/3] Downloading Python wheels..."
pip3 download \
    -r "$BACKEND_DIR/requirements.txt" \
    -d "$VENDOR_PYTHON" \
    --platform macosx_13_0_arm64 \
    --platform macosx_13_0_x86_64 \
    --platform macosx_14_0_arm64 \
    --platform macosx_14_0_x86_64 \
    --only-binary=:all: \
    --python-version 3 \
    --quiet 2>/dev/null || \
pip3 download \
    -r "$BACKEND_DIR/requirements.txt" \
    -d "$VENDOR_PYTHON" \
    --quiet
echo "  ✓ Wheels saved to: $VENDOR_PYTHON"
echo "  $(ls "$VENDOR_PYTHON" | wc -l | tr -d ' ') files downloaded"

# ── 2. Python installer ───────────────────────────────────────────────────────
echo ""
echo "[2/3] Downloading Python installer..."

# Resolve latest Python 3.x from python.org download page
PYTHON_VERSION="3.13.3"
PYTHON_PKG="python-${PYTHON_VERSION}-macos11.pkg"
PYTHON_URL="https://www.python.org/ftp/python/${PYTHON_VERSION}/${PYTHON_PKG}"
PYTHON_DEST="$VENDOR_INSTALLERS/$PYTHON_PKG"

if [[ -f "$PYTHON_DEST" ]]; then
    echo "  ✓ Python installer already present: $PYTHON_PKG"
else
    echo "  Downloading Python ${PYTHON_VERSION} universal installer..."
    curl -L --progress-bar "$PYTHON_URL" -o "$PYTHON_DEST"
    echo "  ✓ Saved: $PYTHON_DEST"
fi

# ── 3. Node.js installer (optional) ──────────────────────────────────────────
echo ""
echo "[3/3] Node.js installer..."
if [[ "$WITH_NODE" == "true" ]]; then
    NODE_VERSION="22.15.0"
    NODE_PKG_ARM="node-v${NODE_VERSION}-darwin-arm64.tar.gz"
    NODE_PKG_X64="node-v${NODE_VERSION}-darwin-x64.tar.gz"
    NODE_BASE_URL="https://nodejs.org/dist/v${NODE_VERSION}"

    for NODE_PKG in "$NODE_PKG_ARM" "$NODE_PKG_X64"; do
        NODE_DEST="$VENDOR_INSTALLERS/$NODE_PKG"
        if [[ -f "$NODE_DEST" ]]; then
            echo "  ✓ Already present: $NODE_PKG"
        else
            echo "  Downloading $NODE_PKG ..."
            curl -L --progress-bar "${NODE_BASE_URL}/${NODE_PKG}" -o "$NODE_DEST"
            echo "  ✓ Saved: $NODE_DEST"
        fi
    done
else
    echo "  Skipped (frontend/dist/ is pre-built; Node.js not needed at runtime)"
    echo "  Pass --with-node to include Node.js installers for frontend rebuilds"
fi

# ── Checklist ─────────────────────────────────────────────────────────────────
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo " Bundle Checklist"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

check() {
    local label="$1"
    local path="$2"
    if [[ -e "$path" ]]; then
        echo "  [✓] $label"
    else
        echo "  [✗] MISSING: $label  ($path)"
        MISSING=true
    fi
}

MISSING=false
check "backend/requirements.txt"           "$BACKEND_DIR/requirements.txt"
check "vendor/python/ wheels"              "$VENDOR_PYTHON"
check "Python installer .pkg"             "$VENDOR_INSTALLERS/python-${PYTHON_VERSION}-macos11.pkg"
check "frontend/dist/ (pre-built UI)"     "$APP_DIR/frontend/dist/index.html"
check "install.sh"                         "$APP_DIR/install.sh"

if [[ "$WITH_NODE" == "true" ]]; then
    check "Node.js arm64 tarball"          "$VENDOR_INSTALLERS/$NODE_PKG_ARM"
    check "Node.js x64 tarball"           "$VENDOR_INSTALLERS/$NODE_PKG_X64"
fi

echo ""
if [[ "$MISSING" == "true" ]]; then
    echo "  Some items are missing. Re-run to retry downloads."
    exit 1
else
    echo "  All items present — ready to copy to SD card."
fi

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo " Next steps:"
echo ""
echo "  1. Copy this entire directory to the SD card:"
echo "       cp -R \"$(dirname "$APP_DIR")\" /Volumes/<SD_CARD>/hx-guardian"
echo ""
echo "  2. On the airgap device, copy from SD card:"
echo "       cp -R /Volumes/<SD_CARD>/hx-guardian ~/Documents/airgap/"
echo ""
echo "  3. Run the installer (fully offline):"
echo "       cd ~/Documents/airgap/hx-guardian"
echo "       sudo zsh app/install.sh"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
