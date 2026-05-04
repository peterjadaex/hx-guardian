#!/bin/zsh
# HX-Guardian Install Script — DEV variant
# Run: sudo zsh app/install-dev.sh
# Must be run from the hx-guardian repo root directory.
#
# Compared to install.sh, this script omits the steps that change device
# behavior beyond running the dashboard:
#   - USB watcher daemon (would force-eject non-whitelisted USB storage)
#   - pwpolicy enforcement (15-char passwords, 5-attempt lockout)
#   - Opening the unified .mobileconfig (would disable Bluetooth, iCloud,
#     AirDrop, AppleID, etc. once approved)
# Bluetooth, Wi-Fi, USB storage, iCloud and so on stay working as normal.

set -euo pipefail

APP_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(dirname "$APP_DIR")"

HXG_SUPPORT="/Library/Application Support/hxguardian"
HXG_BIN="$HXG_SUPPORT/bin"
HXG_DATA="$HXG_SUPPORT/data"
HXG_SCRIPTS="$HXG_SUPPORT"   # standards/ is copied here; paths stay standards/scripts/...

DIST_DIR="$APP_DIR/dist"

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo " HX-Guardian Security Dashboard — Installation (dev install)"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

# Check root
if [[ $EUID -ne 0 ]]; then
    echo "ERROR: Must run as root. Use: sudo zsh app/install-dev.sh"
    exit 1
fi

ACTUAL_USER="${SUDO_USER:-admin}"
echo "Installing for user: $ACTUAL_USER"

# ── Cleanup previous install ──────────────────────────────────────────────────
echo ""
echo "[cleanup] Removing previous installation..."

# 1. Unload launchd services. Label-wildcard instead of a hardcoded list so any
#    stray com.hxguardian.* registration (from an older install, a renamed
#    service, or a hand-edited plist) is drained — including a usbwatcher from
#    a prior airgap install on this machine.
/bin/launchctl list 2>/dev/null \
    | /usr/bin/awk '$3 ~ /^com\.hxguardian\./ {print $3}' \
    | while read -r label; do
          /bin/launchctl bootout "system/$label" 2>/dev/null || true
      done

# 2. Kill any lingering processes (crash-looping services may leave zombies)
pkill -f 'hxg-server'        2>/dev/null || true
pkill -f 'hxg-runner'        2>/dev/null || true
pkill -f 'hxg-usb-watcher'   2>/dev/null || true
pkill -f 'hxg-shell-watcher' 2>/dev/null || true
sleep 1
# Force-kill anything still hanging
pkill -9 -f 'hxg-server'        2>/dev/null || true
pkill -9 -f 'hxg-runner'        2>/dev/null || true
pkill -9 -f 'hxg-usb-watcher'   2>/dev/null || true
pkill -9 -f 'hxg-shell-watcher' 2>/dev/null || true

# 3. Remove plist files. Glob both the system LaunchDaemons dir and any
#    LaunchAgents location — covers stray agents that an operator may have
#    dropped manually, which the hardcoded list could not reach.
#    `(N)` is the zsh null-glob qualifier: on a fresh install (no matches)
#    it expands to nothing silently instead of aborting the script.
setopt LOCAL_OPTIONS NULL_GLOB
_hxg_stale_plists=(
    /Library/LaunchDaemons/com.hxguardian.*.plist(N)
    /Library/LaunchAgents/com.hxguardian.*.plist(N)
    "/Users/$ACTUAL_USER"/Library/LaunchAgents/com.hxguardian.*.plist(N)
)
(( ${#_hxg_stale_plists} )) && rm -f "${_hxg_stale_plists[@]}"
unset _hxg_stale_plists

# 3b. Remove any previous hxguardian audit block from /etc/zshrc so the install
#     step below writes a single current copy (block is fenced by sentinels).
if [[ -f /etc/zshrc ]] && grep -q '>>> hxguardian-audit >>>' /etc/zshrc 2>/dev/null; then
    /usr/bin/sed -i '' '/# >>> hxguardian-audit >>>/,/# <<< hxguardian-audit <<</d' /etc/zshrc
fi

# 4. Remove stale socket
rm -f /var/run/hxg/runner.sock

# 5. Remove stale log files (will be re-created with correct ownership)
rm -f /Library/Logs/hxguardian-server.log /Library/Logs/hxguardian-server-error.log
rm -f /Library/Logs/hxguardian-runner.log /Library/Logs/hxguardian-runner-error.log

# 6. Remove previous binaries
rm -rf "$HXG_BIN"
echo "  ✓ Previous install removed"

# Verify binaries exist (USB watcher omitted in dev install)
for binary in hxg-server hxg-runner hxg-shell-watcher; do
    if [[ ! -f "$DIST_DIR/$binary/$binary" ]]; then
        echo "ERROR: Binary not found: $DIST_DIR/$binary/$binary"
        echo "  Run: zsh app/build.sh"
        exit 1
    fi
done

# ── 0. Deploy binaries ────────────────────────────────────────────────────────
echo ""
echo "[0/7] Deploying binaries (server, runner, shell-watcher)..."
mkdir -p "$HXG_BIN" "$HXG_DATA"

# Remove any previous install (file or directory) to allow clean copy
rm -rf "$HXG_BIN/hxg-server" "$HXG_BIN/hxg-runner" "$HXG_BIN/hxg-shell-watcher"

cp -R "$DIST_DIR/hxg-server"        "$HXG_BIN/"
cp -R "$DIST_DIR/hxg-runner"        "$HXG_BIN/"
cp -R "$DIST_DIR/hxg-shell-watcher" "$HXG_BIN/"

chown -R root:wheel "$HXG_BIN/hxg-server" "$HXG_BIN/hxg-runner" "$HXG_BIN/hxg-shell-watcher"
chmod -R 755 "$HXG_BIN/hxg-server" "$HXG_BIN/hxg-runner" "$HXG_BIN/hxg-shell-watcher"

# Remove quarantine and ad-hoc sign so Gatekeeper does not block launch
xattr -dr com.apple.quarantine "$HXG_BIN/hxg-server"        2>/dev/null || true
xattr -dr com.apple.quarantine "$HXG_BIN/hxg-runner"        2>/dev/null || true
xattr -dr com.apple.quarantine "$HXG_BIN/hxg-shell-watcher" 2>/dev/null || true
codesign --force --deep --sign - "$HXG_BIN/hxg-server"        2>/dev/null || true
codesign --force --deep --sign - "$HXG_BIN/hxg-runner"        2>/dev/null || true
codesign --force --deep --sign - "$HXG_BIN/hxg-shell-watcher" 2>/dev/null || true

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
exec "$HXG_BIN/hxg-server/hxg-server"
EOF

cat > "$HXG_BIN/run-hxg-runner" << EOF
#!/bin/zsh
export HOME="/var/root"
export TMPDIR="/tmp"
cd "$HXG_BIN/hxg-runner"
exec "$HXG_BIN/hxg-runner/hxg-runner"
EOF

cat > "$HXG_BIN/run-hxg-shell-watcher" << EOF
#!/bin/zsh
export HOME="/var/root"
export TMPDIR="/tmp"
cd "$HXG_BIN/hxg-shell-watcher"
exec "$HXG_BIN/hxg-shell-watcher/hxg-shell-watcher"
EOF

chmod 755 "$HXG_BIN/run-hxg-server" "$HXG_BIN/run-hxg-runner" "$HXG_BIN/run-hxg-shell-watcher"
chown root:wheel "$HXG_BIN/run-hxg-server" "$HXG_BIN/run-hxg-runner" "$HXG_BIN/run-hxg-shell-watcher"

echo "  ✓ Binaries: $HXG_BIN  (USB watcher skipped — dev install)"

# ── 1. Deploy standards (scripts) with root-only permissions ──────────────────
echo ""
echo "[1/7] Deploying standards scripts (root-only)..."

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

# Deploy management scripts (start/stop/restart/rules_setup) into the support
# tree so the airgap operator can run them after removing ~/hxg-install. We do
# NOT deploy update.sh here — it needs the dist/ binary tree adjacent to it,
# which only exists in the SD-card bundle. update.sh stays bundle-local.
HXG_APP="$HXG_SUPPORT/app"
mkdir -p "$HXG_APP"
for f in start.sh stop.sh restart.sh rules_setup.sh; do
    cp "$APP_DIR/$f" "$HXG_APP/$f"
done
chown -R root:wheel "$HXG_APP"
chmod 755 "$HXG_APP"
chmod 755 "$HXG_APP"/*.sh
echo "  ✓ Management scripts: $HXG_APP/{start,stop,restart,rules_setup}.sh"

# ── 1b. Ensure Xcode Command Line Tools are present ──────────────────────────
# CLT supplies /usr/bin/python3 (required by rules_setup.sh) and on pre-Tahoe
# macOS also supplies /usr/bin/xmllint (used by 19 scan/fix scripts). On
# Tahoe+, xmllint is bundled in base macOS but python3 is still a CLT shim —
# so we always need CLT on airgap devices. We detect using `xcode-select -p`
# (canonical signal) rather than size-checking individual binaries, since
# that check is unreliable across macOS versions.
echo ""
echo "[1b/7] Verifying Xcode Command Line Tools..."

clt_installed() {
    # Canonical check: xcode-select -p returns the active developer dir and
    # that directory actually exists on disk. Size-checking /usr/bin/xmllint
    # is unreliable — on macOS 26 Tahoe xmllint ships in base macOS even
    # without CLT, so the size check reports "installed" when it isn't.
    # python3, which rules_setup.sh depends on, is still a CLT shim on Tahoe.
    local p
    p=$(xcode-select -p 2>/dev/null) || return 1
    [[ -n "$p" && -d "$p" ]]
}

install_clt_from_pkg() {
    local pkg="$1"
    echo "  Installing $(basename "$pkg") (this takes ~2 min)..."
    installer -pkg "$pkg" -target / >/dev/null
}

install_clt_from_dmg() {
    local dmg="$1"
    local mount_point pkg
    echo "  Mounting $(basename "$dmg")..."
    mount_point=$(hdiutil attach -nobrowse -noverify "$dmg" \
        | awk -F'\t' '/\/Volumes\// {print $NF}' | tail -1)
    if [[ -z "$mount_point" || ! -d "$mount_point" ]]; then
        echo "  ERROR: Could not mount $dmg"
        return 1
    fi
    pkg=$(find "$mount_point" -maxdepth 2 -name "*.pkg" | head -1)
    if [[ -z "$pkg" ]]; then
        echo "  ERROR: No .pkg found inside the .dmg"
        hdiutil detach "$mount_point" -quiet 2>/dev/null || true
        return 1
    fi
    install_clt_from_pkg "$pkg"
    local rc=$?
    hdiutil detach "$mount_point" -quiet 2>/dev/null || true
    return $rc
}

if clt_installed; then
    echo "  ✓ CLT already installed: $(xcode-select -p 2>/dev/null)"
else
    echo "  /usr/bin/xmllint is a CLT shim — looking for bundled CLT installer..."
    CLT_DIR="$APP_DIR/vendor/clt"
    CLT_PKG=""
    CLT_DMG=""
    if [[ -d "$CLT_DIR" ]]; then
        CLT_PKG=$(find "$CLT_DIR" -maxdepth 1 -name "*.pkg" 2>/dev/null | head -1)
        [[ -z "$CLT_PKG" ]] && CLT_DMG=$(find "$CLT_DIR" -maxdepth 1 -name "*.dmg" 2>/dev/null | head -1)
    fi

    if [[ -n "$CLT_PKG" ]]; then
        install_clt_from_pkg "$CLT_PKG" || { echo "ERROR: CLT install failed"; exit 1; }
    elif [[ -n "$CLT_DMG" ]]; then
        install_clt_from_dmg "$CLT_DMG" || { echo "ERROR: CLT install failed"; exit 1; }
    else
        echo ""
        echo "ERROR: Xcode Command Line Tools required but not installed, and no bundled installer found."
        echo ""
        echo "  HX-Guardian scan scripts need /usr/bin/xmllint (ships with CLT)."
        echo ""
        echo "  Install on a dev Mac with:  xcode-select --install"
        exit 1
    fi

    if ! clt_installed; then
        echo "ERROR: CLT installer ran but /usr/bin/xmllint is still a stub."
        exit 1
    fi
    echo "  ✓ CLT installed: $(xcode-select -p 2>/dev/null)"
fi

# ── 2. Unix socket directory ──────────────────────────────────────────────────
echo ""
echo "[2/7] Creating Unix socket directory..."
mkdir -p /var/run/hxg
chown root:admin /var/run/hxg 2>/dev/null || chown root:staff /var/run/hxg
chmod 770 /var/run/hxg
echo "  ✓ Socket directory: /var/run/hxg"

# ── 3. Pre-create log files ──────────────────────────────────────────────────
echo ""
echo "[3/7] Creating log files..."
# Runner logs: root-owned (LaunchDaemons run as root, can create their own)
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
echo "[4/7] Installing launchd plists (USB watcher omitted in dev install)..."

RUNNER_PLIST="/Library/LaunchDaemons/com.hxguardian.runner.plist"
# Snapshot before overwrite — see comment in install.sh for rationale.
if [[ -f "$RUNNER_PLIST" ]]; then
    cp -p "$RUNNER_PLIST" "$RUNNER_PLIST.bak.$(date +%s)" 2>/dev/null || true
fi
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
    <dict>
        <key>SuccessfulExit</key>
        <false/>
        <key>Crashed</key>
        <true/>
    </dict>

    <key>ThrottleInterval</key>
    <integer>10</integer>

    <key>ExitTimeOut</key>
    <integer>15</integer>

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

SHELL_PLIST="/Library/LaunchDaemons/com.hxguardian.shellwatcher.plist"
cp -X "$REPO_ROOT/standards/launchd/com.hxguardian.shellwatcher.plist" "$SHELL_PLIST"
xattr -c "$SHELL_PLIST" 2>/dev/null || true
chown root:wheel "$SHELL_PLIST"
chmod 644 "$SHELL_PLIST"
touch /var/log/hxguardian_shell.log
chmod 644 /var/log/hxguardian_shell.log
echo "  ✓ Shell Watcher plist: $SHELL_PLIST"

# ── 4b. System-wide zsh history audit config ─────────────────────────────────
# The shell watcher tails ~/.zsh_history, but zsh's default is to flush only on
# shell exit — so without this, commands are invisible to audit until the
# operator closes their Terminal window. INC_APPEND_HISTORY makes zsh append
# each command immediately; EXTENDED_HISTORY adds an epoch prefix so the
# watcher records the real execution time rather than "when I saw it".
#
# Written to /etc/zshrc (sourced by all interactive zsh sessions before the
# user's ~/.zshrc) inside a fenced block so it can be updated/removed cleanly.
# The old block is stripped in step 3b above so re-running install.sh is
# idempotent; this step always writes the current definition.
echo ""
echo "[4b/7] Enabling real-time zsh history audit..."

# /etc/zshrc exists by default on macOS; create it if a fresh install ever lacks it
touch /etc/zshrc
cat >> /etc/zshrc << 'ZSHRC'
# >>> hxguardian-audit >>>
# Managed by hxguardian install.sh — edits inside this block will be overwritten.
# Enables real-time capture of typed commands into the HX-Guardian audit log.
if [[ -o interactive ]]; then
    setopt INC_APPEND_HISTORY   # append each command to ~/.zsh_history immediately
    setopt EXTENDED_HISTORY     # prefix each line with epoch timestamp
fi
# <<< hxguardian-audit <<<
ZSHRC
chown root:wheel /etc/zshrc
chmod 644 /etc/zshrc
echo "  ✓ /etc/zshrc updated — new zsh sessions capture commands in real time"

# ── 5. Password policy ───────────────────────────────────────────────────────
echo ""
echo "[5/7] Password policy enforcement..."
echo "  → skipped (dev install)"

# ── 6. Start services ───────────────────────────────────────────────────────
echo ""
echo "[6/7] Starting services..."
zsh "$APP_DIR/start.sh"

# ── 7. Unified configuration profile ─────────────────────────────────────────
echo ""
echo "[7/7] Unified configuration profile..."
echo "  → skipped (dev install) — Bluetooth, iCloud, AirDrop, etc. left untouched"

# ── Done ──────────────────────────────────────────────────────────────────────
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo " Dev installation complete!"
echo ""
echo " Skipped (vs. install.sh):"
echo "   - USB watcher daemon (no force-eject of USB storage)"
echo "   - Password policy via pwpolicy"
echo "   - Unified .mobileconfig profile"
echo ""
echo " Manage services:"
echo "   sudo zsh app/start.sh"
echo "   sudo zsh app/stop.sh"
echo "   sudo zsh app/restart.sh"
echo ""
echo " Apply updates (no full reinstall):"
echo "   zsh app/build.sh                  <- rebuild binaries"
echo "   sudo zsh app/update.sh runner     <- deploy runner only"
echo "   sudo zsh app/update.sh server     <- deploy server only"
echo "   sudo zsh app/update.sh            <- deploy all"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
