#!/bin/zsh
# HX-Guardian Install Script
# Run: sudo zsh app/install.sh
# Must be run from the hx-guardian repo root directory.

set -euo pipefail

APP_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(dirname "$APP_DIR")"

HXG_SUPPORT="/Library/Application Support/hxguardian"
HXG_BIN="$HXG_SUPPORT/bin"
HXG_DATA="$HXG_SUPPORT/data"
HXG_SCRIPTS="$HXG_SUPPORT"   # standards/ is copied here; paths stay standards/scripts/...

DIST_DIR="$APP_DIR/dist"

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo " HX-Guardian Security Dashboard — Installation"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

# Check root
if [[ $EUID -ne 0 ]]; then
    echo "ERROR: Must run as root. Use: sudo zsh app/install.sh"
    exit 1
fi

ACTUAL_USER="${SUDO_USER:-admin}"
echo "Installing for user: $ACTUAL_USER"

# ── Cleanup previous install ──────────────────────────────────────────────────
echo ""
echo "[cleanup] Removing previous installation..."

# 1. Unload launchd services (may already be gone — ignore errors)
launchctl bootout system /Library/LaunchDaemons/com.hxguardian.server.plist      2>/dev/null || true
launchctl bootout system /Library/LaunchDaemons/com.hxguardian.runner.plist      2>/dev/null || true
launchctl bootout system /Library/LaunchDaemons/com.hxguardian.usbwatcher.plist  2>/dev/null || true

# 2. Kill any lingering processes (crash-looping services may leave zombies)
pkill -f 'hxg-server'      2>/dev/null || true
pkill -f 'hxg-runner'      2>/dev/null || true
pkill -f 'hxg-usb-watcher' 2>/dev/null || true
sleep 1
# Force-kill anything still hanging
pkill -9 -f 'hxg-server'      2>/dev/null || true
pkill -9 -f 'hxg-runner'      2>/dev/null || true
pkill -9 -f 'hxg-usb-watcher' 2>/dev/null || true

# 3. Remove plist files
rm -f /Library/LaunchDaemons/com.hxguardian.server.plist
rm -f /Library/LaunchDaemons/com.hxguardian.runner.plist
rm -f /Library/LaunchDaemons/com.hxguardian.usbwatcher.plist

# 4. Remove stale socket
rm -f /var/run/hxg/runner.sock

# 5. Remove stale log files (will be re-created with correct ownership)
rm -f /Library/Logs/hxguardian-server.log /Library/Logs/hxguardian-server-error.log
rm -f /Library/Logs/hxguardian-runner.log /Library/Logs/hxguardian-runner-error.log

# 6. Remove previous binaries
rm -rf "$HXG_BIN"
echo "  ✓ Previous install removed"

# Verify binaries exist
for binary in hxg-server hxg-runner hxg-usb-watcher; do
    if [[ ! -f "$DIST_DIR/$binary/$binary" ]]; then
        echo "ERROR: Binary not found: $DIST_DIR/$binary/$binary"
        echo "  Run: zsh app/build.sh  (on an internet-connected Mac)"
        exit 1
    fi
done

# ── 0. Deploy binaries ────────────────────────────────────────────────────────
echo ""
echo "[0/5] Deploying binaries..."
mkdir -p "$HXG_BIN" "$HXG_DATA"

# Remove any previous install (file or directory) to allow clean copy
rm -rf "$HXG_BIN/hxg-server" "$HXG_BIN/hxg-runner" "$HXG_BIN/hxg-usb-watcher"

cp -R "$DIST_DIR/hxg-server"      "$HXG_BIN/"
cp -R "$DIST_DIR/hxg-runner"      "$HXG_BIN/"
cp -R "$DIST_DIR/hxg-usb-watcher" "$HXG_BIN/"

chown -R root:wheel "$HXG_BIN/hxg-server" "$HXG_BIN/hxg-runner" "$HXG_BIN/hxg-usb-watcher"
chmod -R 755 "$HXG_BIN/hxg-server" "$HXG_BIN/hxg-runner" "$HXG_BIN/hxg-usb-watcher"

# Remove quarantine and ad-hoc sign so Gatekeeper does not block launch
xattr -dr com.apple.quarantine "$HXG_BIN/hxg-server"      2>/dev/null || true
xattr -dr com.apple.quarantine "$HXG_BIN/hxg-runner"      2>/dev/null || true
xattr -dr com.apple.quarantine "$HXG_BIN/hxg-usb-watcher" 2>/dev/null || true
codesign --force --deep --sign - "$HXG_BIN/hxg-server"      2>/dev/null || true
codesign --force --deep --sign - "$HXG_BIN/hxg-runner"      2>/dev/null || true
codesign --force --deep --sign - "$HXG_BIN/hxg-usb-watcher" 2>/dev/null || true

# Data directory owned by the operator user so the server (non-root) can write to it
chown "$ACTUAL_USER":staff "$HXG_DATA"
chmod 750 "$HXG_DATA"

# Create wrapper scripts — launchd runs in a stripped environment that can cause
# PyInstaller onedir binaries to fail. Wrappers set TMPDIR/HOME and cd to the
# binary directory before exec, matching what a terminal session provides.
cat > "$HXG_BIN/run-hxg-server" << EOF
#!/bin/zsh
export HOME="/Users/$ACTUAL_USER"
export TMPDIR="/tmp"
export USER="$ACTUAL_USER"
cd "$HXG_BIN/hxg-server"
"$HXG_BIN/hxg-server/hxg-server"
EOF

cat > "$HXG_BIN/run-hxg-runner" << EOF
#!/bin/zsh
export HOME="/var/root"
export TMPDIR="/tmp"
cd "$HXG_BIN/hxg-runner"
"$HXG_BIN/hxg-runner/hxg-runner"
EOF

cat > "$HXG_BIN/run-hxg-usb-watcher" << EOF
#!/bin/zsh
export HOME="/var/root"
export TMPDIR="/tmp"
cd "$HXG_BIN/hxg-usb-watcher"
"$HXG_BIN/hxg-usb-watcher/hxg-usb-watcher"
EOF

chmod 755 "$HXG_BIN/run-hxg-server" "$HXG_BIN/run-hxg-runner" "$HXG_BIN/run-hxg-usb-watcher"
chown root:wheel "$HXG_BIN/run-hxg-server" "$HXG_BIN/run-hxg-runner" "$HXG_BIN/run-hxg-usb-watcher"

echo "  ✓ Binaries: $HXG_BIN"

# ── 1. Deploy standards (scripts) with root-only permissions ──────────────────
echo ""
echo "[1/5] Deploying standards scripts (root-only)..."

# Copy the standards/ directory tree into HXG_SUPPORT
cp -R "$REPO_ROOT/standards/." "$HXG_SCRIPTS/"

# Top-level standard directories must be traversable by the server (runs as the
# operator user, not root). cp -R may preserve restrictive source permissions.
for std in 800-53r5_high cisv8 cis_lvl2 unified; do
    [[ -d "$HXG_SCRIPTS/$std" ]] && chmod 755 "$HXG_SCRIPTS/$std"
done

# Fine-grained permissions:
#   manifest.json  — readable by server (runs as admin user)
#   scan/fix .sh   — root only (operators cannot read the script logic)
chown -R root:wheel "$HXG_SCRIPTS/scripts"

# Directories: traversable by all (711) so the server can reach manifest.json
find "$HXG_SCRIPTS/scripts" -type d -exec chmod 711 {} \;

# manifest.json: world-readable (rule names/metadata only, no script source)
chmod 644 "$HXG_SCRIPTS/scripts/manifest.json"

# All shell scripts: root-only (hides the actual checking/fix logic)
find "$HXG_SCRIPTS/scripts" -name "*.sh" -exec chmod 700 {} \;

# mobileconfigs: readable by the server (runs as the operator user, not root).
# These are published standards — no sensitive content, world-readable is fine.
find "$HXG_SCRIPTS" -type d -name "mobileconfigs" | while read -r dir; do
    chmod -R 755 "$dir"
done

echo "  ✓ Scripts deployed — manifest readable, .sh files root-only, mobileconfigs world-readable"

# ── 2. Unix socket directory ──────────────────────────────────────────────────
echo ""
echo "[2/5] Creating Unix socket directory..."
mkdir -p /var/run/hxg
chown root:admin /var/run/hxg 2>/dev/null || chown root:staff /var/run/hxg
chmod 770 /var/run/hxg
echo "  ✓ Socket directory: /var/run/hxg"

# ── 3. Pre-create log files ──────────────────────────────────────────────────
echo ""
echo "[3/5] Creating log files..."
# Runner/USB logs: root-owned (LaunchDaemons run as root, can create their own)
touch /Library/Logs/hxguardian-runner.log /Library/Logs/hxguardian-runner-error.log
chown root:wheel /Library/Logs/hxguardian-runner.log /Library/Logs/hxguardian-runner-error.log
chmod 644 /Library/Logs/hxguardian-runner.log /Library/Logs/hxguardian-runner-error.log
# Server logs: user-owned (LaunchAgent runs as the user — the per-user launchd
# cannot create files in /Library/Logs/ so these must be pre-created here)
touch /Library/Logs/hxguardian-server.log /Library/Logs/hxguardian-server-error.log
chown "$ACTUAL_USER":staff /Library/Logs/hxguardian-server.log /Library/Logs/hxguardian-server-error.log
chmod 644 /Library/Logs/hxguardian-server.log /Library/Logs/hxguardian-server-error.log
echo "  ✓ Log files created in /Library/Logs/"

# ── 4. Install launchd plists ────────────────────────────────────────────────
echo ""
echo "[4/5] Installing launchd plists..."

RUNNER_PLIST="/Library/LaunchDaemons/com.hxguardian.runner.plist"
cp -X "$APP_DIR/launchd/com.hxguardian.runner.plist" "$RUNNER_PLIST"
xattr -c "$RUNNER_PLIST" 2>/dev/null || true
chown root:wheel "$RUNNER_PLIST"
chmod 644 "$RUNNER_PLIST"
echo "  ✓ Runner plist: $RUNNER_PLIST"

SERVER_PLIST="/Library/LaunchDaemons/com.hxguardian.server.plist"
cat > "$SERVER_PLIST" << PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>com.hxguardian.server</string>

    <key>UserName</key>
    <string>$ACTUAL_USER</string>

    <key>ProgramArguments</key>
    <array>
        <string>/bin/zsh</string>
        <string>/Library/Application Support/hxguardian/bin/run-hxg-server</string>
    </array>

    <key>RunAtLoad</key>
    <true/>

    <key>KeepAlive</key>
    <true/>

    <key>StandardOutPath</key>
    <string>/Library/Logs/hxguardian-server.log</string>

    <key>StandardErrorPath</key>
    <string>/Library/Logs/hxguardian-server-error.log</string>
</dict>
</plist>
PLIST
xattr -c "$SERVER_PLIST" 2>/dev/null || true
chown root:wheel "$SERVER_PLIST"
chmod 644 "$SERVER_PLIST"
echo "  ✓ Server plist (LaunchDaemon): $SERVER_PLIST"

USB_PLIST="/Library/LaunchDaemons/com.hxguardian.usbwatcher.plist"
cp -X "$REPO_ROOT/standards/launchd/com.hxguardian.usbwatcher.plist" "$USB_PLIST"
xattr -c "$USB_PLIST" 2>/dev/null || true
chown root:wheel "$USB_PLIST"
chmod 644 "$USB_PLIST"
touch /var/log/hxguardian_usb.log
chmod 644 /var/log/hxguardian_usb.log
echo "  ✓ USB Watcher plist: $USB_PLIST"

# ── 5. Start services ───────────────────────────────────────────────────────
echo ""
echo "[5/5] Starting services..."
zsh "$APP_DIR/start.sh"

# ── Done ──────────────────────────────────────────────────────────────────────
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo " Installation complete!"
echo ""
echo " Manage services:"
echo "   sudo zsh app/start.sh"
echo "   sudo zsh app/stop.sh"
echo "   sudo zsh app/restart.sh"
echo ""
echo " Apply updates (no full reinstall):"
echo "   zsh app/build.sh                  <- rebuild binaries (dev machine)"
echo "   sudo zsh app/update.sh runner     <- deploy runner only"
echo "   sudo zsh app/update.sh server     <- deploy server only"
echo "   sudo zsh app/update.sh            <- deploy all three"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
