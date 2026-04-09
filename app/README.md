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
| Internet access | Required **only during setup** | For pip install |

> **Airgap note:** Internet is only needed once during setup to install Python dependencies. See [Offline Installation](#offline-installation-airgap) to pre-bundle dependencies before the device is isolated.

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
1. Installs Python dependencies (fastapi, uvicorn, sqlalchemy, apscheduler, etc.)
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

For devices that have no internet access, pre-bundle the Python dependencies on an internet-connected Mac **before** the device is isolated.

### On an internet-connected Mac (same macOS version and architecture):

```bash
cd hx-guardian/app/backend

# Download all wheels into vendor/python/
pip3 download -r requirements.txt -d vendor/python/

# Build the frontend (requires Node.js and npm)
cd ../frontend
npm install
npm run build
# The dist/ folder is now ready — it is committed to the repo
```

Then copy the entire `hx-guardian/` directory to the airgap device (USB drive, etc.).

### On the airgap device:

```bash
sudo zsh app/install.sh
# The installer detects vendor/python/ and installs offline automatically
```

---

## Starting Manually (Development / Troubleshooting)

If you need to start the services manually without LaunchDaemon/LaunchAgent:

```bash
# Terminal 1 — privileged runner (must be root)
sudo python3 app/backend/hxg_runner.py

# Terminal 2 — web server
zsh app/start-dev.sh
```

The session token will be printed to Terminal 2 output.

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

---

## Dashboard Features

| Page | Description |
|---|---|
| **Dashboard** | Compliance score, per-category charts, device status strip, pre-flight readiness |
| **Rules** | All 266 rules with filtering by category / standard / status |
| **Rule Detail** | Scan now, apply fix, scan history, exemption management |
| **Scan History** | Compliance trend chart, past scan sessions, CSV export |
| **Device Status** | macOS version, SIP, FileVault, Gatekeeper, Secure Boot |
| **Connections** | Live USB devices, Bluetooth state, network interfaces, established TCP connections |
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

**Scan returns ERROR for all rules**
- The runner must be running as root. Check `hxguardian-runner.log`.
- Verify the socket exists: `ls -la /var/run/hxg/runner.sock`

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
