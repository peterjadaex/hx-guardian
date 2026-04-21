#!/bin/zsh
# HX-Guardian — Deploy pre-built binaries and restart services.
# Run this on the airgap device after copying a fresh transfer package,
# or on the dev machine after running build.sh.
#
# Does NOT require Python — binaries must already be built in app/dist/.
#
# Usage (from hx-guardian repo root or an unpacked transfer directory):
#   sudo zsh app/update.sh            # deploy all three
#   sudo zsh app/update.sh runner     # deploy + restart runner only
#   sudo zsh app/update.sh server     # deploy + restart server only
#   sudo zsh app/update.sh usbwatcher # deploy + restart USB watcher only

set -euo pipefail

APP_DIR="$(cd "$(dirname "$0")" && pwd)"
DIST_DIR="$APP_DIR/dist"
HXG_BIN="/Library/Application Support/hxguardian/bin"
ACTUAL_USER="${SUDO_USER:-$(whoami)}"

TARGET="${1:-all}"

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo " HX-Guardian — Update"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

if [[ $EUID -ne 0 ]]; then
    echo "ERROR: Must run as root. Use: sudo zsh app/update.sh"
    exit 1
fi

# ── Validate binaries exist ─────────────────────────────────────────────────
case "$TARGET" in
    runner)      BINARIES=(hxg-runner) ;;
    server)      BINARIES=(hxg-server) ;;
    usbwatcher)  BINARIES=(hxg-usb-watcher) ;;
    all)         BINARIES=(hxg-server hxg-runner hxg-usb-watcher) ;;
    *)
        echo "ERROR: Unknown target '$TARGET'. Use: all | runner | server | usbwatcher"
        exit 1
        ;;
esac

for binary in "${BINARIES[@]}"; do
    if [[ ! -f "$DIST_DIR/$binary/$binary" ]]; then
        echo "ERROR: Binary not found: $DIST_DIR/$binary/$binary"
        echo "  Run build.sh on the dev machine first, then re-prepare the transfer package."
        exit 1
    fi
done

# ── Deploy ──────────────────────────────────────────────────────────────────
echo "[1/2] Deploying binaries..."

deploy_binary() {
    local name="$1"
    echo "  Deploying $name..."
    rm -rf "$HXG_BIN/$name"
    cp -R "$DIST_DIR/$name" "$HXG_BIN/"
    chown -R root:wheel "$HXG_BIN/$name"
    chmod -R 755 "$HXG_BIN/$name"
    xattr -dr com.apple.quarantine "$HXG_BIN/$name" 2>/dev/null || true
    codesign --force --deep --sign - "$HXG_BIN/$name/$name" 2>/dev/null || true
    echo "  ✓ $name deployed"
}

for binary in "${BINARIES[@]}"; do
    deploy_binary "$binary"
done

# ── Restart ─────────────────────────────────────────────────────────────────
echo ""
echo "[2/2] Restarting services..."

restart_runner() {
    launchctl kickstart -k system/com.hxguardian.runner 2>/dev/null \
        || { launchctl unload /Library/LaunchDaemons/com.hxguardian.runner.plist 2>/dev/null || true
             launchctl load -w /Library/LaunchDaemons/com.hxguardian.runner.plist; }
    echo "  ✓ Runner restarted"
}

restart_server() {
    launchctl kickstart -k system/com.hxguardian.server 2>/dev/null \
        || { launchctl bootout system /Library/LaunchDaemons/com.hxguardian.server.plist 2>/dev/null || true
             launchctl bootstrap system /Library/LaunchDaemons/com.hxguardian.server.plist; }
    echo "  ✓ Server restarted"
}

restart_usbwatcher() {
    launchctl kickstart -k system/com.hxguardian.usbwatcher 2>/dev/null \
        || { launchctl unload /Library/LaunchDaemons/com.hxguardian.usbwatcher.plist 2>/dev/null || true
             launchctl load -w /Library/LaunchDaemons/com.hxguardian.usbwatcher.plist; }
    echo "  ✓ USB Watcher restarted"
}

case "$TARGET" in
    runner)     restart_runner ;;
    server)     restart_server ;;
    usbwatcher) restart_usbwatcher ;;
    all)
        restart_runner
        restart_server
        restart_usbwatcher
        ;;
esac

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo " Update complete!"
echo ""
echo " Logs:"
echo "   tail -f /Library/Logs/hxguardian-runner.log"
echo "   tail -f /Library/Logs/hxguardian-server-error.log"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
