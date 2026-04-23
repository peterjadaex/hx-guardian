#!/bin/zsh
# HX-Guardian — Stop all services
# Run: sudo zsh app/stop.sh

set -euo pipefail

echo "Stopping HX-Guardian services..."

# Unload launchd services
launchctl bootout system /Library/LaunchDaemons/com.hxguardian.server.plist        2>/dev/null || true
launchctl bootout system /Library/LaunchDaemons/com.hxguardian.runner.plist        2>/dev/null || true
launchctl bootout system /Library/LaunchDaemons/com.hxguardian.usbwatcher.plist    2>/dev/null || true
launchctl bootout system /Library/LaunchDaemons/com.hxguardian.shellwatcher.plist  2>/dev/null || true

# Kill any lingering processes
pkill -f 'hxg-server'        2>/dev/null || true
pkill -f 'hxg-runner'        2>/dev/null || true
pkill -f 'hxg-usb-watcher'   2>/dev/null || true
pkill -f 'hxg-shell-watcher' 2>/dev/null || true
sleep 1
pkill -9 -f 'hxg-server'        2>/dev/null || true
pkill -9 -f 'hxg-runner'        2>/dev/null || true
pkill -9 -f 'hxg-usb-watcher'   2>/dev/null || true
pkill -9 -f 'hxg-shell-watcher' 2>/dev/null || true

# Clean stale socket
rm -f /var/run/hxg/runner.sock

echo "  ✓ All services stopped"
