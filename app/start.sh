#!/bin/zsh
# HX-Guardian — Start all services
# Run: sudo zsh app/start.sh

set -euo pipefail

echo "Starting HX-Guardian services..."

# Runner (LaunchDaemon — root)
RUNNER_PLIST="/Library/LaunchDaemons/com.hxguardian.runner.plist"
if [[ -f "$RUNNER_PLIST" ]]; then
    launchctl bootout system "$RUNNER_PLIST" 2>/dev/null || true
    launchctl bootstrap system "$RUNNER_PLIST"
    echo "  ✓ Runner started"
else
    echo "  ✗ Runner plist not found — run install.sh first"
fi

# Server (LaunchDaemon — runs as admin user at boot, accessible to any user)
DAEMON_PLIST="/Library/LaunchDaemons/com.hxguardian.server.plist"
if [[ -f "$DAEMON_PLIST" ]]; then
    launchctl bootout system "$DAEMON_PLIST" 2>/dev/null || true
    launchctl bootstrap system "$DAEMON_PLIST"
    echo "  ✓ Server started"
else
    echo "  ✗ Server plist not found — run install.sh first"
fi

# USB Watcher (LaunchDaemon — root)
USB_PLIST="/Library/LaunchDaemons/com.hxguardian.usbwatcher.plist"
if [[ -f "$USB_PLIST" ]]; then
    launchctl bootout system "$USB_PLIST" 2>/dev/null || true
    launchctl bootstrap system "$USB_PLIST"
    echo "  ✓ USB Watcher started"
else
    echo "  ✗ USB Watcher plist not found — run install.sh first"
fi

# Shell Watcher (LaunchDaemon — root)
SHELL_PLIST="/Library/LaunchDaemons/com.hxguardian.shellwatcher.plist"
if [[ -f "$SHELL_PLIST" ]]; then
    launchctl bootout system "$SHELL_PLIST" 2>/dev/null || true
    launchctl bootstrap system "$SHELL_PLIST"
    echo "  ✓ Shell Watcher started"
else
    echo "  ✗ Shell Watcher plist not found — run install.sh first"
fi

# Print session token
echo ""
sleep 2
TOKEN_LINE=$(grep "session token" /Library/Logs/hxguardian-server-error.log 2>/dev/null | tail -1)
if [[ -n "$TOKEN_LINE" ]]; then
    echo "$TOKEN_LINE"
else
    echo "Token not yet available — check: tail -f /Library/Logs/hxguardian-server-error.log"
fi
echo ""
echo "Dashboard: http://127.0.0.1:8000"
