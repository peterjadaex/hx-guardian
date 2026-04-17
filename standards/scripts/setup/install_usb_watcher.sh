#!/usr/bin/env zsh
# install_usb_watcher.sh — install the HX Guardian USB enforcement daemon
#
# Must be run as root:
#   sudo zsh standards/scripts/setup/install_usb_watcher.sh
#
# What this does:
#   1. Resolves the absolute path to usb_watcher.py in this repo
#   2. Writes a LaunchDaemon plist to /Library/LaunchDaemons/
#   3. Loads (or reloads) the daemon so it starts immediately

set -euo pipefail

if [[ $EUID -ne 0 ]]; then
  echo "ERROR: Run this script as root: sudo zsh $0"
  exit 1
fi

# ── Paths ──────────────────────────────────────────────────────────────────────

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
WATCHER_SCRIPT="$REPO_ROOT/app/backend/usb_watcher.py"
PLIST_SRC="$REPO_ROOT/standards/launchd/com.hxguardian.usbwatcher.plist"
PLIST_DST="/Library/LaunchDaemons/com.hxguardian.usbwatcher.plist"
LABEL="com.hxguardian.usbwatcher"
LOG_FILE="/var/log/hxguardian_usb.log"

# ── Validate ───────────────────────────────────────────────────────────────────

if [[ ! -f "$WATCHER_SCRIPT" ]]; then
  echo "ERROR: Watcher script not found at $WATCHER_SCRIPT"
  exit 1
fi

if [[ ! -f "$PLIST_SRC" ]]; then
  echo "ERROR: Plist template not found at $PLIST_SRC"
  exit 1
fi

echo "Installing HX Guardian USB Watcher"
echo "  Repo root:      $REPO_ROOT"
echo "  Watcher script: $WATCHER_SCRIPT"
echo "  Daemon plist:   $PLIST_DST"
echo "  Log file:       $LOG_FILE"

# ── Write plist ────────────────────────────────────────────────────────────────

sed "s|__WATCHER_SCRIPT__|$WATCHER_SCRIPT|g" "$PLIST_SRC" > "$PLIST_DST"
chown root:wheel "$PLIST_DST"
chmod 644 "$PLIST_DST"

# Ensure log file exists and is writable
touch "$LOG_FILE"
chmod 644 "$LOG_FILE"

# ── Load daemon ────────────────────────────────────────────────────────────────

# Unload existing instance if already loaded (ignore errors)
launchctl unload "$PLIST_DST" 2>/dev/null || true

launchctl load "$PLIST_DST"

# Verify it loaded
if launchctl list | grep -q "$LABEL"; then
  echo ""
  echo "✓ USB Watcher daemon loaded successfully"
  echo "  Status: launchctl list $LABEL"
  launchctl list "$LABEL" 2>/dev/null || true
  echo ""
  echo "  Live log: tail -f $LOG_FILE"
else
  echo "ERROR: Daemon did not load. Check $LOG_FILE for details."
  exit 1
fi
