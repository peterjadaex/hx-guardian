#!/bin/zsh
# HX-Guardian Install Script
# Run: sudo zsh app/install.sh
# Must be run from the hx-guardian repo root directory.

set -euo pipefail

APP_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(dirname "$APP_DIR")"
BACKEND_DIR="$APP_DIR/backend"
DATA_DIR="$APP_DIR/data"

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

# ── 1. Python dependencies ────────────────────────────────────────────────────
echo ""
echo "[1/6] Installing Python dependencies..."
if [[ -d "$BACKEND_DIR/vendor/python" ]] && ls "$BACKEND_DIR/vendor/python"/*.whl &>/dev/null 2>&1; then
    echo "  Using vendored wheels (offline install)..."
    sudo -u "$ACTUAL_USER" /usr/bin/python3 -m pip install \
        --no-index \
        --find-links="$BACKEND_DIR/vendor/python" \
        -r "$BACKEND_DIR/requirements.txt" \
        --quiet
else
    echo "  Installing from PyPI (requires internet)..."
    sudo -u "$ACTUAL_USER" /usr/bin/python3 -m pip install \
        -r "$BACKEND_DIR/requirements.txt" \
        --quiet
fi
echo "  ✓ Python dependencies installed"

# ── 2. Data directory ─────────────────────────────────────────────────────────
echo ""
echo "[2/6] Setting up data directory..."
mkdir -p "$DATA_DIR/reports"
chown -R "$ACTUAL_USER":staff "$DATA_DIR"
chmod -R 750 "$DATA_DIR"
echo "  ✓ Data directory: $DATA_DIR"

# ── 3. Unix socket directory ──────────────────────────────────────────────────
echo ""
echo "[3/6] Creating Unix socket directory..."
mkdir -p /var/run/hxg
chown root:admin /var/run/hxg 2>/dev/null || chown root:staff /var/run/hxg
chmod 770 /var/run/hxg
echo "  ✓ Socket directory: /var/run/hxg"

# ── 4. Initialize database ────────────────────────────────────────────────────
echo ""
echo "[4/6] Initializing database..."
PYTHONPATH="$BACKEND_DIR" sudo -u "$ACTUAL_USER" \
    /usr/bin/python3 -c "
import sys; sys.path.insert(0, '$BACKEND_DIR')
from core.database import init_db
init_db()
print('  Database initialized at: $DATA_DIR/hxguardian.db')
"

# ── 5. LaunchDaemon (runner — root) ───────────────────────────────────────────
echo ""
echo "[5/6] Installing LaunchDaemon (privileged runner)..."
RUNNER_PLIST="/Library/LaunchDaemons/com.hxguardian.runner.plist"
cp "$APP_DIR/launchd/com.hxguardian.runner.plist" "$RUNNER_PLIST"
chown root:wheel "$RUNNER_PLIST"
chmod 644 "$RUNNER_PLIST"

# Replace ACTUAL_USER placeholder in plist if present
if [[ -n "$ACTUAL_USER" ]]; then
    sed -i '' "s|/Users/admin/|/Users/$ACTUAL_USER/|g" "$RUNNER_PLIST"
fi

launchctl unload "$RUNNER_PLIST" 2>/dev/null || true
launchctl load -w "$RUNNER_PLIST"
echo "  ✓ LaunchDaemon loaded: com.hxguardian.runner"

# ── 6. LaunchAgent (server — user) ───────────────────────────────────────────
echo ""
echo "[6/6] Installing LaunchAgent (web server)..."
AGENT_PLIST="/Library/LaunchAgents/com.hxguardian.server.plist"
cp "$APP_DIR/launchd/com.hxguardian.server.plist" "$AGENT_PLIST"
chown root:wheel "$AGENT_PLIST"
chmod 644 "$AGENT_PLIST"

# Replace user paths
if [[ -n "$ACTUAL_USER" ]]; then
    sed -i '' "s|/Users/admin/|/Users/$ACTUAL_USER/|g" "$AGENT_PLIST"
fi

launchctl unload "$AGENT_PLIST" 2>/dev/null || true
sudo -u "$ACTUAL_USER" launchctl load -w "$AGENT_PLIST" 2>/dev/null || launchctl load -w "$AGENT_PLIST"
echo "  ✓ LaunchAgent loaded: com.hxguardian.server"

# ── Done ──────────────────────────────────────────────────────────────────────
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo " Installation complete!"
echo ""
echo " Dashboard will be available at:"
echo "   http://127.0.0.1:8000"
echo ""
echo " Session token is printed in the server log:"
echo "   tail -f /Library/Logs/hxguardian-server.log"
echo ""
echo " To stop services:"
echo "   sudo launchctl unload /Library/LaunchDaemons/com.hxguardian.runner.plist"
echo "   launchctl unload /Library/LaunchAgents/com.hxguardian.server.plist"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
