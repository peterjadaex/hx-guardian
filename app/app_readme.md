# HX-Guardian — Application Developer Guide

A localhost web application for monitoring and enforcing macOS security compliance
on an airgap signing device. Supports NIST 800-53r5 High, CIS Controls v8, and
CIS Level 2 baselines across 266 security rules.

> **Audience:** Application developers — people who build, modify, debug, or package
> the HX-Guardian dashboard for deployment to airgap devices. Operators and admins
> who install the app on an airgap device should read [airgap_readme.md](../standards/airgap_readme.md).

---

## 1. Prerequisites

This guide assumes an **internet-connected development Mac**. The airgap target
device has different prerequisites — see [airgap_readme.md](../standards/airgap_readme.md).

| Requirement | Version | Check | Install |
|---|---|---|---|
| macOS | 13 Ventura or later | `sw_vers` | — |
| Python | 3.12.10 (python.org build) | `python3.12 --version` | <https://www.python.org/downloads/release/python-31210/> (macOS 64-bit universal2 installer) |
| Xcode Command Line Tools | Any | `xcode-select -p` | `xcode-select --install` |
| Node.js | 18 LTS or later (only to rebuild the frontend) | `node --version` | <https://nodejs.org/en/download> (macOS installer) or `brew install node` |
| Admin account | Required | Must be in the `admin` group | — |
| Internet access | Required on the dev machine only | — | — |

> **Why python.org and not the Xcode CLT Python at `/usr/bin/python3`?** The CLT build is
> a restricted embedded distribution that does not work with PyInstaller (used by
> [app/build.sh](build.sh)). Install the python.org 3.12.10 universal2 package and the rest of
> this guide will work.

---

## 2. Application Overview

### 2.1 Architecture

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

### 2.2 Security properties

- The web server never runs as root and has no sudo capability.
- The runner only executes scripts whose names appear in `manifest.json` —
  no arbitrary commands.
- The dashboard binds to `127.0.0.1` only — never accessible from the network.
- Every operator action (scan, fix, exemption, report) is written to the audit log.

### 2.3 Scan streaming

The runner streams each script result back to the server as it completes rather
than waiting for the entire batch to finish. The UI can display results as they
arrive and avoids socket timeouts on large scans (266 rules). The frontend polls
the session status every 2 seconds and reloads the rule list automatically when
the scan is done.

### 2.4 Directory structure

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
    │   ├── usb_watcher.py      ← USB enforcement daemon
    │   ├── requirements.txt    ← Python dependencies
    │   ├── core/               ← Database, auth, manifest, scheduler
    │   └── routers/            ← API route handlers
    ├── frontend/
    │   ├── src/                ← React source (edit here)
    │   └── dist/               ← Pre-built React UI (served by backend)
    ├── data/                   ← Created on install; holds DB + reports
    ├── launchd/                ← LaunchDaemon and LaunchAgent plists
    ├── install.sh              ← Production installer (runs on target)
    ├── rules_setup.sh          ← Post-install bulk fix + exemption script
    ├── prepare_sd_card.sh      ← SD card bundle builder (runs on dev machine)
    └── start-dev.sh            ← Development start script
```

### 2.5 Dashboard features

| Page | Description |
|---|---|
| **Dashboard** | Compliance score, per-category charts, device status strip (SIP, FileVault, Gatekeeper, Firewall, Secure Boot), device information, pre-flight readiness |
| **Rules** | All 266 rules with filtering by category / standard / status |
| **Rule Detail** | Scan now, apply fix, scan history, exemption management |
| **Scan History** | Compliance trend chart, past scan sessions, CSV export, save as PDF |
| **Connections** | Live USB devices and storage volumes with whitelist management, Bluetooth state, network interfaces, established TCP connections |
| **Device Logs** | System log viewer with live streaming and keyword filter |
| **MDM Profiles** | Maps 52 MDM-only rules to mobileconfig profiles; check install status; download profiles |
| **Exemptions** | Grant / revoke rule exemptions with reason and expiry date |
| **Schedule** | Configure automatic recurring scans (cron-based) |
| **Reports** | Generate HTML compliance report, save as PDF, or CSV export |
| **Audit Log** | Append-only log of all operator actions |

---

## 3. Development Setup

### 3.1 Clone the repository

```bash
git clone <repo-url> ~/Documents/hx-guardian
cd ~/Documents/hx-guardian
```

### 3.2 Create a virtual environment and install Python dependencies

Use a project-local venv so the dev environment is isolated from system Python.

```bash
# From the repo root
python3.12 -m venv .venv
source .venv/bin/activate

pip install --upgrade pip
pip install -r app/backend/requirements.txt
```

Re-activate the venv (`source .venv/bin/activate`) in every new terminal that
runs the server or the runner. Deactivate with `deactivate` when done.

### 3.3 Start in development mode

Both terminals must have the venv activated. The runner runs as root, so pass the
venv's Python to `sudo` explicitly — `sudo python3` would otherwise use the system
Python and miss the installed packages.

```bash
# Terminal 1 — privileged runner (must be root, uses venv Python)
source .venv/bin/activate
sudo "$(which python3)" app/backend/hxg_runner.py

# Terminal 2 — web server (with hot-reload)
source .venv/bin/activate
zsh app/start-dev.sh
```

Expected runner output:

```
[runner] INFO Manifest loaded: 266 rules
[runner] INFO hxg_runner listening on /var/run/hxg/runner.sock (uid=0)
```

Expected server output:

```
INFO  Starting HX-Guardian dashboard...
INFO  Uvicorn running on http://127.0.0.1:8000
```

Open <http://127.0.0.1:8000> in Safari. The dashboard is open on localhost with
no login — sensitive actions (applying fixes, modifying exemptions, etc.) are
gated by a 2FA one-time password configured under **Settings**.

### 3.4 Rebuild the frontend

Only needed when you modify anything under [app/frontend/src/](frontend/src/).

```bash
cd app/frontend
npm install
npm run build
```

Restart the backend to serve the new build. The built artifacts go to
[app/frontend/dist/](frontend/dist/), which is committed to the repo so the
airgap device does not need Node.js at install time.

### 3.5 Health check

```bash
curl -s http://127.0.0.1:8000/api/health
# → {"status":"ok","ready":true,"version":"1.0.0"}

curl -s http://127.0.0.1:8000/api/runner/status
# → {"runner_connected":true,"available":true,"reason":null,"detail":"Runner is available.",
#    "uid":0,"manifest_rules":268,"server_manifest_rules":268,
#    "stale_manifest":false,"legacy":false,"checked_at":"..."}
```

`/api/health` covers only this server; runner state lives at
`/api/runner/status`. Two fields matter there and they are not the same thing:

- `runner_connected` — something answered on the socket. This is what
  `update.sh` checks during post-deploy verification.
- `available` — the runner can actually assess compliance. A runner can be
  connected yet unusable: `manifest_empty` (it loaded zero rules),
  `standards_missing`, or `not_root`. `reason` and `detail` say which, and
  `detail` includes the command to fix it.

If `available` is `false`, a scan will not attempt those rules; it records them
as **Not Assessed** rather than guessing. `stale_manifest` means the manifest
changed since the runner started — the runner reads it once at startup, so it
needs `sudo zsh app/update.sh runner` to pick up edits.

---

## 4. Preparing the Airgap SD Card Bundle

This is the **only online step** required to ship HX-Guardian to an airgap device.
The backend is compiled to standalone PyInstaller binaries (onedir) on the dev Mac,
so the airgap device never needs Python, pip, Node.js, or internet access.

### 4.1 Run the bundle script

```bash
cd ~/Documents/hx-guardian
source .venv/bin/activate        # PyInstaller runs from the venv
zsh app/prepare_sd_card.sh
```

The script runs [app/build.sh](build.sh) first (PyInstaller → ad-hoc codesign),
assembles and verifies the bundle in a temporary staging directory, then writes
`hxg-install.zip` at the repo root. The archive contains one top-level
`hxg-install/` directory:

| Path | Contents |
|---|---|
| `hxg-install/app/dist/hxg-server/` | FastAPI web server binary (onedir) |
| `hxg-install/app/dist/hxg-runner/` | Privileged script runner binary (onedir) |
| `hxg-install/app/dist/hxg-usb-watcher/` | USB enforcement daemon binary (onedir) |
| `hxg-install/app/install.sh` + `start/stop/restart/update.sh` | Management scripts |
| `hxg-install/app/rules_setup.sh` | Post-install bulk fix + exemption script |
| `hxg-install/app/launchd/com.hxguardian.runner.plist` | LaunchDaemon plist for the runner |
| `hxg-install/standards/launchd/com.hxguardian.usbwatcher.plist` | LaunchDaemon plist for the USB watcher |
| `hxg-install/standards/scripts/` | manifest.json, scan/, fix/ |
| `hxg-install/standards/<baseline>/mobileconfigs/unsigned/` | MDM profiles per baseline |
| `hxg-install/standards/unified/` | Merged unified MDM profile |
| `hxg-install/app/vendor/clt/` | Staged Xcode Command Line Tools `.dmg` or `.pkg` installer, when available |

It prints a checklist at the end confirming every artifact is present.

### 4.2 Verify the bundle is complete before copying

```bash
# Verify ZIP integrity and inspect key entries
unzip -tq hxg-install.zip
unzip -l hxg-install.zip | grep 'hxg-install/app/dist/hxg-server/hxg-server'
unzip -l hxg-install.zip | grep 'hxg-install/app/install.sh'
unzip -l hxg-install.zip | grep 'hxg-install/standards/scripts/manifest.json'
unzip -l hxg-install.zip | grep 'hxg-install/standards/unified/com.hxguardian.unified.mobileconfig'

# Archive size (for sizing the SD card)
du -sh hxg-install.zip
```

### 4.3 Copy to SD card

Copy **only** the generated ZIP archive — not the whole repo.

```bash
cp hxg-install.zip /Volumes/<SD_CARD_NAME>/
```

The SD card is now ready to hand off to the airgap device admin. Nothing else
needs to be downloaded on the target.

**Operator-side install order (brief):**
1. `ditto -x -k /Volumes/<SD_CARD>/hxg-install.zip ~/`
2. `sudo zsh ~/hxg-install/app/install.sh`
3. Install `standards/unified/com.hxguardian.unified.mobileconfig` via System Settings
4. `zsh ~/hxg-install/app/rules_setup.sh` — applies all fixes + exemptions, triggers rescan
5. Open `http://127.0.0.1:8000`

---

## 5. Build & Packaging Checklist

Before handing a build to operators, run through these:

- [ ] Python 3.12.10 (python.org build) is installed: `python3.12 --version`.
- [ ] `.venv` exists and `pip install -r app/backend/requirements.txt` completes cleanly.
- [ ] `sudo "$(which python3)" app/backend/hxg_runner.py` starts and logs `Manifest loaded: 266 rules` (venv-activated shell).
- [ ] `zsh app/start-dev.sh` starts and uvicorn reports running on `127.0.0.1:8000`.
- [ ] `curl -s http://127.0.0.1:8000/api/runner/status` returns `runner_connected: true` **and** `available: true`.
- [ ] `npm run build` in `app/frontend/` completes without errors (if frontend changed).
- [ ] [app/frontend/dist/index.html](frontend/dist/index.html) is up to date and committed.
- [ ] A matching Xcode CLT installer is staged under `app/vendor/clt/` when the target does not already have CLT.
- [ ] `zsh app/prepare_sd_card.sh` completes and the final checklist is all green.
- [ ] `unzip -tq hxg-install.zip` succeeds.
- [ ] The LaunchDaemon/LaunchAgent plists in [app/launchd/](launchd/) reference the
      path where the binaries will live on the target device. Update paths if they differ.

---

## 6. Running Manually (Dev Troubleshooting)

If the backend fails to start or scans return errors, run each layer manually to
isolate the problem.

### 6.1 Runner daemon

```bash
source .venv/bin/activate
sudo "$(which python3)" app/backend/hxg_runner.py
```

Leave this open. Expected log line:

```
hxg_runner listening on /var/run/hxg/runner.sock
```

### 6.2 Backend

```bash
source .venv/bin/activate
cd app/backend
python3 -m uvicorn main:app --host 127.0.0.1 --port 8000
```

### 6.3 Common failure modes

| Symptom | Cause / fix |
|---|---|
| `ModuleNotFoundError` on startup | Venv not activated, or deps not installed — `source .venv/bin/activate && pip install -r app/backend/requirements.txt` |
| `sudo: python3: command not found` | `sudo` dropped PATH — use `sudo "$(which python3)" app/backend/hxg_runner.py` |
| `Manifest not found` in runner log | Run from repo root — the runner resolves paths relative to cwd |
| `Permission denied` on socket | `sudo rm -rf /var/run/hxg && sudo mkdir -p /var/run/hxg && sudo chown root:admin /var/run/hxg && sudo chmod 770 /var/run/hxg`, then restart the runner |
| `runner_connected: false` in `/api/runner/status` | Runner is not running or its socket is missing — check Terminal 1 |
| `available: false` with `reason: manifest_empty` | The runner started but `load_manifest()` failed, so it knows zero rules. Restore `standards/scripts/manifest.json`, then restart the runner — it reads the manifest once at startup |
| `available: false` with `reason: standards_missing` | The runner cannot find `standards/scripts/scan/` — check the path it reports in `detail` |
| Rules show **Not Assessed** after a scan | The runner was unavailable, so those rules were never evaluated. Fix the runner (see `detail` on `/api/runner/status`) and re-scan; the score deliberately excludes them rather than counting them as failures |
| All rules return `ERROR` | Runner not running as root, or socket missing — see above |
| `PermissionError: /tmp/hxg_build/... base_library.zip` during `build.sh` / `prepare_sd_card.sh` | The legacy workpath is owned by root from a prior `sudo` build. Run `sudo rm -rf /tmp/hxg_build` once, then re-run without sudo. The current [app/build.sh](build.sh) uses `$TMPDIR/hxg_build` (per-user), so this only affects repos that ran an older build.sh with sudo. |
| `PermissionError: .../app/dist/hxg-server` during PyInstaller COLLECT | `app/dist/` was created by a prior `sudo` build and is now owned by root. Run `sudo rm -rf app/dist` once, then re-run `zsh app/prepare_sd_card.sh` without sudo. |
| `ERROR: Do not run build.sh as root / via sudo` | Re-run `zsh app/prepare_sd_card.sh` (or `zsh app/build.sh`) as your normal admin user, not with `sudo`. PyInstaller and the codesign step must run as the owning user. |

---

## 7. API Surface (Quick Reference)

All routes are under `/api`. The dashboard is localhost-only, so routes are open
to the local browser without a startup auth header. Sensitive actions (applying
fixes, modifying exemptions, USB whitelist changes) require a short-lived 2FA
session token obtained via `POST /api/settings/2fa/verify` and passed as
`X-HXG-Token: <token>` on subsequent calls.

| Method | Path | Purpose |
|---|---|---|
| GET | `/api/health` | Server + runner status |
| GET | `/api/rules` | List all rules (filterable) |
| GET | `/api/rules/{rule_id}` | Rule detail + scan history |
| POST | `/api/scan/single/{rule_id}` | Scan one rule |
| POST | `/api/scan/all` | Scan all rules (streams results) |
| POST | `/api/fix/{rule_id}` | Apply fix script |
| GET | `/api/sessions` | Scan session history |
| GET | `/api/audit-log` | Append-only operator actions |
| GET | `/api/connections` | USB devices, volumes, network, Bluetooth |
| GET/POST/DELETE | `/api/usb-whitelist` | Manage the USB whitelist |
| GET | `/api/reports/*` | Generate HTML / CSV reports |

Routers live in [app/backend/routers/](backend/routers/). Add new endpoints by
creating a router module and including it in [app/backend/main.py](backend/main.py).

---

## 8. Getting Help

- `/help` for Claude Code help.
- File issues at <https://github.com/anthropics/claude-code/issues>.
- The operator-side documentation is in
  [standards/airgap_readme.md](../standards/airgap_readme.md).
