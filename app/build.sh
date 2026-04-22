#!/bin/zsh
# HX-Guardian Binary Build Script
# Run on an internet-connected Mac to produce standalone executables.
# Output: app/dist/hxg-server, hxg-runner, hxg-usb-watcher
#
# Usage:
#   zsh app/build.sh
#
# Must be run from the hx-guardian repo root directory.

set -euo pipefail

APP_DIR="$(cd "$(dirname "$0")" && pwd)"
BACKEND_DIR="$APP_DIR/backend"
DIST_DIR="$APP_DIR/dist"
# Per-user workpath — macOS $TMPDIR is already user-private (/var/folders/.../T),
# so this avoids the root-owned /tmp/hxg_build problem that occurs if the build
# was ever run under sudo.
WORK_DIR="${TMPDIR:-/tmp}"
WORK_DIR="${WORK_DIR%/}/hxg_build"

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo " HX-Guardian — Binary Build"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

if [[ ${EUID:-$(id -u)} -eq 0 ]]; then
    echo "ERROR: Do not run build.sh as root / via sudo."
    echo "  PyInstaller must run as the normal user so the workpath and"
    echo "  dist/ stay user-writable. Re-run without sudo."
    exit 1
fi

if [[ ! -f "$APP_DIR/install.sh" ]]; then
    echo "ERROR: Must be run from the hx-guardian repo root."
    echo "  cd /path/to/hx-guardian && zsh app/build.sh"
    exit 1
fi

# Clean any stale workpath + dist from a prior run (including ones that may have
# been left behind with wrong permissions). If either fails, the user hit the
# root-owned artifact case — tell them exactly how to fix it.
clean_or_die() {
    local path="$1"
    if [[ ! -e "$path" ]]; then
        return 0
    fi
    # Let rm's stderr through so the real errno is visible if it fails.
    local err
    if ! err=$(rm -rf "$path" 2>&1); then
        echo "ERROR: Cannot remove stale build artifact: $path"
        echo "  rm said: $err"
        echo ""
        echo "  If it's a permissions issue (owned by root from a prior sudo build), run:"
        echo "    sudo rm -rf \"$path\""
        echo "  If it's an immutable-flag issue, run:"
        echo "    chflags -R nouchg,noschg \"$path\" && rm -rf \"$path\""
        echo "  then re-run this script."
        exit 1
    fi
}
clean_or_die "$WORK_DIR"
clean_or_die "$DIST_DIR"

# ── 1. Ensure PyInstaller is available ───────────────────────────────────────
echo "[1/4] Checking Python..."

# Prefer python.org / Homebrew installs over Xcode CLT Python.
# Xcode CLT Python (/usr/bin/python3, /Library/Developer/...) is a restricted
# embedded build that does not work with PyInstaller.
PYTHON=""
for candidate in \
    /Library/Frameworks/Python.framework/Versions/3.13/bin/python3 \
    /Library/Frameworks/Python.framework/Versions/3.12/bin/python3 \
    /Library/Frameworks/Python.framework/Versions/3.11/bin/python3 \
    /Library/Frameworks/Python.framework/Versions/3.10/bin/python3 \
    /opt/homebrew/bin/python3 \
    /usr/local/bin/python3; do
    if [[ -x "$candidate" ]]; then
        PYTHON="$candidate"
        break
    fi
done

if [[ -z "$PYTHON" ]]; then
    echo ""
    echo "ERROR: No suitable Python found."
    echo "  Install Python from https://python.org (macOS installer)"
    echo "  Xcode CLT Python (/usr/bin/python3) does not work with PyInstaller."
    exit 1
fi

echo "  ✓ Using Python: $PYTHON ($($PYTHON --version))"

# ── 2. Install Python dependencies (needed for import analysis) ───────────────
echo ""
echo "[2/4] Installing Python dependencies (for import analysis)..."
"$PYTHON" -m pip install -r "$BACKEND_DIR/requirements.txt" --quiet
"$PYTHON" -m pip install pyinstaller --quiet
echo "  ✓ PyInstaller $("$PYTHON" -m PyInstaller --version)"
echo "  ✓ Dependencies ready"

# ── 3. Build binaries ─────────────────────────────────────────────────────────
echo ""
echo "[3/4] Building binaries..."
mkdir -p "$DIST_DIR"

cd "$BACKEND_DIR"

echo "  Building hxg-server..."
"$PYTHON" -m PyInstaller hxg_server.spec \
    --distpath "$DIST_DIR" \
    --workpath "$WORK_DIR" \
    --noconfirm \
    --log-level WARN

echo "  Building hxg-runner..."
"$PYTHON" -m PyInstaller hxg_runner.spec \
    --distpath "$DIST_DIR" \
    --workpath "$WORK_DIR" \
    --noconfirm \
    --log-level WARN

echo "  Building hxg-usb-watcher..."
"$PYTHON" -m PyInstaller hxg_usb_watcher.spec \
    --distpath "$DIST_DIR" \
    --workpath "$WORK_DIR" \
    --noconfirm \
    --log-level WARN

chmod +x "$DIST_DIR/hxg-server" "$DIST_DIR/hxg-runner" "$DIST_DIR/hxg-usb-watcher"

# Ad-hoc code sign — satisfies macOS AMFI/Gatekeeper for local execution
# without requiring an Apple Developer certificate
codesign --force --deep --sign - "$DIST_DIR/hxg-server"
codesign --force --deep --sign - "$DIST_DIR/hxg-runner"
codesign --force --deep --sign - "$DIST_DIR/hxg-usb-watcher"
echo "  ✓ Binaries built and signed"

cd - > /dev/null

# ── 4. Verify outputs ─────────────────────────────────────────────────────────
echo ""
echo "[4/4] Verifying outputs..."
MISSING=false
for binary in hxg-server hxg-runner hxg-usb-watcher; do
    if [[ -f "$DIST_DIR/$binary/$binary" ]]; then
        size=$(du -sh "$DIST_DIR/$binary" | cut -f1)
        echo "  ✓ $binary  ($size)"
    else
        echo "  ✗ MISSING: $binary"
        MISSING=true
    fi
done

echo ""
if [[ "$MISSING" == "true" ]]; then
    echo "  Build failed — one or more binaries are missing."
    exit 1
fi

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo " Build complete!"
echo ""
echo " Binaries: $DIST_DIR/"
echo ""
echo " Next steps:"
echo "   Copy to SD card:  cp -R . /Volumes/<SD_CARD>/hx-guardian"
echo "   Or run directly:  zsh app/prepare_sd_card.sh"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
