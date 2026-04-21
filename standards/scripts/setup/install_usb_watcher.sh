#!/usr/bin/env zsh
# install_usb_watcher.sh — install the HX Guardian USB enforcement daemon
#
# Must be run as root:
#   sudo zsh standards/scripts/setup/install_usb_watcher.sh
#
# Requires the hxg-usb-watcher binary to be deployed at:
#   /Library/Application Support/hxguardian/bin/hxg-usb-watcher
# (done automatically by app/install.sh)

set -euo pipefail

if [[ $EUID -ne 0 ]]; then
  echo "ERROR: Run this script as root: sudo zsh $0"
  exit 1
fi

# ── Paths ──────────────────────────────────────────────────────────────────────

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
PLIST_SRC="$REPO_ROOT/standards/launchd/com.hxguardian.usbwatcher.plist"
PLIST_DST="/Library/LaunchDaemons/com.hxguardian.usbwatcher.plist"
BINARY="/Library/Application Support/hxguardian/bin/hxg-usb-watcher"
LABEL="com.hxguardian.usbwatcher"
LOG_FILE="/var/log/hxguardian_usb.log"

# ── Validate ───────────────────────────────────────────────────────────────────

if [[ ! -f "$BINARY" ]]; then
  echo "ERROR: Binary not found at $BINARY"
  echo "  Run app/install.sh first, or app/build.sh + app/install.sh"
  exit 1
fi

if [[ ! -f "$PLIST_SRC" ]]; then
  echo "ERROR: Plist not found at $PLIST_SRC"
  exit 1
fi

echo "Installing HX Guardian USB Watcher"
echo "  Binary:       $BINARY"
echo "  Daemon plist: $PLIST_DST"
echo "  Log file:     $LOG_FILE"

# ── Deploy plist ───────────────────────────────────────────────────────────────

cp "$PLIST_SRC" "$PLIST_DST"
chown root:wheel "$PLIST_DST"
chmod 644 "$PLIST_DST"

# Ensure log file exists and is writable
touch "$LOG_FILE"
chmod 644 "$LOG_FILE"

# ── Load daemon ────────────────────────────────────────────────────────────────

launchctl unload "$PLIST_DST" 2>/dev/null || true
launchctl load "$PLIST_DST"

if launchctl list | grep -q "$LABEL"; then
  echo ""
  echo "✓ USB Watcher daemon loaded successfully"
  launchctl list "$LABEL" 2>/dev/null || true
  echo ""
  echo "  Live log: tail -f $LOG_FILE"
else
  echo "ERROR: Daemon did not load. Check $LOG_FILE for details."
  exit 1
fi
