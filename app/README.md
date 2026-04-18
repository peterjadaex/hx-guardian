# HX-Guardian Security Dashboard

A localhost web application for monitoring and enforcing macOS security compliance standards on an airgap signing device. Supports NIST 800-53r5 High, CIS Controls v8, and CIS Level 2 baselines across 266 security rules.

---

## Prerequisites

Before installing, verify the following on the target Mac:

| Requirement | Version | Check |
|---|---|---|
| macOS | 13 Ventura or later | `sw_vers` |
| Python | 3.9 or later (system Python is fine) | `python3 --version` |
| Xcode Command Line Tools | Any | `xcode-select -p` |
| Admin account | Required | Must be in the `admin` group |
| Internet access | Required **only during bundle prep** | See [Offline Installation](#offline-installation-airgap) |

> **Airgap note:** Internet is only needed once, on a separate connected Mac, to run `prepare_sd_card.sh`. The target device never needs network access. See [Offline Installation](#offline-installation-airgap).

---

## Directory Structure

```
hx-guardian/
├── standards/                  ← Security rule scripts (existing, do not modify)
│   ├── scripts/
│   │   ├── manifest.json       ← Rule index (266 rules)
│   │   ├── scan/               ← 214 scan scripts
│   │   └── fix/                ← 86 fix scripts
│   ├── 800-53r5_high/
│   ├── cisv8/
│   └── cis_lvl2/
└── app/                        ← Dashboard application
    ├── backend/                ← FastAPI Python backend
    │   ├── main.py             ← Web server entry point
    │   ├── hxg_runner.py       ← Privileged script runner (runs as root)
    │   ├── requirements.txt    ← Python dependencies
    │   ├── core/               ← Database, auth, manifest, scheduler
    │   └── routers/            ← API route handlers
    ├── frontend/
    │   └── dist/               ← Pre-built React UI (served by backend)
    ├── data/                   ← Created on install; holds DB + reports
    ├── launchd/                ← LaunchDaemon and LaunchAgent plists
    ├── install.sh              ← Production installer
    └── start-dev.sh            ← Development start script
```

---

## Installation (Internet-Connected Device)

### Step 1 — Clone or copy the repository

```bash
# Place the repo at a permanent location — the launchd services reference this path
git clone <repo-url> /Users/<username>/Documents/airgap/hx-guardian
cd /Users/<username>/Documents/airgap/hx-guardian
```

> If you change the repo location, update the paths in `app/launchd/*.plist` before running `install.sh`.

### Step 2 — Run the installer

```bash
sudo zsh app/install.sh
```

The installer performs these steps automatically:
0. Checks for Python 3 — if absent, installs from `vendor/installers/python-*.pkg` (offline)
1. Installs Python dependencies — from `vendor/python/` wheels if present (offline), else PyPI
2. Creates `app/data/` directory with correct permissions
3. Creates the Unix socket directory at `/var/run/hxg/`
4. Initialises the SQLite database at `app/data/hxguardian.db`
5. Installs and loads the **LaunchDaemon** (`com.hxguardian.runner`) — runs as root, executes scan/fix scripts
6. Installs and loads the **LaunchAgent** (`com.hxguardian.server`) — runs as your user, serves the web dashboard

### Step 3 — Get the session token

The web server generates a random session token on each startup. Retrieve it from the log:

```bash
grep -A1 "session token" /Library/Logs/hxguardian-server.log
```

### Step 4 — Open the dashboard

Open Safari and go to:

```
http://127.0.0.1:8000
```

Paste the session token from Step 3 and click **Access Dashboard**.

---

## Offline Installation (Airgap)

For devices with no internet access, use `prepare_sd_card.sh` to download all runtime
dependencies on a connected Mac, transfer via SD card, then install fully offline.

### Step 1 — On an internet-connected Mac: build the bundle

```bash
cd hx-guardian

# Downloads Python wheels + Python installer .pkg into vendor/
zsh app/prepare_sd_card.sh

# Optional: also download Node.js installers (only needed to rebuild the frontend)
zsh app/prepare_sd_card.sh --with-node
```

The script populates:
- `app/backend/vendor/python/` — all Python wheels for offline `pip install`
- `app/backend/vendor/installers/python-*.pkg` — Python 3 universal installer (used if Python
  is not yet present on the target device)

It prints a checklist at the end confirming every artifact is present.

> **Frontend:** `frontend/dist/` is pre-built and committed — Node.js is not required on the
> airgap device unless you intend to rebuild the UI from source there.

### Step 2 — Copy to SD card

```bash
cp -R hx-guardian /Volumes/<SD_CARD_NAME>/hx-guardian
```

### Step 3 — On the airgap device: install from SD card

```bash
# Copy from SD card to the device
cp -R /Volumes/<SD_CARD_NAME>/hx-guardian ~/Documents/airgap/hx-guardian
cd ~/Documents/airgap/hx-guardian

# Install (fully offline)
sudo zsh app/install.sh
```

`install.sh` detects `vendor/python/` and installs wheels with `--no-index`. If Python 3 is
absent, it silently runs the bundled `.pkg` before proceeding. No internet connection is needed
at any point on the target device.

---

## Starting Manually (Development / Troubleshooting)

If you need to start the services manually without LaunchDaemon/LaunchAgent:

```bash
# Terminal 1 — privileged runner (must be root)
# Run from the repo root; the runner resolves manifest and script paths relative to it
sudo python3 app/backend/hxg_runner.py

# Terminal 2 — web server (with hot-reload)
zsh app/start-dev.sh
```

The session token is printed to **Terminal 2 stdout** at startup:
```
INFO  ============================================================
INFO  Dashboard session token (copy this):
INFO    a3f8c2d1...
INFO  Open: http://127.0.0.1:8000
INFO  ============================================================
```

When running via LaunchAgent, retrieve it from the log file instead:
```bash
grep -A1 "session token" /Library/Logs/hxguardian-server.log
```

The token changes on every restart — re-copy it each time the server is restarted.

---

## USB Watcher Daemon

The USB watcher enforces the device whitelist at the OS layer — ejecting unauthorized storage
volumes and firing audit log entries independently of the dashboard.

**Prerequisite:** Grant your terminal **Full Disk Access** in
`System Settings → Privacy & Security → Full Disk Access` before running the watcher as root.
Without it, `sudo python3` cannot open files under `/Users/` and fails with `[Errno 1]`.

**Install (survives reboots):**
```bash
sudo zsh standards/scripts/setup/install_usb_watcher.sh
```

**Start / stop after install:**
```bash
sudo launchctl unload /Library/LaunchDaemons/com.hxguardian.usbwatcher.plist   # stop
sudo launchctl load   /Library/LaunchDaemons/com.hxguardian.usbwatcher.plist   # start
launchctl list com.hxguardian.usbwatcher                                        # status
tail -f /var/log/hxguardian_usb.log                                             # live log
```

**Run manually for testing (no install required):**
```bash
sudo touch /var/log/hxguardian_usb.log && sudo chmod 644 /var/log/hxguardian_usb.log
sudo sh -c 'python3 /path/to/app/backend/usb_watcher.py >> /var/log/hxguardian_usb.log 2>&1' &
sudo kill $(pgrep -f usb_watcher.py)   # stop
```

The daemon re-reads the whitelist every 30 seconds. Changes made via the Connections page
take effect within one poll cycle — no restart needed. When a storage volume (SD card, USB
drive) is ejected and reinserted into the same reader, the daemon detects the new BSD disk
name and ejects it again automatically.

---

## Service Management

```bash
# Check service status
sudo launchctl list | grep hxguardian

# View server logs (includes session token on startup)
tail -f /Library/Logs/hxguardian-server.log

# View runner logs
tail -f /Library/Logs/hxguardian-runner.log

# Restart server (e.g. after a code update)
launchctl kickstart -k gui/$(id -u)/com.hxguardian.server

# Restart runner
sudo launchctl kickstart -k system/com.hxguardian.runner

# Stop all services
sudo launchctl unload /Library/LaunchDaemons/com.hxguardian.runner.plist
launchctl unload /Library/LaunchAgents/com.hxguardian.server.plist

# Start all services
sudo launchctl load -w /Library/LaunchDaemons/com.hxguardian.runner.plist
launchctl load -w /Library/LaunchAgents/com.hxguardian.server.plist
```

---

## Uninstallation

```bash
# Stop and remove services
sudo launchctl unload /Library/LaunchDaemons/com.hxguardian.runner.plist
launchctl unload /Library/LaunchAgents/com.hxguardian.server.plist
sudo rm /Library/LaunchDaemons/com.hxguardian.runner.plist
sudo rm /Library/LaunchAgents/com.hxguardian.server.plist

# Remove socket directory
sudo rm -rf /var/run/hxg

# Optionally remove data (scan history, audit log)
rm -rf app/data/
```

---

## Architecture Overview

```
Browser (Safari)
    │ http://127.0.0.1:8000
    ▼
hxg_server (FastAPI)          ← Runs as admin user via LaunchAgent
    │ Unix socket /var/run/hxg/runner.sock
    ▼
hxg_runner (Python daemon)    ← Runs as root via LaunchDaemon
    │ subprocess [zsh, --no-rcs, script_path]
    ▼
scan/fix scripts              ← standards/scripts/scan/*.sh
                                 standards/scripts/fix/*.sh
```

**Security properties:**
- The web server never runs as root and has no sudo capability
- The runner only executes scripts whose names appear in `manifest.json` — no arbitrary commands
- The dashboard binds to `127.0.0.1` only — never accessible from the network
- Every operator action (scan, fix, exemption, report) is written to the audit log

**Scan streaming:**
The runner streams each script result back to the server as it completes, rather than
waiting for the entire batch to finish. This means the UI can display results as they arrive
and avoids socket timeouts on large scans (266 rules). The frontend polls the session status
every 2 seconds and reloads the rule list automatically when the scan is done.

---

## Dashboard Features

| Page | Description |
|---|---|
| **Dashboard** | Compliance score, per-category charts, device status strip, pre-flight readiness |
| **Rules** | All 266 rules with filtering by category / standard / status |
| **Rule Detail** | Scan now, apply fix, scan history, exemption management |
| **Scan History** | Compliance trend chart, past scan sessions, CSV export |
| **Device Status** | macOS version, SIP, FileVault, Gatekeeper, Secure Boot |
| **Connections** | Live USB devices and storage volumes with whitelist management, Bluetooth state, network interfaces, established TCP connections |
| **Device Logs** | System log viewer with live streaming and keyword filter |
| **MDM Profiles** | Maps 52 MDM-only rules to mobileconfig profiles; check install status; download profiles |
| **Exemptions** | Grant / revoke rule exemptions with reason and expiry date |
| **Schedule** | Configure automatic recurring scans (cron-based) |
| **Reports** | Generate printable HTML compliance report or CSV export |
| **Audit Log** | Append-only log of all operator actions |

---

## Troubleshooting

**Dashboard not loading**
```bash
# Check the server is running
curl -s http://127.0.0.1:8000/api/health
# Should return: {"status":"ok","runner_connected":...}
```

**`runner_connected: false` in health check**
```bash
# Check the runner daemon is running
sudo launchctl list | grep hxguardian.runner
# If not listed, reload it:
sudo launchctl load -w /Library/LaunchDaemons/com.hxguardian.runner.plist
```

When running manually, ensure Terminal 1 (`sudo python3 app/backend/hxg_runner.py`) is still
open and shows `hxg_runner listening on /var/run/hxg/runner.sock`. Restarting the backend
(Terminal 2) does not restart the runner.

**Scan returns ERROR for all rules**
- The runner must be running as root. Check `hxguardian-runner.log` or Terminal 1.
- Verify the socket exists: `ls -la /var/run/hxg/runner.sock`
- The scan button on Rule Detail shows the full server error — check that output for details.

**Scan results not updating after "Scan All" or "Run Full Scan"**
- The frontend polls the session status and reloads automatically when the scan finishes.
  If results still look stale, wait for the "Scanning…" button to return to normal, then
  check the Rules page — it reloads on completion.
- If results never update, check that the runner is connected (`/api/health`). A disconnected
  runner means scan sessions finish instantly with zero results.

**MDM rules still showing `MDM_REQUIRED` after deploying a profile**
MDM-only rules (those with no scan script) are verified solely by whether the relevant
configuration profile is installed. Deploying the profile does not automatically update
past scan results — run a new full scan after deploying the profile to record the
current state. Rules with scan scripts that check MDM-managed preferences (e.g.
`com.apple.applicationaccess` keys) will pick up the new values on the next scan.

**USB watcher: `[Errno 1] Operation not permitted` when opening the script**

macOS TCC blocks `sudo python3` from reading files under `/Users/` unless the terminal has
Full Disk Access. Fix:
1. `System Settings → Privacy & Security → Full Disk Access`
2. Add Terminal.app (or iTerm2), toggle on, quit and reopen the terminal

**USB watcher: device detected but not ejected / not re-ejected after replug**

Check the live log: `tail -f /var/log/hxguardian_usb.log`
- `Could not eject` in the log → `diskutil eject` failed; ensure Full Disk Access is granted
- No log entry at all → watcher is not running; check `launchctl list com.hxguardian.usbwatcher`
- Ejected once but not again → update to latest `usb_watcher.py` (re-eject-on-replug fix)
- Device shows Whitelisted in Connections → remove the whitelist entry to re-enable enforcement

**`ModuleNotFoundError` on startup**
```bash
# Reinstall Python dependencies
pip3 install -r app/backend/requirements.txt
```

**Permission denied on socket**
```bash
# Recreate the socket directory with correct permissions
sudo rm -rf /var/run/hxg
sudo mkdir -p /var/run/hxg
sudo chown root:admin /var/run/hxg
sudo chmod 770 /var/run/hxg
# Then restart the runner
sudo launchctl kickstart -k system/com.hxguardian.runner
```
