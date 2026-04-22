# HX-Guardian — Airgap Device Admin & Operator Guide

End-to-end runbook for hardening a macOS device for airgapped signing operations
and for day-to-day operation once the device is disconnected.

> **Audience:** Airgap device **admins** (who perform the initial setup and
> hardening) and **operators** (who use the device day-to-day). Developers who
> build or modify the dashboard should read
> [../app/app_readme.md](../app/app_readme.md).

> **Network policy:** The airgap target device **never needs internet access**.
> All software — Python, dependency wheels, the dashboard, the unified MDM
> profile, hardening scripts — arrives on the SD card prepared by the developer.
> TOTP for the dashboard's 2FA works fully offline (authenticator apps are
> time-based, not network-based).

---

## Table of Contents

1. [Prerequisites](#1-prerequisites)
2. [Receiving the SD card bundle](#2-receiving-the-sd-card-bundle)
3. [Install HX-Guardian offline](#3-install-hx-guardian-offline)
4. [Open the dashboard](#4-open-the-dashboard)
5. [Deploy the unified MDM profile](#5-deploy-the-unified-mdm-profile)
6. [Enable FileVault](#6-enable-filevault-full-disk-encryption)
7. [Create operator users and set up 2FA](#7-create-operator-users-and-set-up-2fa)
8. [Enable and verify the firewall](#8-enable-and-verify-the-firewall)
9. [Whitelist USB devices and start the USB watcher](#9-whitelist-usb-devices-and-start-the-usb-watcher)
10. [Run the script-based hardening](#10-run-the-script-based-hardening)
11. [Final verification](#11-final-verification)
12. [Physical disconnect — airgap the device](#12-physical-disconnect--airgap-the-device)
13. [Daily operations](#13-daily-operations)
14. [Recovery procedures](#14-recovery-procedures)
15. [Troubleshooting](#15-troubleshooting)
16. [Appendix — script quick reference](#appendix--script-quick-reference)

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
> with a user-approval click — see §5. Plan for this before starting.

### 1.2 What you need from the developer

An SD card containing the HX-Guardian bundle:

```
/Volumes/<SD_CARD>/hx-guardian/
├── app/
│   ├── backend/vendor/python/                 ← Python wheels (offline pip install)
│   ├── backend/vendor/installers/             ← Python .pkg installer
│   ├── frontend/dist/                         ← Pre-built React UI
│   ├── install.sh
│   └── launchd/
└── standards/
    ├── unified/
    │   └── com.hxguardian.unified.mobileconfig   ← single file, all policies
    ├── 800-53r5_high/                            ← individual profiles (optional / legacy)
    ├── scripts/
    └── airgap_readme.md                         ← this document
```

If any of these are missing, return the card to the developer — the target device
cannot reach the internet to fetch them.

### 1.3 Baseline choice

This runbook uses **NIST 800-53r5 High** throughout. To use a different baseline,
substitute `cisv8/` or `cis_lvl2/` for `800-53r5_high/` in every path below.

### 1.4 Touch ID policy

Touch ID is intentionally kept **enabled** for operator convenience. Three
baseline rules that would disable it are deliberately left failing — see
[§7.4 Touch ID exception](#74-touch-id-exception).

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
cp -R /Volumes/<SD_CARD_NAME>/hx-guardian ~/Documents/airgap/hx-guardian
cd ~/Documents/airgap/hx-guardian
```

> The launchd plists reference the repo path via
> `/Library/Application Support/hxguardian/` after install, so you can move the
> source tree later. Keep the repo in a stable location while you install.

---

## 3. Install HX-Guardian offline

### 3.1 Run the installer

```bash
sudo zsh app/install.sh
```

The installer performs all steps fully offline:

| Step | What it does |
|---|---|
| 0 | Checks for Python 3 — if missing, runs the bundled `.pkg` silently |
| 1 | Installs Python dependencies from `vendor/python/` wheels with `--no-index` |
| 2 | Copies the app into `/Library/Application Support/hxguardian/` and creates `data/` |
| 3 | Creates `/var/run/hxg/` (socket) and log files in `/Library/Logs/` |
| 4 | Installs three **LaunchDaemons** — runner (root), server (admin user), USB watcher (root) |
| 5 | Enforces password policy locally via `pwpolicy` (min 15 chars, complexity, history, 60-day expiry, lockout). All existing non-system local accounts are flagged to change password on next login. |

### 3.2 Admin password policy — what to expect

`install.sh` step 5 writes a site-wide `pwpolicy` covering every local account
(min 15 chars, upper+lower+digit+special, no simple sequences, no reuse of the
last 5, max age 60 days, 5-failures/15-min lockout, 35-day inactivity disable).

**Your own admin password is not force-changed by the installer.** The script
explicitly skips the currently logged-in installer user so the airgap device
does not lock you out on first logout. The password you used to run
`sudo zsh app/install.sh` keeps working.

**But you still need to meet the policy:**

| When | What happens |
|---|---|
| Right after install | Existing admin password continues to work unchanged |
| On next expiry (≤ 60 days) | macOS forces a change; the new password **must** meet every rule above |
| On any voluntary change | Full content rules enforced immediately |
| Compliance scans | `pwpolicy_*` scan scripts PASS — they check that the policy is present, not each account's password hash |

**Strongly recommended:** change your admin password voluntarily **now**, before
airgapping:

```bash
passwd
```

That confirms the policy is active (the system will reject a non-compliant new
password) and prevents being surprised at expiry with an offline device.

### 3.3 Confirm all three services are running

```bash
sudo launchctl list | grep hxguardian
# Expected:
#   com.hxguardian.runner
#   com.hxguardian.server
#   com.hxguardian.usbwatcher
```

All three are LaunchDaemons under `/Library/LaunchDaemons/`. The server plist
has `UserName` set to the admin user so the dashboard runs non-root; the other
two run as root.

---

## 4. Open the dashboard

### 4.1 Go to the dashboard

Open Safari and go to:

```
http://127.0.0.1:8000
```

The dashboard has **no startup token**. It opens immediately for anyone on
`127.0.0.1`. The server binds to loopback only — it is unreachable from the
network.

### 4.2 Verify the runner is connected

```bash
curl -s http://127.0.0.1:8000/api/health
# → {"status":"ok","runner_connected":true,"version":"1.0.0"}
```

The `/api/health` endpoint is public and takes no auth. If `runner_connected`
is `false`, jump to [§15 Troubleshooting](#15-troubleshooting).

### 4.3 Authentication model

- Read-only dashboard access is open on `127.0.0.1` — anyone logged into the
  Mac can browse scans, reports, and audit logs.
- Sensitive actions (apply a fix, change the USB whitelist, grant an exemption,
  disable 2FA, view the QR for an enrolled secret) require a **TOTP from 2FA**.
  The UI prompts for a 6-digit code; the backend issues a 10-minute
  `X-2FA-Token` that covers follow-up requests.
- **2FA is a single site-wide secret held by the admin** — not per-user. Only
  the admin enrolls and holds the authenticator app. Operators cannot (and
  should not) perform any gated action — those are admin-only.
- Physical possession of the device (airgap + FileVault + firmware password)
  is the primary perimeter; admin 2FA prevents an unattended-but-unlocked
  session from silently altering the compliance state.

Admin 2FA enrollment is covered in §7.4.

---

## 5. Deploy the unified MDM profile

HX-Guardian ships a single unified profile that bundles every policy this
runbook previously required as separate files.

**Profile file:** `standards/unified/com.hxguardian.unified.mobileconfig`
**Identifier:** `com.hxguardian.unified`

### 5.1 Install the profile (macOS Tahoe 26 and later)

`sudo profiles install -path …` is **blocked** on recent macOS — the command
returns without deploying and requires GUI approval. Use this flow instead:

1. In Finder, navigate to
   `~/Documents/airgap/hx-guardian/standards/unified/`.
2. **Double-click** `com.hxguardian.unified.mobileconfig`. macOS copies it into
   the pending-profiles queue and opens System Settings.
3. Go to **System Settings → General → VPN & Device Management** (on Tahoe
   it may appear under **Privacy & Security → Profiles**).
4. Select **HX-Guardian Unified** from the list → click **Install** → enter the
   admin password when prompted.
5. The profile is now deployed. It cannot be removed except by an admin.

### 5.2 Touch ID edit — before deploying

Before installing, confirm the profile allows Touch ID for unlock. Open the
unified `.mobileconfig` in a text editor and check that the
`com.apple.applicationaccess` payload either:

- does **not** contain `allowFingerprintForUnlock`, **or**
- has `<key>allowFingerprintForUnlock</key><true/>`.

If you see `<false/>`, change it to `<true/>` before Step 5.1.2. Otherwise
operators cannot unlock with Touch ID or authenticate `sudo` with a fingerprint.

### 5.3 What the unified profile enforces

The single file applies every policy this runbook used to deploy as separate
profiles:

| Area | Effect |
|---|---|
| FileVault 2 | Pre-requires FileVault (operator still enables via System Settings — §6) |
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

Password policy is **not** applied via the profile — it is enforced locally by
`install.sh` using `pwpolicy`. See §3.1 step 5.

### 5.4 Verify the profile is installed

From the dashboard: **MDM Profiles** page — `com.hxguardian.unified` shows a
green installed check. Or from the terminal:

```bash
profiles -P | grep hxguardian
# → HX-Guardian Unified (com.hxguardian.unified)
```

---

## 6. Enable FileVault (full-disk encryption)

> On macOS Tahoe, the MDM `ForceEnableInSetupAssistant` trigger is unreliable —
> enable FileVault **directly from System Settings**.

### 6.1 Turn on FileVault

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

### 6.2 Disable FileVault auto-login (already set by the unified profile)

The unified profile sets `DisableFDEAutoLogin`. If the profile is not yet
deployed, run:

```bash
sudo defaults write /Library/Preferences/com.apple.loginwindow DisableFDEAutoLogin -bool true
```

### 6.3 Verify FileVault

```bash
sudo fdesetup status
# → FileVault is On.
```

On the dashboard, scan both rules and confirm PASS:

```bash
sudo zsh standards/scripts/scan/system_settings_filevault_enforce.sh
sudo zsh standards/scripts/scan/os_filevault_autologin_disable.sh
```

| Result | Remediation |
|---|---|
| `system_settings_filevault_enforce` FAIL | Re-run §6.1 in System Settings |
| `os_filevault_autologin_disable` FAIL | Run the `defaults write` command in §6.2 |

---

## 7. Create operator users and set up 2FA

**Role split — read first:**

| Role | Accounts | Dashboard access | 2FA | Can apply fixes / change whitelist / grant exemptions? |
|---|---|---|---|---|
| Admin | 1 (you) | Read + gated actions | **Yes — site-wide secret on admin's phone** | Yes |
| Operator | 1..n | Read only | No | No |

2FA is a **singleton** in HX-Guardian — there is one secret for the whole
dashboard, not one per user. The admin holds it. Operators never enroll 2FA
and never hold the authenticator app.

### 7.1 Create operator accounts manually

Operators are standard (non-admin) macOS users. Create them via System Settings
while still logged in as admin:

1. **System Settings → Users & Groups → Add Account…** (admin password required).
2. **New User** → **Standard**.
3. Enter a full name (e.g. "Operator 01"), account name (e.g. `operator01`),
   and a temporary password.
4. Click **Create User**. Repeat for each operator.

> `install.sh` already enforces the compliant password policy via `pwpolicy`
> and flagged all existing local accounts to change password on next login.
> New accounts inherit the same policy automatically.

### 7.2 For each operator: first login and password change

1. Log out of the admin account.
2. Log in as each operator with the temporary password.
3. macOS will **force a password change** — set a password that satisfies the
   policy (min 15 chars, mixed case, digit, special character, not a reuse of
   the last 5).
4. Log out and return to the admin account.

### 7.3 Touch ID enrollment (admin + each operator)

Touch ID is the device's second perimeter (unlock + sudo prompt) and is
available to every account. Enroll it once per account:

1. Log in as the account (admin or operator in turn).
2. **System Settings → Touch ID & Password → Add a Fingerprint**.
3. Enroll at least two fingers (primary + backup).
4. Test: lock the screen and unlock with Touch ID; run `sudo -v` in Terminal
   (admin only, operators don't have sudo) and confirm the Touch ID prompt
   appears.

### 7.4 Admin enrolls 2FA (singleton TOTP) — one-time

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

### 7.5 Touch ID exception — intentional compliance FAIL

Three baseline rules deliberately show **FAIL** in compliance reports.
Do **not** run these fix scripts.

| Rule | Reason skipped |
|---|---|
| `system_settings_touchid_unlock_disable` | Operators use Touch ID for unlock |
| `system_settings_touch_id_settings_disable` | Operators manage their own fingerprints |
| `os_touchid_prompt_disable` | Enrollment prompt needed for new operators |

---

## 8. Enable and verify the firewall

The unified profile enables the application firewall + stealth mode. The
default-deny pf rule must be added manually (§8.3).

### 8.1 Manual fallback — application firewall via CLI

Only run this if the unified profile is not yet deployed:

```bash
sudo /usr/libexec/ApplicationFirewall/socketfilterfw --setglobalstate on
sudo /usr/libexec/ApplicationFirewall/socketfilterfw --setstealthmode on
# Optional — most restrictive; blocks all incoming connections
sudo /usr/libexec/ApplicationFirewall/socketfilterfw --setblockall on
```

### 8.2 Verify application firewall

```bash
profiles -P | grep -i hxguardian
sudo /usr/libexec/ApplicationFirewall/socketfilterfw --getglobalstate
# → Firewall is enabled.
sudo /usr/libexec/ApplicationFirewall/socketfilterfw --getstealthmode
# → Stealth mode enabled.
```

### 8.3 Add the default-deny pf rule

`os_firewall_default_deny_require.sh` checks for a `block drop in all` rule in
pf. There is no fix script for this — it must be added manually.

> **Before adding this rule**, confirm `/etc/pf.conf` already contains
> `pass on lo0` and `pass out all`. Without those, the HX-Guardian dashboard on
> `127.0.0.1:8000` and local services will stop working.

```bash
# Review existing rules first
sudo pfctl -sr

# Back up and append the block rule (add before any final pass lines)
sudo cp /etc/pf.conf /etc/pf.conf.bak
sudo sh -c 'echo "block drop in all" >> /etc/pf.conf'

# Reload and enable pf
sudo pfctl -f /etc/pf.conf
sudo pfctl -e

# Verify
sudo pfctl -sr | grep "block drop"
```

### 8.4 Run firewall scans

```bash
sudo zsh standards/scripts/scan/system_settings_firewall_enable.sh
sudo zsh standards/scripts/scan/system_settings_firewall_stealth_mode_enable.sh
sudo zsh standards/scripts/scan/os_firewall_default_deny_require.sh
```

All three should return PASS.

| Result | Remediation |
|---|---|
| `system_settings_firewall_enable` FAIL | Re-deploy the unified profile or run §8.1 |
| `system_settings_firewall_stealth_mode_enable` FAIL | Re-deploy the profile or run `--setstealthmode on` |
| `os_firewall_default_deny_require` FAIL | Apply the pf rule in §8.3 |

---

## 9. Whitelist USB devices and start the USB watcher

### 9.1 USB Restricted Mode

**What it does:** When enabled, macOS requires the device to be unlocked before
a newly connected USB accessory can communicate. If the device has been locked
for more than one hour, any new USB connection is blocked until the operator
authenticates.

**Already set by the unified profile.** Verify:

```bash
sudo zsh standards/scripts/scan/system_settings_usb_restricted_mode.sh
# → PASS
```

### 9.2 Whitelist known-good USB devices

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

### 9.3 Grant Full Disk Access to the USB watcher

The USB watcher runs as a LaunchDaemon and reads the SQLite database under
`/Library/Application Support/hxguardian/data/`. On macOS Tahoe the watcher
binary needs Full Disk Access:

1. **System Settings → Privacy & Security → Full Disk Access**.
2. Click `+` → add `/Library/Application Support/hxguardian/bin/run-hxg-usbwatcher`
   (press **Cmd+Shift+G** in the file picker to type the path directly).
3. Toggle it on.

Without this, the watcher fails with `[Errno 1] Operation not permitted` and
nothing is ejected.

### 9.4 The USB watcher is already installed

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

**Control the daemon (modern `launchctl` syntax):**

```bash
# Stop
sudo launchctl bootout   system /Library/LaunchDaemons/com.hxguardian.usbwatcher.plist
# Start
sudo launchctl bootstrap system /Library/LaunchDaemons/com.hxguardian.usbwatcher.plist
# Status
launchctl print system/com.hxguardian.usbwatcher | head
# Live log
tail -f /var/log/hxguardian_usb.log
```

### 9.5 Test the watcher

1. Insert an **unknown** USB stick. Within 5 seconds you should see a macOS
   notification, and the volume should be ejected.
2. The **Connections** page shows an entry in **UNAUTHORIZED USB EVENTS**.
3. Insert a **whitelisted** device — no notification, no ejection, shows green.

---

## 10. Run the script-based hardening

Each scan script checks compliance; each fix script remediates. Run scans first,
then the corresponding fix script for any FAIL.

Exit codes: `0` = PASS / SUCCESS, `1` = FAIL, `2` = NOT_APPLICABLE, `3` = ERROR.

Pattern:

```bash
sudo zsh standards/scripts/scan/<rule>.sh    # check — outputs JSON
sudo zsh standards/scripts/fix/<rule>.sh     # remediate
```

The Dashboard is the easier path: **Rules** page → filter by FAIL → click
**Apply Fix** on each. The admin's TOTP is required for the first fix in a
session; the issued `X-2FA-Token` covers further actions for 10 minutes.
Operators cannot apply fixes.

### 10.1 iCloud — MDM only (14 rules)

All iCloud rules are scan-only. Remediation is via the unified profile already
deployed in §5. No fix scripts exist; if a scan shows FAIL, re-deploy the
unified profile.

### 10.2 Screen lock

| Script | Purpose |
|---|---|
| `scan/system_settings_screensaver_timeout_enforce.sh` | Idle timeout ≤ 10 min |
| `scan/system_settings_screensaver_password_enforce.sh` | Password required to unlock |
| `scan/system_settings_screensaver_ask_for_password_delay_enforce.sh` | No delay before lock |
| `scan/os_screensaver_loginwindow_enforce.sh` | Loginwindow screensaver set |

### 10.3 Login window & guest account

| Script | Purpose |
|---|---|
| `scan/system_settings_guest_account_disable.sh` | Guest account off |
| `scan/os_guest_folder_removed.sh` + `fix/…` | Remove `/Users/Guest` |
| `scan/system_settings_guest_access_smb_disable.sh` + `fix/…` | Disable SMB guest |
| `scan/system_settings_automatic_login_disable.sh` | Auto-login disabled |
| `scan/system_settings_loginwindow_prompt_username_password_enforce.sh` | Show username + password fields |
| `scan/os_loginwindow_adminhostinfo_disabled.sh` | No host info at login window |

### 10.4 System Integrity Protection (SIP)

| Script | Purpose |
|---|---|
| `scan/os_sip_enable.sh` | Verify SIP on |
| `fix/os_sip_enable.sh` | Enable SIP |

> SIP changes require Recovery Mode. If the fix fails, reboot to Recovery
> (**hold Power** on Apple Silicon; **Cmd+R** on Intel) and run `csrutil enable`.

### 10.5 Gatekeeper

| Script | Purpose |
|---|---|
| `scan/os_gatekeeper_enable.sh` | Gatekeeper on |
| `scan/system_settings_gatekeeper_identified_developers_allowed.sh` | Allow identified devs |
| `scan/system_settings_gatekeeper_override_disallow.sh` | Block right-click overrides |

### 10.6 Siri & Dictation

`scan/system_settings_siri_disable.sh`, `scan/system_settings_siri_settings_disable.sh`,
`scan/os_siri_prompt_disable.sh`, `scan/os_dictation_disable.sh`,
`scan/system_settings_improve_siri_dictation_disable.sh`.

### 10.7 AirDrop

`scan/os_airdrop_disable.sh` (scan only — MDM via unified profile).

### 10.8 Bluetooth

| Script | Purpose |
|---|---|
| `scan/system_settings_bluetooth_disable.sh` | Bluetooth off (scan only) |
| `scan/system_settings_bluetooth_sharing_disable.sh` + `fix/…` | Disable Bluetooth sharing |

> On 800-53r5 High the unified profile leaves Bluetooth togglable; disable
> manually: **System Settings → Bluetooth → Turn Bluetooth Off**.

### 10.9 Sharing services

Pairs of `scan/fix` for: Screen Sharing, SSH (Remote Login), SMB, Remote
Management, Printer Sharing, Media Sharing.

### 10.10 Secure Boot & firmware password

Scan-only — remediation requires manual steps in Recovery Mode.

| Script | Checks |
|---|---|
| `scan/os_secure_boot_verify.sh` | Secure Boot set to Full Security |
| `scan/os_firmware_password_require.sh` | EFI / Startup Security password set |

**Set firmware password manually:**

1. Reboot to Recovery Mode (**hold Power** / **Cmd+R**).
2. Utilities → Startup Security Utility.
3. Set to **Full Security** and enable password requirement.
4. Apple Silicon: controlled by Activation Lock and MDM enrollment.

### 10.11 Password policy

Already applied by `install.sh` via `pwpolicy` (§3.1 step 5). 7 scan scripts
verify compliance (min length, lockout, history, lifetime, complexity).
Fix scripts exist for `account_inactivity_enforce` and `minimum_lifetime_enforce`
if they show FAIL.

> **Admin password:** the installer intentionally does not force a change for
> the logged-in installer user. See §3.2 for the implications and the
> recommended voluntary `passwd` step before airgapping.

### 10.12 Audit logging

13 scan scripts + 3 fix scripts. Run all audit fixes in one pass:

```bash
for f in standards/scripts/fix/audit_*.sh; do sudo zsh "$f"; done
```

---

## 11. Final verification

### 11.1 Option A — Dashboard (recommended)

1. Open `http://127.0.0.1:8000`.
2. Dashboard → **Run Full Scan**.
3. Review compliance score and per-category charts.
4. Re-scan or re-fix any individual rule from the **Rules** page (TOTP prompt
   on fixes).

### 11.2 Option B — Command line

```bash
sudo zsh standards/800-53r5_high/800-53r5_high_compliance.sh
```

### 11.3 Expected state before airgapping

- All rules **PASS** except the **3 Touch ID exceptions** (intentional FAIL).
- iCloud rules: **PASS** (enforced via unified profile).
- Firmware / Secure Boot: **PASS** (set manually in Recovery Mode).
- Password policy rules: **PASS** (set by `install.sh`).

---

## 12. Physical disconnect — airgap the device

> Only proceed once §11 is green.

1. Forget all saved Wi-Fi networks:
   `System Settings → Wi-Fi → (each network) → Forget`
2. Turn off Wi-Fi: `System Settings → Wi-Fi → off`
3. Disable Bluetooth if not needed: `System Settings → Bluetooth → off`
4. If Ethernet is present: **physically remove** the adapter / cable.
5. Final check — confirm no active interfaces:

```bash
ifconfig | grep 'inet ' | grep -v 127.0.0.1
sudo lsof -i | grep ESTABLISHED
```

Both commands should return no output.

**The device is now airgapped.** Daily operations continue in §13.

---

## 13. Daily operations

### 13.1 Open the dashboard

```
http://127.0.0.1:8000
```

No token, no login screen. 2FA prompts appear only when an operator attempts
a gated action (apply fix, change whitelist, grant exemption, disable 2FA).

### 13.2 Service management (modern `launchctl`)

```bash
# Status
sudo launchctl print system/com.hxguardian.server  | head
sudo launchctl print system/com.hxguardian.runner  | head
sudo launchctl print system/com.hxguardian.usbwatcher | head

# Logs
tail -f /Library/Logs/hxguardian-server.log       # server
tail -f /Library/Logs/hxguardian-runner.log       # runner
tail -f /var/log/hxguardian_usb.log               # USB watcher

# Restart a service (kickstart re-execs in place)
sudo launchctl kickstart -k system/com.hxguardian.server
sudo launchctl kickstart -k system/com.hxguardian.runner
sudo launchctl kickstart -k system/com.hxguardian.usbwatcher

# Stop
sudo launchctl bootout system /Library/LaunchDaemons/com.hxguardian.server.plist
sudo launchctl bootout system /Library/LaunchDaemons/com.hxguardian.runner.plist
sudo launchctl bootout system /Library/LaunchDaemons/com.hxguardian.usbwatcher.plist

# Start
sudo launchctl bootstrap system /Library/LaunchDaemons/com.hxguardian.runner.plist
sudo launchctl bootstrap system /Library/LaunchDaemons/com.hxguardian.server.plist
sudo launchctl bootstrap system /Library/LaunchDaemons/com.hxguardian.usbwatcher.plist
```

### 13.3 Adding a USB device to the whitelist (post-airgap)

Whitelist changes are admin-only.

1. Log in as the **admin** (operators cannot complete this flow — gated on
   admin 2FA).
2. Connect the new USB device.
3. Dashboard → **Connections** → locate the device in **USB DEVICES**.
4. Click **Add to Whitelist**, fill in the purpose / owner note, save.
5. Enter the 6-digit TOTP from the **admin's** authenticator app.
6. The USB watcher picks up the change within 30 seconds — no restart needed.
7. The action is recorded in the **Audit Log** under the admin account.

### 13.4 Scheduling recurring scans

Dashboard → **Schedule** → configure a cron expression
(e.g. daily 02:00: `0 2 * * *`). The runner executes the scan session as root
and results appear in **Scan History**.

### 13.5 Generating reports

Dashboard → **Reports** → choose **HTML** (printable) or **CSV** (for archival).
Reports include the compliance score, per-rule status, audit-log excerpt, and
exemptions list.

### 13.6 Granting / revoking an exemption

Admin-only. Dashboard → **Exemptions** → **Grant Exemption** → enter rule ID,
reason, and expiry date. Admin TOTP prompt appears. Exempted rules are counted
as PASS in compliance reports but remain visible in the Rules list with an
**Exempt** badge.

---

## 14. Recovery procedures

### 14.1 Reset an operator password

Operators are standard users, so the admin resets from an admin shell:

```bash
sudo passwd operator01
```

The password policy installed in §3.1 still applies. If the operator is locked
out because of failed attempts, see §14.2.

**If the admin password itself is lost:**

1. Reboot into Recovery Mode (**hold Power** / **Cmd+R**).
2. Utilities → Terminal.
3. `resetpassword` — pick the admin user, set a new password.
4. Reboot normally.

> If FileVault is on and **both** the admin password and the PRK (§6.1) are lost,
> the data is unrecoverable by design.

### 14.2 Unlock a locked-out account

If the password-policy lockout triggers, unlock from an admin shell:

```bash
sudo pwpolicy -u operator01 -clearaccountpolicies
```

Then re-apply the site-wide policy so the account remains compliant:

```bash
sudo zsh app/install.sh     # idempotent — re-runs pwpolicy step
```

### 14.3 Re-enroll a Touch ID fingerprint

Only the owning operator can enroll or remove their own fingerprints:

1. Log in as the operator.
2. **System Settings → Touch ID & Password**.
3. Remove the old fingerprint (trash icon) and add a new one.

### 14.4 Reset admin 2FA (lost phone)

Because 2FA is a single site-wide secret held only by the admin, losing the
admin's phone locks the whole dashboard out of gated actions (fix / whitelist /
exemption). There are no backup / scratch codes — recovery is via SQLite.

1. Log in as the admin on the Mac (macOS account password still works; the
   lockout is dashboard-only).
2. Wipe the singleton 2FA row — note it is **`two_factor_config`**, not plural:
   ```bash
   sudo sqlite3 "/Library/Application Support/hxguardian/data/hxguardian.db" \
       "DELETE FROM two_factor_config;"
   sudo launchctl kickstart -k system/com.hxguardian.server
   ```
3. The dashboard is now in the "2FA not configured" state — gated actions are
   temporarily unguarded. Immediately re-enroll via §7.4 on the replacement
   phone before doing anything else.
4. The SQLite delete and the re-enrollment are both recorded in the Audit Log.

### 14.5 Restore the pf configuration

If the dashboard becomes unreachable after §8.3:

```bash
sudo cp /etc/pf.conf.bak /etc/pf.conf
sudo pfctl -f /etc/pf.conf
```

### 14.6 Reinstall HX-Guardian from SD card

Bring the original SD card (or a fresh one from the developer), copy the bundle
onto the device, and re-run `sudo zsh app/install.sh`. The installer is
idempotent — it upgrades in place and preserves
`/Library/Application Support/hxguardian/data/` (DB + reports).

---

## 15. Troubleshooting

**Dashboard not loading**
```bash
curl -s http://127.0.0.1:8000/api/health
# Should return: {"status":"ok","runner_connected":...}
```

**`runner_connected: false` in health check**
```bash
sudo launchctl print system/com.hxguardian.runner | head
# If not loaded, start it:
sudo launchctl bootstrap system /Library/LaunchDaemons/com.hxguardian.runner.plist
```

**Scan returns ERROR for all rules**
- The runner must be running as root. Check `/Library/Logs/hxguardian-runner.log`.
- Verify the socket exists: `ls -la /var/run/hxg/runner.sock`.
- The **Rule Detail** page shows the full server error for a single-rule scan.

**Scan results not updating after "Run Full Scan"**
- The frontend polls session status and reloads automatically when the scan
  finishes. Wait for the **Scanning…** button to return to normal, then reload
  the Rules page.
- If results never update, check that the runner is connected (`/api/health`).

**MDM rules still showing `MDM_REQUIRED` after deploying the unified profile**
- MDM-only rules are verified by whether the profile is installed. Deploying
  the profile does not automatically update past scan results — run a new
  full scan.
- If the profile install was blocked, check
  **System Settings → General → VPN & Device Management** for an unapproved
  pending profile.

**`profiles install` on the CLI does nothing (Tahoe)**
- Expected. Use the Finder + System Settings flow in §5.1 instead.

**USB watcher: `[Errno 1] Operation not permitted`**
- The watcher binary needs Full Disk Access.
  **System Settings → Privacy & Security → Full Disk Access** → add
  `/Library/Application Support/hxguardian/bin/run-hxg-usbwatcher` → toggle on →
  `sudo launchctl kickstart -k system/com.hxguardian.usbwatcher`.

**USB watcher: device detected but not ejected / not re-ejected after replug**
```bash
tail -f /var/log/hxguardian_usb.log
```
- `Could not eject` → `diskutil eject` failed; verify Full Disk Access.
- No log entry at all → watcher is not running; `sudo launchctl bootstrap system /Library/LaunchDaemons/com.hxguardian.usbwatcher.plist`.
- Device shows **Whitelisted** → remove the whitelist entry to re-enable
  enforcement.

**2FA prompt appears but every code from the admin's phone is rejected**
- Phone clock is out of sync with the device. Re-sync the phone's time
  (automatic time zone on). TOTP tolerates roughly ±30 s drift.
- Last-resort reset (admin's phone lost / unrecoverable): §14.4.

**`ModuleNotFoundError` on server startup**
```bash
# Re-runs pip from the bundled vendor wheels
sudo zsh app/install.sh
```

**Permission denied on socket**
```bash
sudo rm -rf /var/run/hxg
sudo mkdir -p /var/run/hxg
sudo chown root:admin /var/run/hxg
sudo chmod 770 /var/run/hxg
sudo launchctl kickstart -k system/com.hxguardian.runner
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
| `app/backend/usb_watcher.py` | The daemon itself (launched by the plist) |
| `/Library/LaunchDaemons/com.hxguardian.usbwatcher.plist` | Installed plist |
| `/var/log/hxguardian_usb.log` | Daemon runtime log |

### Key paths after install

| Path | Contents |
|---|---|
| `/Library/Application Support/hxguardian/` | Installed app (code + data + bin) |
| `/Library/Application Support/hxguardian/data/hxguardian.db` | SQLite DB (scans, audit, whitelist, 2FA) |
| `/Library/LaunchDaemons/com.hxguardian.runner.plist` | Runner (root) |
| `/Library/LaunchDaemons/com.hxguardian.server.plist` | Server (admin user) |
| `/Library/LaunchDaemons/com.hxguardian.usbwatcher.plist` | USB watcher (root) |
| `/Library/Logs/hxguardian-{server,runner}.log` | Service logs |
| `/var/log/hxguardian_usb.log` | USB watcher log |
| `/var/run/hxg/runner.sock` | Unix socket between server and runner |

---

## Uninstall (rarely used)

```bash
# Stop and remove all three LaunchDaemons
sudo launchctl bootout system /Library/LaunchDaemons/com.hxguardian.server.plist
sudo launchctl bootout system /Library/LaunchDaemons/com.hxguardian.runner.plist
sudo launchctl bootout system /Library/LaunchDaemons/com.hxguardian.usbwatcher.plist
sudo rm /Library/LaunchDaemons/com.hxguardian.server.plist
sudo rm /Library/LaunchDaemons/com.hxguardian.runner.plist
sudo rm /Library/LaunchDaemons/com.hxguardian.usbwatcher.plist

# Remove socket directory
sudo rm -rf /var/run/hxg

# Remove the unified MDM profile
# System Settings → General → VPN & Device Management → HX-Guardian Unified → Remove

# Optionally remove installed app + data (scan history, audit log, 2FA secrets)
sudo rm -rf "/Library/Application Support/hxguardian"
```
