#!/bin/zsh
# HX-Guardian — Start all services
# Run: sudo zsh app/start.sh

set -euo pipefail

SCRIPT_DIR="${0:A:h}"

# ── Always start from a clean slate ──────────────────────────────────────────
# stop.sh unloads all daemons, kills any orphaned hxg-* processes (e.g. a
# foreground `sudo hxg-server` left open in a terminal), and removes the stale
# Unix socket. Running it first guarantees we never stack a second copy on top
# of an already-running one — the #1 cause of "Address already in use" errors.
if [[ -f "$SCRIPT_DIR/stop.sh" ]]; then
    zsh "$SCRIPT_DIR/stop.sh" >/dev/null 2>&1 || true
fi

echo "Starting HX-Guardian services..."

# Runner (LaunchDaemon — root)
RUNNER_PLIST="/Library/LaunchDaemons/com.hxguardian.runner.plist"
if [[ -f "$RUNNER_PLIST" ]]; then
    launchctl bootstrap system "$RUNNER_PLIST"
    echo "  ✓ Runner started"
else
    echo "  ✗ Runner plist not found — run install.sh first"
fi

# Server (LaunchDaemon — runs as admin user at boot, accessible to any user)
DAEMON_PLIST="/Library/LaunchDaemons/com.hxguardian.server.plist"
if [[ -f "$DAEMON_PLIST" ]]; then
    # Preflight: refuse to start if port 8000 is already held. Without this,
    # launchctl bootstraps the daemon, it fails with EADDRINUSE, and KeepAlive
    # flaps it — hiding the real offender behind a crash loop.
    if /usr/sbin/lsof -nP -iTCP:8000 -sTCP:LISTEN >/dev/null 2>&1; then
        echo "  ✗ Port 8000 is already in use:"
        /usr/sbin/lsof -nP -iTCP:8000 -sTCP:LISTEN | sed 's/^/      /'
        echo "  Refusing to start the server — stop the offending process first."
        exit 1
    fi
    launchctl bootstrap system "$DAEMON_PLIST"
    echo "  ✓ Server started"
else
    echo "  ✗ Server plist not found — run install.sh first"
fi

# USB Watcher (LaunchDaemon — root)
USB_PLIST="/Library/LaunchDaemons/com.hxguardian.usbwatcher.plist"
if [[ -f "$USB_PLIST" ]]; then
    launchctl bootstrap system "$USB_PLIST"
    echo "  ✓ USB Watcher started"
else
    echo "  ✗ USB Watcher plist not found — run install.sh first"
fi

# Shell Watcher (LaunchDaemon — root)
SHELL_PLIST="/Library/LaunchDaemons/com.hxguardian.shellwatcher.plist"
if [[ -f "$SHELL_PLIST" ]]; then
    launchctl bootstrap system "$SHELL_PLIST"
    echo "  ✓ Shell Watcher started"
else
    echo "  ✗ Shell Watcher plist not found — run install.sh first"
fi

echo ""
sleep 2

# ── Post-start sanity: flag duplicates early ─────────────────────────────────
# Expected: exactly one process per binary. More than one means a stray plist
# under /Library/LaunchAgents/ or a manual foreground run that escaped stop.sh.
for bin in hxg-runner hxg-server hxg-usb-watcher hxg-shell-watcher; do
    # pgrep -x matches the exact process name, so the run-hxg-* zsh wrapper
    # (whose cmdline contains the binary name) is not counted — only real
    # duplicate instances of the binary trigger this warning.
    n=$(/usr/bin/pgrep -x "$bin" | /usr/bin/wc -l | /usr/bin/tr -d ' ' || true)
    if (( n > 1 )); then
        echo "  ⚠ $n copies of $bin running — check /Library/LaunchAgents/ and /Library/LaunchDaemons/ for stray plists"
    fi
done

# Poll the health endpoint for up to ~20s before giving up. A slow first-boot
# DB migration or manifest load can easily take >2s; a hard crash loop will
# never recover, and we tail the error log so the cause is visible on-screen.
health_ok=0
for _ in {1..10}; do
    if /usr/bin/curl -sf -o /dev/null --max-time 2 http://127.0.0.1:8000/api/health; then
        health_ok=1
        break
    fi
    sleep 2
done
if (( health_ok )); then
    echo "  ✓ Server responding on http://127.0.0.1:8000"
else
    echo "  ✗ Server did not respond within 20s — recent error log:"
    if [[ -f /Library/Logs/hxguardian-server-error.log ]]; then
        /usr/bin/tail -n 30 /Library/Logs/hxguardian-server-error.log | sed 's/^/      /'
    else
        echo "      (log file /Library/Logs/hxguardian-server-error.log does not exist yet)"
    fi
    echo "  Follow live: tail -f /Library/Logs/hxguardian-server-error.log"
fi
echo ""
echo "Dashboard: http://127.0.0.1:8000"
