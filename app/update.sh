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
#   sudo zsh app/update.sh usbwatcher   # deploy + restart USB watcher only
#   sudo zsh app/update.sh shellwatcher # deploy + restart shell watcher only

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
    runner)       BINARIES=(hxg-runner) ;;
    server)       BINARIES=(hxg-server) ;;
    usbwatcher)   BINARIES=(hxg-usb-watcher) ;;
    shellwatcher) BINARIES=(hxg-shell-watcher) ;;
    all)          BINARIES=(hxg-server hxg-runner hxg-usb-watcher hxg-shell-watcher) ;;
    *)
        echo "ERROR: Unknown target '$TARGET'. Use: all | runner | server | usbwatcher | shellwatcher"
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

refresh_runner_plist() {
    # Refresh the runner plist if the bundled version differs from the
    # deployed one. This is what carries the launchd `Sockets` key (socket
    # activation), so an existing airgap that only ran update.sh before this
    # change won't have it yet. Deploying the plist here avoids forcing the
    # operator to re-run the full install.sh just to pick up a plist change.
    #
    # Returns 0 if the plist was changed (caller must bootout/bootstrap to
    # re-parse it; kickstart -k won't pick up new launchd keys), 1 otherwise.
    local SRC="$APP_DIR/launchd/com.hxguardian.runner.plist"
    local DST="/Library/LaunchDaemons/com.hxguardian.runner.plist"

    if [[ ! -f "$SRC" ]]; then
        return 1
    fi
    if [[ -f "$DST" ]] && /usr/bin/cmp -s "$SRC" "$DST"; then
        return 1
    fi

    # Snapshot for rollback — mirrors the M3 pattern in install.sh. The
    # `.bak.<timestamp>` filename has no .plist extension so launchd won't
    # try to load it at boot.
    if [[ -f "$DST" ]]; then
        cp -p "$DST" "$DST.bak.$(date +%s)" 2>/dev/null || true
    fi
    cp -X "$SRC" "$DST"
    xattr -c "$DST" 2>/dev/null || true
    chown root:wheel "$DST"
    chmod 644 "$DST"
    echo "  ✓ Runner plist refreshed (backup at $DST.bak.*)"
    return 0
}

restart_runner() {
    # If the plist changed (e.g. socket activation just got rolled out), we
    # MUST bootout + bootstrap so launchd re-parses the new `Sockets` keys.
    # kickstart -k uses the previously-parsed plist and would silently keep
    # running the old behavior. When the plist is unchanged, kickstart -k is
    # the fast path (no socket flap).
    if refresh_runner_plist; then
        launchctl bootout system /Library/LaunchDaemons/com.hxguardian.runner.plist 2>/dev/null || true
        launchctl bootstrap system /Library/LaunchDaemons/com.hxguardian.runner.plist
    else
        launchctl kickstart -k system/com.hxguardian.runner 2>/dev/null \
            || { launchctl bootout system /Library/LaunchDaemons/com.hxguardian.runner.plist 2>/dev/null || true
                 launchctl bootstrap system /Library/LaunchDaemons/com.hxguardian.runner.plist; }
    fi
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

restart_shellwatcher() {
    launchctl kickstart -k system/com.hxguardian.shellwatcher 2>/dev/null \
        || { launchctl unload /Library/LaunchDaemons/com.hxguardian.shellwatcher.plist 2>/dev/null || true
             launchctl load -w /Library/LaunchDaemons/com.hxguardian.shellwatcher.plist; }
    echo "  ✓ Shell Watcher restarted"
}

case "$TARGET" in
    runner)       restart_runner ;;
    server)       restart_server ;;
    usbwatcher)   restart_usbwatcher ;;
    shellwatcher) restart_shellwatcher ;;
    all)
        restart_runner
        restart_server
        restart_usbwatcher
        restart_shellwatcher
        ;;
esac

# ── Post-deploy verification ─────────────────────────────────────────────────
# Catches a broken deploy at deploy-time instead of letting the operator find
# the dashboard wedged later. Skipped for watcher-only targets since the
# server endpoints don't reflect their state.
if [[ "$TARGET" == "all" || "$TARGET" == "server" || "$TARGET" == "runner" ]]; then
    echo ""
    echo "[verify] Probing /api/health and /api/runner/status..."

    health_ok=0
    for _ in {1..15}; do
        resp=$(/usr/bin/curl -sf --max-time 2 http://127.0.0.1:8000/api/health 2>/dev/null || echo '')
        if echo "$resp" | /usr/bin/grep -q '"ready":[[:space:]]*true'; then
            health_ok=1
            break
        fi
        sleep 2
    done
    if (( health_ok )); then
        echo "  ✓ Server ready"
    else
        echo "  ✗ Server not ready after 30s — see /api/internal/startup"
        /usr/bin/curl -sf --max-time 3 http://127.0.0.1:8000/api/internal/startup 2>/dev/null | sed 's/^/      /'
        exit 1
    fi

    runner_ok=0
    for _ in {1..10}; do
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
        echo "  ✗ Runner not reachable — check /Library/Logs/hxguardian-runner-error.log"
        if [[ -f /Library/Logs/hxguardian-runner-error.log ]]; then
            /usr/bin/tail -n 20 /Library/Logs/hxguardian-runner-error.log | sed 's/^/      /'
        fi
        exit 1
    fi
fi

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo " Update complete!"
echo ""
echo " Logs:"
echo "   tail -f /Library/Logs/hxguardian-runner.log"
echo "   tail -f /Library/Logs/hxguardian-server-error.log"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
