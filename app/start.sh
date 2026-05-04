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

# Poll the health endpoint for up to ~20s before giving up. With the new
# non-blocking lifespan, /api/health responds in <100ms regardless of DB
# state, so failure here means the server crashed at import time.
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
    exit 1
fi

# Wait for background startup to finish (init_db, scheduler) — surfaces as
# /api/health -> {"ready": true}. Bounded at 30s; longer means a DB problem.
ready_ok=0
for _ in {1..15}; do
    resp=$(/usr/bin/curl -sf --max-time 2 http://127.0.0.1:8000/api/health 2>/dev/null || echo '')
    if echo "$resp" | /usr/bin/grep -q '"ready":[[:space:]]*true'; then
        ready_ok=1
        break
    fi
    sleep 2
done
if (( ready_ok )); then
    echo "  ✓ Background startup complete (DB ready)"
else
    echo "  ✗ Server did not finish background startup within 30s"
    echo "    Check: curl http://127.0.0.1:8000/api/internal/startup"
    /usr/bin/curl -sf --max-time 3 http://127.0.0.1:8000/api/internal/startup 2>/dev/null | sed 's/^/      /'
    exit 1
fi

# Verify the runner is reachable through the privilege-boundary socket.
# Failing here loudly is much better than the operator finding the dashboard
# wedged later.
runner_ok=0
for _ in {1..15}; do
    resp=$(/usr/bin/curl -sf --max-time 2 http://127.0.0.1:8000/api/runner/status 2>/dev/null || echo '')
    if echo "$resp" | /usr/bin/grep -q '"runner_connected":[[:space:]]*true'; then
        runner_ok=1
        break
    fi
    sleep 2
done
if (( runner_ok )); then
    echo "  ✓ Runner reachable through Unix socket"
else
    echo "  ✗ Runner not reachable through /var/run/hxg/runner.sock after 30s"
    echo "    See: /Library/Logs/hxguardian-runner-error.log"
    if [[ -f /Library/Logs/hxguardian-runner-error.log ]]; then
        /usr/bin/tail -n 20 /Library/Logs/hxguardian-runner-error.log | sed 's/^/      /'
    fi
    exit 1
fi

echo ""
echo "Dashboard: http://127.0.0.1:8000"
