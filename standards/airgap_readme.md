# HX-Guardian — Airgap Device Admin & Operator Guide

End-to-end runbook for hardening a macOS device for airgapped signing operations
and for day-to-day operation once the device is disconnected.

> **Audience:** Airgap device **admins** (who perform the initial setup and
> hardening) and **operators** (who use the device day-to-day). Developers who
> build or modify the dashboard should read
> [../app/app_readme.md](../app/app_readme.md).

> **Network policy:** The airgap target device **never needs internet access**.
> All software — pre-compiled binaries, the dashboard, the unified MDM profile,
> hardening scripts, and the Xcode Command Line Tools installer — arrives on
> the SD card prepared by the developer. TOTP for the dashboard's 2FA works
> fully offline (authenticator apps are time-based, not network-based).

---

## Table of Contents

1. [Prerequisites](#1-prerequisites)
2. [Receiving the SD card bundle](#2-receiving-the-sd-card-bundle)
3. [Install HX-Guardian offline](#3-install-hx-guardian-offline)
4. [Apply bulk fixes and exemptions](#4-apply-bulk-fixes-and-exemptions)
5. [Deploy the unified MDM profile](#5-deploy-the-unified-mdm-profile)
6. [Open the dashboard and enrol admin 2FA](#6-open-the-dashboard-and-enrol-admin-2fa)
7. [Enable FileVault](#7-enable-filevault-full-disk-encryption)
8. [Create the operator account and enrol fingerprints](#8-create-the-operator-account-and-enrol-fingerprints)
9. [Whitelist USB devices](#9-whitelist-usb-devices)
10. [Daily operations](#10-daily-operations)
11. [Recovery procedures](#11-recovery-procedures)
12. [Troubleshooting](#12-troubleshooting)
13. [Appendix — script quick reference](#appendix--script-quick-reference)

---

## 1. Prerequisites

### 1.1 Target device requirements

| Requirement | Version / State | How to check |
|---|---|---|
| macOS | 13 Ventura or later (includes macOS 26 Tahoe) | `sw_vers` |
| Admin account | Must exist on target and be in the `admin` group | `id` |
| Apple ID | Must be **signed out** before hardening begins | System Settings → [Apple ID] |
| macOS updates | Latest available installed | System Settings → General → Software Update |
| An authenticator app on the **admin's** phone | For the single site-wide 2FA secret (Google Authenticator, 1Password, Authy, etc.). Operators do **not** enroll 2FA. | — |

> **macOS Tahoe (26) note:** The `sudo profiles install` CLI no longer deploys
> profiles unattended. Every profile install goes through Finder + System Settings
> with a user-approval click — see §5.

### 1.2 What you need from the developer

An SD card containing the HX-Guardian install bundle (produced by `prepare_sd_card.sh`):

```
/Volumes/<SD_CARD>/hxg-install/
├── app/
│   ├── dist/
│   │   ├── hxg-server/          ← pre-compiled web server binary (PyInstaller onedir)
│   │   ├── hxg-runner/          ← pre-compiled runner binary
│   │   ├── hxg-usb-watcher/     ← pre-compiled USB watcher binary
│   │   └── hxg-shell-watcher/   ← pre-compiled shell-audit watcher binary
│   ├── launchd/                 ← LaunchDaemon plists
│   ├── vendor/clt/              ← Xcode Command Line Tools installer (.dmg or .pkg)
│   ├── install.sh               ← main installer
│   ├── start.sh / stop.sh / restart.sh / update.sh
│   └── rules_setup.sh           ← post-install bulk fix + exemption script
└── standards/
    ├── unified/
    │   └── com.hxguardian.unified.mobileconfig   ← single file, all policies
    ├── launchd/                 ← USB watcher + shell watcher plists
    ├── 800-53r5_high/mobileconfigs/unsigned/
    ├── cisv8/mobileconfigs/unsigned/
    ├── cis_lvl2/mobileconfigs/unsigned/
    └── scripts/                 ← manifest.json, scan/ and fix/ shell scripts
```

If any of these are missing, return the card to the developer — the target device
cannot reach the internet to fetch them.

### 1.3 Baseline choice

This runbook uses **NIST 800-53r5 High** throughout. To use a different baseline,
substitute `cisv8/` or `cis_lvl2/` for `800-53r5_high/` in every path below.

### 1.4 Touch ID policy

Touch ID is intentionally kept **enabled** for operator convenience. Three
baseline rules that would disable it are permanently exempted by `rules_setup.sh` — see
§8.

---

## 2. Receiving the SD card bundle

> **Do not update macOS at this stage.** The developer has already verified
> the app and hardening rules against the shipped macOS version. Bumping the
> OS here can invalidate that testing (profile keys change between releases,
> Tahoe's `profiles install` lockdown is a recent example). Stay on the
> version the device arrived with unless the developer explicitly says to
> upgrade.

### 2.1 Sign out of Apple ID and disable iCloud

```
System Settings → [Apple ID] → Sign Out
```

Disable iCloud Drive, Find My Mac, and all iCloud sync **before** continuing.

### 2.2 Copy the bundle from SD card to local disk

```bash
cp -R /Volumes/<SD_CARD_NAME>/hxg-install ~/hxg-install
```

---

## 3. Install HX-Guardian offline

### 3.1 Install Xcode Command Line Tools (CLT)

HX-Guardian's scan/fix scripts use `/usr/bin/xmllint` and `/usr/bin/python3`,
both of which are CLT shims on modern macOS. `install.sh` does **not** install
CLT — it only verifies CLT is present and aborts with instructions if it is
not. Install CLT manually from the bundled installer **before** running
`install.sh`:

1. In Finder, navigate to `~/hxg-install/app/vendor/clt/`.
2. **Double-click** the `.pkg` file (or open the `.dmg` first and then
   double-click the `.pkg` inside it).
3. The standard macOS Installer opens. Click through **Continue → Agree →
   Install**, then enter the admin password when prompted.
4. Wait for installation to complete (a few minutes). Close the Installer when
   finished.

Verify:

```bash
xcode-select -p
# → /Library/Developer/CommandLineTools
```

> **Why manual?** CLT installs pop a GUI prompt and can require Apple-ID-bound
> consent flows on some macOS builds. Keeping the install step off the
> automated installer avoids mid-run interruptions and keeps the airgap
> device's install footprint predictable.

### 3.2 Run the installer

```bash
sudo zsh ~/hxg-install/app/install.sh
```

The installer performs all steps fully offline — no internet required:

| Step | What it does |
|---|---|
| 0 | Removes any existing HX-Guardian services and binaries |
| 1 | Deploys pre-compiled binaries (server, runner, USB watcher, shell watcher) to `/Library/Application Support/hxguardian/bin/` |
| 1b | Verifies Xcode Command Line Tools are present; aborts with instructions to install from `app/vendor/clt/` if missing (see §3.1) |
| 2 | Copies the standards tree (scripts + manifest + profiles) to `/Library/Application Support/hxguardian/standards/` |
| 3 | Creates `/var/run/hxg/` (Unix socket directory) and log files in `/Library/Logs/` |
| 4 | Installs four **LaunchDaemons** — runner (root), server (admin user), USB watcher (root), shell watcher (root) |
| 4b | Writes the hxguardian block into `/etc/zshrc` (enables `INC_APPEND_HISTORY` + `EXTENDED_HISTORY` so the shell watcher captures commands in real time) |
| 5 | Enforces password policy locally via `pwpolicy` (min 15 chars, complexity, lockout). All existing non-system local accounts are flagged to change password on next login. |
| 6 | Starts all four services (`start.sh`) and pings `/api/health` |
| 7 | Opens the unified MDM profile in System Settings for user approval — complete §5 when prompted |

### 3.3 Admin password policy — what to expect

Two layers enforce password policy on the airgap device:

1. **Profile layer (minimal floor).** The unified MDM profile ships a small
   `com.apple.mobiledevice.passwordpolicy` payload — `requireAlphanumeric=true`,
   `minComplexChars=1`. This gives the OS a baseline passcode check the moment
   the profile lands.
2. **Local layer (full enforcement).** `install.sh` writes a site-wide
   `pwpolicy` covering every local account — min 15 chars,
   upper+lower+digit+special, 5-failures lockout. This is where the real
   enforcement lives.

**Your own admin password is not force-changed by the installer.** The script
explicitly skips the currently logged-in installer user so the airgap device
does not lock you out on first logout. The password you used to run
`sudo zsh app/install.sh` keeps working.

**But you still need to meet the policy on any voluntary change.** Compliance
scans (`pwpolicy_*`) PASS because they check that the policy is present, not
each account's password hash.

**Strongly recommended:** change your admin password voluntarily **now**, before
airgapping:

```bash
passwd
```

That confirms the policy is active (the system will reject a non-compliant new
password) and prevents being surprised later with an offline device.

### 3.4 Confirm all four services are running

```bash
sudo launchctl list | grep hxguardian
# Expected:
#   com.hxguardian.runner
#   com.hxguardian.server
#   com.hxguardian.usbwatcher
#   com.hxguardian.shellwatcher
```

All four are LaunchDaemons under `/Library/LaunchDaemons/`. The server plist
has `UserName` set to the admin user so the dashboard runs non-root; the other
three run as root.

---

## 4. Apply bulk fixes and exemptions

This is the post-install hardening step. Wait ~10 seconds for the server to
start after `install.sh` completes, then run:

```bash
zsh ~/hxg-install/app/rules_setup.sh
```

If you removed `~/hxg-install`, the script is also at:

```bash
zsh /Library/Application\ Support/hxguardian/app/rules_setup.sh
```

### What it does

| Phase | Action |
|---|---|
| **1 — Fixes** | Applies fix scripts for all fixable compliance rules. Rules in the exempt list below are skipped to avoid disruptive changes (e.g. enforcing smartcard auth when no hardware is present). |
| **2 — Exemptions** | Creates permanent exemptions for the rules listed below. These appear as **EXEMPT** in the dashboard instead of FAIL, and are excluded from the compliance score. |
| **3 — Rescan** | Triggers a full compliance scan and waits for completion. Prints the final score, pass/fail/exempt counts. |

### Rules exempted (permanent)

| Group | Rules |
|---|---|
| Smartcard | `auth_pam_login_smartcard_enforce`, `auth_pam_su_smartcard_enforce`, `auth_pam_sudo_smartcard_enforce`, `auth_smartcard_allow`, `auth_smartcard_certificate_trust_enforce_high`, `auth_smartcard_enforce`, `supplemental_smartcard` |
| Touch ID | `os_touchid_prompt_disable`, `system_settings_touch_id_settings_disable`, `system_settings_touchid_unlock_disable` |
| Policy exceptions | `os_config_data_install_enforce`, `os_config_profile_ui_install_disable`, `os_httpd_disable`, `os_root_disable` |
| Software updates | `os_software_update_app_update_enforce`, `os_software_update_deferral`, `system_settings_download_software_update_enforce`, `system_settings_software_update_download_enforce`, `system_settings_softwareupdate_current` |
| Time Machine | `system_settings_time_machine_auto_backup_enable` |

---

## 5. Deploy the unified MDM profile

HX-Guardian ships a single unified profile that bundles every policy this
runbook requires.

**Profile file:** `standards/unified/com.hxguardian.unified.mobileconfig`
**Identifier:** `com.hxguardian.unified`

### 5.1 Install the profile (macOS Tahoe 26 and later)

`install.sh` opens the profile automatically in its final step. If you need to
re-open it manually:

1. In Finder, navigate to
   `/Library/Application Support/hxguardian/standards/unified/`.
2. **Double-click** `com.hxguardian.unified.mobileconfig`. macOS copies it into
   the pending-profiles queue and opens System Settings.
3. Go to **System Settings → General → Device Management** (on Tahoe it may
   appear under **Privacy & Security → Profiles**).
4. Select **HX-Guardian Unified** from the list → click **Install** → enter the
   admin password when prompted.

   > **Expect a second prompt for the FileVault user.** Because the profile
   > carries a FileVault payload, macOS also asks for the password of the
   > current FileVault-enabled user before it can apply that payload. Enter the
   > admin login password — **not** the Personal Recovery Key. If FileVault has
   > not been turned on yet (§7), the profile installs without this second
   > prompt and the FileVault payload activates the next time FileVault is
   > enabled.
5. The profile is now deployed. It cannot be removed except by an admin.

### 5.2 What the unified profile enforces

The single file applies every policy this runbook used to deploy as separate
profiles:

| Area | Effect |
|---|---|
| FileVault 2 | Pre-requires FileVault (operator still enables via System Settings — §7) |
| Firewall | Enables application firewall + stealth mode |
| iCloud | Blocks Drive, Keychain, Photos, Mail, Calendar, Notes, Reminders, Bookmarks, Private Relay, and hides the Apple ID pane |
| Login window | Hides user list, disables guest, shows username+password prompt |
| Screen lock | Idle timeout + password-required |
| Software updates | Enforces automatic checks |
| Gatekeeper | Identified developers only, right-click override disallowed |
| Application access | Blocks AirDrop, Siri, dictation; enables USB Restricted Mode |
| System preferences | Locks sensitive panes |
| Setup assistant | Suppresses first-run prompts |
| Diagnostics | Disables crash-report submission to Apple |
| Password policy (minimal floor) | `requireAlphanumeric=true`, `minComplexChars=1` — baseline only |

The profile's password payload is a **minimal floor only**. The full policy
(length, history, lockout) is layered on locally by `install.sh` using
`pwpolicy`. See §3.3.

### 5.3 Verify the profile is installed

From the dashboard: **MDM Profiles** page — `com.hxguardian.unified` shows a
green installed check. Or from the terminal:

```bash
sudo profiles list | grep hxguardian
# → attribute: name: HX-Guardian Unified
# → attribute: identifier: com.hxguardian.unified
```

> On macOS Tahoe, `profiles -P` without `sudo` silently returns empty. Use
> `sudo profiles list` as shown above, or check
> **System Settings → General → Device Management** for the HX-Guardian
> Unified entry.

---

## 6. Open the dashboard and enrol admin 2FA

### 6.1 Go to the dashboard

Open Safari and go to:

```
http://127.0.0.1:8000
```

The dashboard has **no startup token**. It opens immediately for anyone on
`127.0.0.1`. The server binds to loopback only — it is unreachable from the
network.

### 6.2 Verify the runner is connected

The dashboard exposes three public no-auth endpoints for liveness:

```bash
curl -s http://127.0.0.1:8000/api/health
# → {"status":"ok","ready":true,"version":"1.0.0"}

curl -s http://127.0.0.1:8000/api/runner/status
# → {"runner_connected":true}

curl -s http://127.0.0.1:8000/api/internal/startup
# → {"started_at":...,"finished_at":...,"elapsed_seconds":0.012,"ready":true,"error":null}
```

`/api/health` reports only this server's liveness — it does **not** depend on
the runner, so a slow runner cannot collapse the dashboard. Runner liveness is
a separate endpoint, `/api/runner/status`. `/api/internal/startup` shows how
long the background DB/scheduler init took and surfaces the exception class
if startup failed (handy for diagnosis without log access).

If `ready` is `false` or `runner_connected` is `false`, jump to
[§12 Troubleshooting](#12-troubleshooting).

### 6.3 Authentication model

- Read-only dashboard access is open on `127.0.0.1` — anyone logged into the
  Mac can browse scans, reports, and audit logs.
- Sensitive actions (apply a fix, change the USB whitelist, grant an exemption,
  view the QR for an enrolled secret) require a **TOTP from 2FA**.
  The UI prompts for a 6-digit code; the backend issues a 10-minute
  `X-2FA-Token` that covers follow-up requests.
- **2FA is a single site-wide secret held by the admin** — not per-user. Only
  the admin enrolls and holds the authenticator app. Operators cannot (and
  should not) perform any gated action — those are admin-only.
- Physical possession of the device (airgap + FileVault + firmware password)
  is the primary perimeter; admin 2FA prevents an unattended-but-unlocked
  session from silently altering the compliance state.

### 6.4 Admin enrols 2FA (singleton TOTP) — one-time

HX-Guardian 2FA is standard TOTP (RFC 6238) — works fully offline once enrolled.
The admin performs this **once**; there is no per-operator enrollment.

1. Log in as the **admin**.
2. Open the dashboard at `http://127.0.0.1:8000`.
3. Go to **Settings → Two-Factor Authentication → Set Up**.
4. The dashboard shows a QR code. On the **admin's phone**, open an
   authenticator app (Google Authenticator, 1Password, Authy, etc.) and scan
   it.
5. Enter the current 6-digit code into the dashboard → **Enable 2FA**.
6. Test: trigger any gated action (e.g. re-scan a single rule) — the UI should
   prompt for a 6-digit code. Enter the current code; the action should
   succeed.

> **Offline guarantee:** TOTP is time-based, not network-based. Keep the
> admin's phone clock accurate (automatic time zone on; phones stay within a
> few seconds of real time for months). No network required at any step from
> here on.

> **Operational implication:** gated actions (apply fix, edit whitelist,
> grant exemption) can only be completed when the **admin is physically
> present with their phone**. Operators perform read-only workflows and escalate
> to the admin for anything that changes state. This is intentional.

---

## 7. Enable FileVault (full-disk encryption)

> On macOS Tahoe, the MDM `ForceEnableInSetupAssistant` trigger is unreliable —
> enable FileVault **directly from System Settings**.

### 7.1 Turn on FileVault

1. **System Settings → Privacy & Security → FileVault → Turn On FileVault…**
2. When asked where to store the recovery key, choose
   **Create a local recovery key** — do **not** use iCloud (the device is to
   be airgapped).
3. macOS generates and displays the **Personal Recovery Key (PRK)**.
   **Write it down immediately** — this is the only time it is shown in full.
4. Store the key **on paper, physically secured offline** (safe, tamper-evident
   envelope, whatever your security policy mandates).
5. Click **Continue**. FileVault begins encrypting in the background — you can
   keep using the device, but a reboot is required for encryption to complete.

### 7.2 Verify FileVault

```bash
sudo fdesetup status
# → FileVault is On.
```

On the dashboard, scan both rules and confirm PASS:

```bash
sudo zsh standards/scripts/scan/system_settings_filevault_enforce.sh
sudo zsh standards/scripts/scan/os_filevault_autologin_disable.sh
```

---

## 8. Create the operator account and enrol fingerprints

**Role split — read first:**

| Role | Accounts | Dashboard access | 2FA | Can apply fixes / change whitelist / grant exemptions? |
|---|---|---|---|---|
| Admin | 1 (you) | Read + gated actions | **Yes — site-wide secret on admin's phone** | Yes |
| Operator | 1 shared account, N fingerprints | Read only | No | No |

2FA is a **singleton** in HX-Guardian — there is one secret for the whole
dashboard, not one per user. The admin holds it.

Multiple operators can share a single macOS operator account. Touch ID events
are attributed to the **macOS account** that authenticated. macOS does **not**
expose the enrolled fingerprint slot in its audit log, so on a shared operator
account the biometric audit trail tells you *that* an operator unlocked, not
*which* operator. If per-operator attribution is required, give each operator
their own standard account instead of sharing one.

### 8.1 Create the shared operator account

Operators share a single standard (non-admin) macOS user. Create it via
System Settings while logged in as admin:

1. **System Settings → Users & Groups → Add Account…** (admin password required).
2. **New User** → **Standard**.
3. Enter a full name (e.g. "Operator"), account name (e.g. `operator`),
   and a strong password.
4. Click **Create User**.

> `install.sh` enforces the compliant password policy via `pwpolicy`
> automatically — the new account inherits it.

### 8.2 First login and password change

1. Log out of the admin account.
2. Log in as `operator` with the temporary password.
3. macOS will **force a password change** — set a password that satisfies the
   policy (min 15 chars, mixed case, digit, special character).
4. Log out and return to the admin account.

### 8.3 Touch ID enrollment — one fingerprint per operator

Touch ID is the device's second perimeter (unlock + sudo prompt). Enrol one
fingerprint per human operator in the shared account:

1. Log in as `operator`.
2. **System Settings → Touch ID & Password → Add a Fingerprint**.
3. Have each operator enrol their own fingerprint.
4. Repeat until every authorised operator has a slot (Apple allows up to three
   fingerprints per account across all accounts on the Mac).
5. Test: each operator locks the screen and unlocks with their own finger.

> Touch ID is not required for sudo on the operator account — operators do not
> have sudo rights. It is used for unlock and for any per-fingerprint biometric
> audit logging.

### 8.4 Admin Touch ID (optional but recommended)

Log in as the admin, **System Settings → Touch ID & Password**, enrol at least
one finger. Test with `sudo -v` in Terminal — the Touch ID prompt should
appear.

### 8.5 Touch ID exception — permanently exempted

Three baseline rules are permanently **EXEMPT** (not FAIL) — `rules_setup.sh`
creates these exemptions automatically in §4. Do **not** run their fix scripts.

| Rule | Reason |
|---|---|
| `system_settings_touchid_unlock_disable` | Operators use Touch ID for unlock |
| `system_settings_touch_id_settings_disable` | Operators manage their own fingerprints |
| `os_touchid_prompt_disable` | Enrollment prompt needed for new operators |

These rules show an **Exempt** badge in the dashboard and are excluded from the
compliance score.

---

## 9. Whitelist USB devices

### 9.1 Whitelist known-good USB devices

Register every USB peripheral the airgap device will ever use (YubiKeys, CAC
readers, approved keyboards/mice, encrypted drives) **before** physical
disconnect.

1. Connect each approved USB device one at a time.
2. Open the dashboard → **Connections** (`http://127.0.0.1:8000/connections`).
3. Each device appears in the **USB DEVICES** section. Unknown devices show a
   red **Unauthorized** badge.
4. Click **Add to Whitelist** next to each approved device. The form pre-fills
   with the device name, vendor, product ID, and serial.
5. Add a note (operator name, asset tag, purpose) and save. The backend will
   prompt for a 2FA TOTP code — enter the current code from the admin's
   authenticator app.
6. The device now shows a green **Whitelisted** badge.

**Storage volumes (SD cards, USB drives):**
Volumes appear in the **USB VOLUMES** section below **USB DEVICES** and inherit
whitelist status from their **parent USB device** (the card reader or hub port).
Whitelisting the parent device permits its storage volumes.

**Manual add / remove:** Use the **USB WHITELIST** card below the device list.
All changes are written to the Audit Log.

**Match criteria:** A device is considered whitelisted if `product_id` **or**
`serial` matches any whitelist entry (whichever fields are non-empty). Prefer
serial when available for strongest identity binding.

### 9.2 The USB watcher is already installed

`install.sh` has already installed and started
`/Library/LaunchDaemons/com.hxguardian.usbwatcher.plist`. It survives reboots
via `KeepAlive`. What it does:

| Action | Detail |
|---|---|
| Polls USB bus | Every 5 seconds via `system_profiler SPUSBDataType` |
| Reads whitelist | Every 30 seconds from SQLite (`usb_whitelist` table) |
| Ejects storage | `diskutil eject` on any unauthorized removable volume |
| Re-ejects on replug | Tracks BSD disk names — re-ejects if a card is removed and reinserted into the same reader |
| Notifies operator | macOS notification with `Basso` sound |
| Logs to audit trail | Writes `USB_UNAUTHORIZED_DEVICE` entry |

---

## 10. Daily operations

### 10.1 Open the dashboard

```
http://127.0.0.1:8000
```

No token, no login screen. 2FA prompts appear only when an operator attempts
a gated action (apply fix, change whitelist, grant exemption).

### 10.2 Adding a USB device to the whitelist (post-airgap)

Whitelist changes are admin-only.

1. Log in as the **admin** (operators cannot complete this flow — gated on
   admin 2FA).
2. Connect the new USB device.
3. Dashboard → **Connections** → locate the device in **USB DEVICES**.
4. Click **Add to Whitelist**, fill in the purpose / owner note, save.
5. Enter the 6-digit TOTP from the **admin's** authenticator app.
6. The USB watcher picks up the change within 30 seconds — no restart needed.
7. The action is recorded in the **Audit Log** under the admin account.

### 10.3 Scheduling recurring scans

Dashboard → **Schedule** → configure a cron expression
(e.g. daily 02:00: `0 2 * * *`). The runner executes the scan session as root
and results appear in **Scan History**.

### 10.4 Generating reports

Dashboard → **Reports** → choose **HTML** (printable) or **CSV** (for archival).
Reports include the compliance score, per-rule status, audit-log excerpt, and
exemptions list.

### 10.5 Granting / revoking an exemption

Admin-only. Dashboard → **Exemptions** → **Grant Exemption** → enter rule ID,
reason, and expiry date. Admin TOTP prompt appears. Exempted rules are counted
as PASS in compliance reports but remain visible in the Rules list with an
**Exempt** badge.

### 10.6 Service management scripts

`install.sh` deploys four LaunchDaemons that auto-start at boot, so day-to-day
the services run unattended. The bundle ships four small management scripts for
the times you do need to intervene (binary update, plist edit, troubleshooting).
All four require `sudo`.

| Script | Purpose | Run from | Notes |
|---|---|---|---|
| `start.sh` | Bootstraps all four LaunchDaemons (runner, server, USB watcher, shell watcher). Re-bootstraps any that are already loaded. | `/Library/Application Support/hxguardian/app/` (or `~/hxg-install/app/` if still present) | Also invoked at the end of `install.sh`. Gates on three checks before exiting: server responds, `/api/health` reports `ready: true`, and `/api/runner/status` reports `runner_connected: true`. Exits non-zero (with the relevant log tail) if any check fails — better to fail the install loudly than let the operator find the dashboard wedged later. |
| `stop.sh` | `bootout`s all four daemons, kills any lingering processes (TERM then KILL), removes the stale Unix socket. | Same as `start.sh` | Use before manual binary swaps or before re-running `install.sh`. |
| `restart.sh` | Calls `stop.sh` then `start.sh`. | Same as `start.sh` | Convenience only — equivalent to running both back-to-back. |
| `update.sh [target]` | Re-deploys pre-built binaries from a transfer bundle's `app/dist/`, then restarts the matching LaunchDaemons. `target` is one of `runner`, `server`, `usbwatcher`, `shellwatcher`, or `all` (default). | **Bundle directory only** — `~/hxg-install/app/` or `/Volumes/<SD>/hxg-install/app/`. Requires `dist/` to sit alongside the script, which is only true in the SD-card bundle. | The fast path for shipping a new build. Skips pwpolicy, the `/etc/zshrc` edit, and the MDM profile open — those only need to happen once at first install. |

Examples:

```bash
# Restart everything after editing a plist
sudo zsh /Library/Application\ Support/hxguardian/app/restart.sh

# Push a freshly-built server binary (from the SD-card bundle)
sudo zsh ~/hxg-install/app/update.sh server

# Push all four watchers / runner / server in one shot
sudo zsh ~/hxg-install/app/update.sh
```

> `update.sh` is the only one of the four scripts that is **not** copied into
> `/Library/Application Support/hxguardian/app/` by `install.sh` — it depends
> on the bundled `dist/` tree and would fail in isolation. Keep the SD-card
> bundle (or a copy of it) accessible whenever you plan to deploy new binaries.

### 10.7 Reviewing the audit logs

The **Audit Log** page is the single pane for every auditable event the device
records. The **Action** dropdown at the top of the page switches between three
underlying data sources — each backed by its own SQLite table and its own
REST + SSE endpoint:

| View | Contents | Source table |
|---|---|---|
| **All Actions** (default) | Dashboard-initiated events: `SCAN_RUN`, `SCAN_COMPLETE`, `FIX_APPLIED`, `EXEMPTION_GRANTED`/`REVOKED`, `SCHEDULE_*`, `REPORT_GENERATED`, `PREFLIGHT_RUN`, `USB_UNAUTHORIZED_DEVICE`, `SUSPICIOUS_ACTION` | `audit_log` |
| **SHELL_EXEC** | Every command typed into an interactive zsh session by any account (captured via `/etc/zshrc` + the shell watcher) | `shell_exec_log` |
| **BIOMETRIC_AUTH** | Every Touch ID unlock and `sudo` authentication, attributed to the macOS account. Per-fingerprint (which slot) attribution is **not** captured — macOS does not expose it. | `biometric_events` |

**Filters available in every view:** a date range (From → To) and per-view
filters (search box for SHELL_EXEC/BIOMETRIC_AUTH, `Include teardown noise`
checkbox for BIOMETRIC_AUTH, action dropdown for the general audit log).
Pagination is 100 rows per page.

**Exports:**

- **Export CSV** — visible only in the general audit log view.
- **Export JSONL** — available in all three views. Writes a newline-delimited
  JSON file suitable for SIEM or offline archival. Filters apply to the export.

#### Go Live (real-time tail)

Next to the **Refresh** button, each view has a **Go Live** toggle. When on:

- The page opens an SSE (Server-Sent Events) connection to the matching
  `/api/stream/…` endpoint.
- New rows appear at the top as they are written to SQLite, with a ~2 s blue
  flash so they are easy to spot.
- Pagination is hidden; filters still apply and the stream re-connects
  automatically when you change them.
- **Pause** freezes the visible list without dropping the connection.
  **Resume** re-opens the flow.
- End-to-end latency is ~2–4 s (the shell watcher batches to SQLite every 2 s
  and the stream polls every 2 s).

Use cases:

- **Troubleshooting missing events** — watch the pipeline end-to-end.
  If a shell command shows up in `~/.zsh_history` but never streams into the
  dashboard, the shell watcher or its cursor is stuck (see §12).
- **Monitoring an active operator session** — leave the page open on
  `SHELL_EXEC` or `BIOMETRIC_AUTH` while work is happening.
- **Live ops view during a scan** — stream the general audit log to see
  `SCAN_RUN` → per-rule activity → `SCAN_COMPLETE` as it happens.

> **Status indicator:** below the table while Live is on, `● Streaming live`
> means the SSE connection is healthy. `○ Reconnecting...` means the backend
> dropped (service restart, etc.) — the browser will auto-retry.

---

## 11. Recovery procedures

### 11.1 Reset an operator password (via UI)

The admin can reset the operator account password directly from macOS:

1. Log in as the **admin**.
2. **System Settings → Users & Groups** → click the info icon next to the
   operator account → **Reset Password…**
3. Enter the admin password and set a new operator password. The installed
   pwpolicy still applies.

**If the admin password itself is lost:**

1. Reboot into Recovery Mode (**hold Power** / **Cmd+R**).
2. Utilities → Terminal.
3. `resetpassword` — pick the admin user, set a new password.
4. Reboot normally.

> If FileVault is on and **both** the admin password and the PRK (§7.1) are lost,
> the data is unrecoverable by design.

### 11.2 Unlock a locked-out account

If the password-policy lockout triggers, unlock from an admin shell:

```bash
sudo pwpolicy -u operator -clearaccountpolicies
```

Then re-apply the site-wide policy so the account remains compliant by
re-running `install.sh` from the SD-card bundle (or `~/hxg-install/` if you
kept it):

```bash
sudo zsh ~/hxg-install/app/install.sh
# or, if you removed it: re-mount the SD card and run from there
```

(The installer is idempotent — it re-runs the pwpolicy step without disturbing
existing services or data. `install.sh` is intentionally not deployed under
`/Library/Application Support/hxguardian/` because it depends on the bundled
`dist/` tree; only `start.sh`, `stop.sh`, `restart.sh`, and `rules_setup.sh`
live there post-install.)

### 11.3 Re-enroll a Touch ID fingerprint

Only someone logged into the owning account can add or remove fingerprints:

1. Log in as the operator (or admin for the admin account).
2. **System Settings → Touch ID & Password**.
3. Remove the old fingerprint (trash icon) and add a new one.

### 11.4 Reset admin 2FA

- **Normal rekey (admin still has their phone):** Dashboard → **Settings →
  Two-Factor Authentication → Rekey**. TOTP prompt for the existing secret,
  then a new QR appears — rescan on the phone.
- **Disable 2FA entirely (still has phone):** Dashboard → **Settings →
  Disable 2FA** → enter current TOTP.
- **Lost phone, cannot rekey via UI:** there are no backup / scratch codes —
  recovery is via SQLite:
   ```bash
   sudo sqlite3 "/Library/Application Support/hxguardian/data/hxguardian.db" \
       "DELETE FROM two_factor_config;"
   sudo launchctl kickstart -k system/com.hxguardian.server
   ```
  Then immediately re-enrol via §6.4 on the replacement phone. The SQLite
  delete and the re-enrollment are both recorded in the Audit Log.

### 11.5 Reinstall HX-Guardian from SD card

Bring the original SD card (or a fresh one from the developer) and run:

```bash
cp -R /Volumes/<SD_CARD_NAME>/hxg-install ~/hxg-install
sudo zsh ~/hxg-install/app/install.sh
zsh ~/hxg-install/app/rules_setup.sh
```

The installer is idempotent — it upgrades binaries and standards in place and
preserves `/Library/Application Support/hxguardian/data/` (DB + reports).
Re-running `rules_setup.sh` after reinstall is also safe — exemptions are
updated rather than duplicated.

---

## 12. Troubleshooting

**Dashboard not loading**
```bash
curl -s http://127.0.0.1:8000/api/health
# Should return: {"status":"ok","ready":true,"version":"1.0.0"}
curl -s http://127.0.0.1:8000/api/internal/startup
# elapsed_seconds + error fields tell you where startup is stuck
```

**Dashboard hangs after reboot (every request, including static files)**
- Should not happen with the current build — the lifespan handler yields
  immediately and the runner socket is bound by launchd via socket activation
  (no boot-order race possible).
- If it does, see the operator escape hatch in
  [`airgap-reboot-debug.md` §10](../airgap-reboot-debug.md) — restoring the
  pre-fix runner plist is a one-line `cp` from the install-time backup at
  `/Library/LaunchDaemons/com.hxguardian.runner.plist.bak.<TIMESTAMP>` plus
  `launchctl bootout && bootstrap`.

**`runner_connected: false` in `/api/runner/status`**
```bash
sudo launchctl print system/com.hxguardian.runner | head
# Under socket activation the runner is on-demand: the listener stays bound
# by launchd even when the binary process is not currently running. To force
# a respawn (and pick up a fresh binary), bootout + bootstrap:
sudo launchctl bootout system /Library/LaunchDaemons/com.hxguardian.runner.plist
sudo launchctl bootstrap system /Library/LaunchDaemons/com.hxguardian.runner.plist
# Then probe the socket directly to trigger the spawn:
echo '{"action":"ping"}' | nc -U /var/run/hxg/runner.sock -w 5
```

**Scan returns ERROR for all rules**
- The runner must be running as root. Check `/Library/Logs/hxguardian-runner.log`.
- Verify the socket exists: `ls -la /var/run/hxg/runner.sock`.
- The **Rule Detail** page shows the full server error for a single-rule scan.

**Scan results not updating after "Run Full Scan"**
- The frontend polls session status and reloads automatically when the scan
  finishes. Wait for the **Scanning…** button to return to normal, then reload
  the Rules page.
- If results never update, check that the runner is connected (`/api/runner/status`).

**MDM rules still showing `MDM_REQUIRED` after deploying the unified profile**
- MDM-only rules are verified by whether the profile is installed. Deploying
  the profile does not automatically update past scan results — run a new
  full scan.
- If the profile install was blocked, check
  **System Settings → General → Device Management** for an unapproved
  pending profile.

**`profiles install` on the CLI does nothing (Tahoe)**
- Expected. Use the Finder + System Settings flow in §5.1 instead.

**USB watcher: device detected but not ejected / not re-ejected after replug**
```bash
tail -f /var/log/hxguardian_usb.log
```
- `Could not eject` → `diskutil eject` failed; inspect the log for the reason.
- No log entry at all → watcher is not running; `sudo launchctl bootstrap system /Library/LaunchDaemons/com.hxguardian.usbwatcher.plist`.
- Device shows **Whitelisted** → remove the whitelist entry to re-enable
  enforcement.

**Shell watcher: commands not appearing in the Shell Log**
- Confirm `/etc/zshrc` still contains the `>>> hxguardian-audit >>>` block (re-run
  `install.sh` if the block was edited out).
- New zsh sessions must be opened after install — commands typed in a session
  started before install won't be captured.
- Check the daemon log: `tail -f /var/log/hxguardian_shell.log`.

**2FA prompt appears but every code from the admin's phone is rejected**
- Phone clock is out of sync with the device. Re-sync the phone's time
  (automatic time zone on). TOTP tolerates roughly ±30 s drift.
- Last-resort reset (admin's phone lost / unrecoverable): §11.4.

**Server fails to start / binary not found**
```bash
# Re-deploy binaries from the SD card bundle
sudo zsh ~/hxg-install/app/install.sh
```

**Permission denied on socket**
Under launchd socket activation, the runner socket file is owned by launchd —
do **not** `rm -rf /var/run/hxg` (that breaks the bound listener and a plain
`kickstart -k` won't re-create it because `KeepAlive=false`). Re-bind via
bootout + bootstrap so launchd re-creates the socket with the perms declared
in the plist (`root:admin 660`):
```bash
sudo launchctl bootout system /Library/LaunchDaemons/com.hxguardian.runner.plist
sudo launchctl bootstrap system /Library/LaunchDaemons/com.hxguardian.runner.plist
ls -l /var/run/hxg/runner.sock     # expect: srw-rw---- root admin
```

---

## Appendix — Script Quick Reference

All scripts live under `standards/scripts/` and require `sudo zsh <script>`.

| Category | Scan count | Fix count |
|---|---|---|
| Audit | 25 | 25 |
| Authentication | 7 | 4 |
| iCloud | 14 | 0 (MDM only) |
| Operating System | 91 | 40 |
| Password Policy | 11 | 2 |
| System Settings | 66 | 15 |

Full rule index: `standards/scripts/manifest.json`
Standards comparison: `standards/security_standards_comparison.md`

### USB enforcement

| Script / file | Purpose |
|---|---|
| `app/install.sh` | Installs the USB watcher LaunchDaemon (among other services) |
| `app/backend/usb_watcher.py` | The daemon source (shipped pre-compiled as `hxg-usb-watcher`) |
| `/Library/LaunchDaemons/com.hxguardian.usbwatcher.plist` | Installed plist |
| `/var/log/hxguardian_usb.log` | Daemon runtime log |

### Shell audit

| Script / file | Purpose |
|---|---|
| `app/backend/shell_watcher.py` | Daemon source (shipped pre-compiled as `hxg-shell-watcher`); tails per-user `~/.zsh_history` and the unified log, feeds `shell_exec_log` |
| `standards/launchd/com.hxguardian.shellwatcher.plist` | Installed plist (deployed to `/Library/LaunchDaemons/` by `install.sh`) |
| `/etc/zshrc` hxguardian block | Enables `INC_APPEND_HISTORY` + `EXTENDED_HISTORY` so every command is captured in real time |
| `/var/log/hxguardian_shell.log` | Daemon runtime log |

### Key paths after install

| Path | Contents |
|---|---|
| `/Library/Application Support/hxguardian/` | Installed app (code + data + bin) |
| `/Library/Application Support/hxguardian/data/hxguardian.db` | SQLite DB (scans, audit, whitelist, 2FA, shell log, biometric log) |
| `/Library/LaunchDaemons/com.hxguardian.runner.plist` | Runner (root) |
| `/Library/LaunchDaemons/com.hxguardian.server.plist` | Server (admin user) |
| `/Library/LaunchDaemons/com.hxguardian.usbwatcher.plist` | USB watcher (root) |
| `/Library/LaunchDaemons/com.hxguardian.shellwatcher.plist` | Shell watcher (root) |
| `/Library/Logs/hxguardian-{server,runner}.log` | Service logs |
| `/var/log/hxguardian_usb.log` | USB watcher log |
| `/var/log/hxguardian_shell.log` | Shell watcher log |
| `/var/run/hxg/runner.sock` | Unix socket between server and runner |

---

## Uninstall (rarely used)

```bash
# Stop and remove all four LaunchDaemons
sudo launchctl bootout system /Library/LaunchDaemons/com.hxguardian.server.plist
sudo launchctl bootout system /Library/LaunchDaemons/com.hxguardian.runner.plist
sudo launchctl bootout system /Library/LaunchDaemons/com.hxguardian.usbwatcher.plist
sudo launchctl bootout system /Library/LaunchDaemons/com.hxguardian.shellwatcher.plist
sudo rm /Library/LaunchDaemons/com.hxguardian.server.plist
sudo rm /Library/LaunchDaemons/com.hxguardian.runner.plist
sudo rm /Library/LaunchDaemons/com.hxguardian.usbwatcher.plist
sudo rm /Library/LaunchDaemons/com.hxguardian.shellwatcher.plist

# Remove socket directory
sudo rm -rf /var/run/hxg

# Remove the hxguardian audit block from /etc/zshrc
sudo sed -i '' '/# >>> hxguardian-audit >>>/,/# <<< hxguardian-audit <<</d' /etc/zshrc

# Remove the unified MDM profile
# System Settings → General → Device Management → HX-Guardian Unified → Remove

# Optionally remove installed app + data (scan history, audit log, 2FA secrets)
sudo rm -rf "/Library/Application Support/hxguardian"
```
