# HX-Guardian — Airgap Device Admin & Operator Guide

End-to-end runbook for hardening a macOS device for airgapped signing operations
and for day-to-day operation once the device is disconnected.

> **Audience:** Airgap device **admins** (who perform the initial setup and
> hardening) and **operators** (who use the device day-to-day). Developers who
> build or modify the dashboard should read
> [../app/app_readme.md](../app/app_readme.md).

> **Network policy:** The airgap target device **never needs internet access**.
> All software — pre-compiled binaries, the dashboard, the unified MDM profile,
> hardening scripts — arrives on the SD card prepared by the developer.
> TOTP for the dashboard's 2FA works fully offline (authenticator apps are
> time-based, not network-based).

---

## Table of Contents

1. [Prerequisites](#1-prerequisites)
2. [Receiving the SD card bundle](#2-receiving-the-sd-card-bundle)
3. [Install HX-Guardian offline](#3-install-hx-guardian-offline)
4. [Apply bulk fixes and exemptions](#4-apply-bulk-fixes-and-exemptions)
5. [Open the dashboard](#5-open-the-dashboard)
6. [Deploy the unified MDM profile](#6-deploy-the-unified-mdm-profile)
7. [Enable FileVault](#7-enable-filevault-full-disk-encryption)
8. [Create operator users and set up 2FA](#8-create-operator-users-and-set-up-2fa)
9. [Enable and verify the firewall](#9-enable-and-verify-the-firewall)
10. [Whitelist USB devices and start the USB watcher](#10-whitelist-usb-devices-and-start-the-usb-watcher)
11. [Run any remaining manual hardening](#11-run-any-remaining-manual-hardening)
12. [Final verification](#12-final-verification)
13. [Physical disconnect — airgap the device](#13-physical-disconnect--airgap-the-device)
14. [Daily operations](#14-daily-operations)
15. [Recovery procedures](#15-recovery-procedures)
16. [Troubleshooting](#16-troubleshooting)
17. [Appendix — script quick reference](#appendix--script-quick-reference)

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
> with a user-approval click — see §6. Plan for this before starting.

### 1.2 What you need from the developer

An SD card containing the HX-Guardian install bundle (produced by `prepare_sd_card.sh`):

```
/Volumes/<SD_CARD>/hxg-install/
├── app/
│   ├── dist/
│   │   ├── hxg-server/          ← pre-compiled web server binary (PyInstaller onedir)
│   │   ├── hxg-runner/          ← pre-compiled runner binary
│   │   └── hxg-usb-watcher/     ← pre-compiled USB watcher binary
│   ├── launchd/                 ← LaunchDaemon plists
│   ├── vendor/bin/xmllint       ← standalone XML parser (~200 KB, deployed by install.sh)
│   ├── install.sh               ← main installer
│   ├── start.sh / stop.sh / restart.sh / update.sh
│   └── rules_setup.sh           ← post-install bulk fix + exemption script
└── standards/
    ├── unified/
    │   └── com.hxguardian.unified.mobileconfig   ← single file, all policies
    ├── launchd/                 ← USB watcher plist
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
§8.5.

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

> After `install.sh` completes, everything is deployed to
> `/Library/Application Support/hxguardian/`. You can optionally remove
> `~/hxg-install` once installation and `rules_setup.sh` have finished.

---

## 3. Install HX-Guardian offline

### 3.1 Run the installer

```bash
sudo zsh ~/hxg-install/app/install.sh
```

The installer performs all steps fully offline — no Python, pip, or internet required:

| Step | What it does |
|---|---|
| 0 | Removes any existing HX-Guardian services and binaries |
| 1 | Deploys pre-compiled binaries from `app/dist/` to `/Library/Application Support/hxguardian/bin/` |
| 2 | Copies the standards tree (scripts + manifest + profiles) to `/Library/Application Support/hxguardian/standards/` |
| 2b | Deploys the bundled `xmllint` binary to `/Library/Application Support/hxguardian/bin/xmllint` and sed-patches the 19 scan/fix scripts that need it. This removes the dependency on Xcode Command Line Tools — airgap devices do **not** need CLT installed. |
| 3 | Creates `/var/run/hxg/` (Unix socket directory) and log files in `/Library/Logs/` |
| 4 | Installs three **LaunchDaemons** — runner (root), server (admin user), USB watcher (root) — and starts all three |
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

### 2FA prompt

If 2FA has been configured (see §8.4), the script prompts for a 6-digit TOTP
code once at the start. It automatically re-prompts before the 10-minute
session window expires if the run takes longer.

---

## 5. Open the dashboard

### 5.1 Go to the dashboard

Open Safari and go to:

```
http://127.0.0.1:8000
```

The dashboard has **no startup token**. It opens immediately for anyone on
`127.0.0.1`. The server binds to loopback only — it is unreachable from the
network.

### 5.2 Verify the runner is connected

```bash
curl -s http://127.0.0.1:8000/api/health
# → {"status":"ok","runner_connected":true,"version":"1.0.0"}
```

The `/api/health` endpoint is public and takes no auth. If `runner_connected`
is `false`, jump to [§16 Troubleshooting](#16-troubleshooting).

### 5.3 Authentication model

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

Admin 2FA enrollment is covered in §8.4.

---

## 6. Deploy the unified MDM profile

HX-Guardian ships a single unified profile that bundles every policy this
runbook previously required as separate files.

**Profile file:** `standards/unified/com.hxguardian.unified.mobileconfig`
**Identifier:** `com.hxguardian.unified`

### 6.1 Install the profile (macOS Tahoe 26 and later)

`sudo profiles install -path …` is **blocked** on recent macOS — the command
returns without deploying and requires GUI approval. Use this flow instead:

1. In Finder, navigate to
   `/Library/Application Support/hxguardian/standards/unified/`.
2. **Double-click** `com.hxguardian.unified.mobileconfig`. macOS copies it into
   the pending-profiles queue and opens System Settings.
3. Go to **System Settings → General → VPN & Device Management** (on Tahoe
   it may appear under **Privacy & Security → Profiles**).
4. Select **HX-Guardian Unified** from the list → click **Install** → enter the
   admin password when prompted.
5. The profile is now deployed. It cannot be removed except by an admin.

### 6.2 Touch ID edit — before deploying

Before installing, confirm the profile allows Touch ID for unlock. Open the
unified `.mobileconfig` in a text editor and check that the
`com.apple.applicationaccess` payload either:

- does **not** contain `allowFingerprintForUnlock`, **or**
- has `<key>allowFingerprintForUnlock</key><true/>`.

If you see `<false/>`, change it to `<true/>` before Step 5.1.2. Otherwise
operators cannot unlock with Touch ID or authenticate `sudo` with a fingerprint.

### 6.3 What the unified profile enforces

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

Password policy is **not** applied via the profile — it is enforced locally by
`install.sh` using `pwpolicy`. See §3.1 step 5.

### 6.4 Verify the profile is installed

From the dashboard: **MDM Profiles** page — `com.hxguardian.unified` shows a
green installed check. Or from the terminal:

```bash
profiles -P | grep hxguardian
# → HX-Guardian Unified (com.hxguardian.unified)
```

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

### 7.2 Disable FileVault auto-login (already set by the unified profile)

The unified profile sets `DisableFDEAutoLogin`. If the profile is not yet
deployed, run:

```bash
sudo defaults write /Library/Preferences/com.apple.loginwindow DisableFDEAutoLogin -bool true
```

### 7.3 Verify FileVault

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
| `system_settings_filevault_enforce` FAIL | Re-run §7.1 in System Settings |
| `os_filevault_autologin_disable` FAIL | Run the `defaults write` command in §7.2 |

---

## 8. Create operator users and set up 2FA

**Role split — read first:**

| Role | Accounts | Dashboard access | 2FA | Can apply fixes / change whitelist / grant exemptions? |
|---|---|---|---|---|
| Admin | 1 (you) | Read + gated actions | **Yes — site-wide secret on admin's phone** | Yes |
| Operator | 1..n | Read only | No | No |

2FA is a **singleton** in HX-Guardian — there is one secret for the whole
dashboard, not one per user. The admin holds it. Operators never enroll 2FA
and never hold the authenticator app.

### 8.1 Create operator accounts manually

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

### 8.2 For each operator: first login and password change

1. Log out of the admin account.
2. Log in as each operator with the temporary password.
3. macOS will **force a password change** — set a password that satisfies the
   policy (min 15 chars, mixed case, digit, special character, not a reuse of
   the last 5).
4. Log out and return to the admin account.

### 8.3 Touch ID enrollment (admin + each operator)

Touch ID is the device's second perimeter (unlock + sudo prompt) and is
available to every account. Enroll it once per account:

1. Log in as the account (admin or operator in turn).
2. **System Settings → Touch ID & Password → Add a Fingerprint**.
3. Enroll at least two fingers (primary + backup).
4. Test: lock the screen and unlock with Touch ID; run `sudo -v` in Terminal
   (admin only, operators don't have sudo) and confirm the Touch ID prompt
   appears.

### 8.4 Admin enrolls 2FA (singleton TOTP) — one-time

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

### 8.5 Touch ID exception — permanently exempted

Three baseline rules are permanently **EXEMPT** (not FAIL) — `rules_setup.sh`
creates these exemptions automatically in §4. Do **not** run their fix scripts.

| Rule | Reason |
|---|---|
| `system_settings_touchid_unlock_disable` | Operators use Touch ID for unlock |
| `system_settings_touch_id_settings_disable` | Operators manage their own fingerprints |
| `os_touchid_prompt_disable` | Enrollment prompt needed for new operators |

These rules show an **Exempt** badge in the dashboard and are excluded from the
compliance score — they do not drag down the percentage.

---

## 9. Enable and verify the firewall

The unified profile enables the application firewall + stealth mode. The
default-deny pf rule must be added manually (§9.3).

### 9.1 Manual fallback — application firewall via CLI

Only run this if the unified profile is not yet deployed:

```bash
sudo /usr/libexec/ApplicationFirewall/socketfilterfw --setglobalstate on
sudo /usr/libexec/ApplicationFirewall/socketfilterfw --setstealthmode on
# Optional — most restrictive; blocks all incoming connections
sudo /usr/libexec/ApplicationFirewall/socketfilterfw --setblockall on
```

### 9.2 Verify application firewall

```bash
profiles -P | grep -i hxguardian
sudo /usr/libexec/ApplicationFirewall/socketfilterfw --getglobalstate
# → Firewall is enabled.
sudo /usr/libexec/ApplicationFirewall/socketfilterfw --getstealthmode
# → Stealth mode enabled.
```

### 9.3 Add the default-deny pf rule

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

### 9.4 Run firewall scans

```bash
sudo zsh standards/scripts/scan/system_settings_firewall_enable.sh
sudo zsh standards/scripts/scan/system_settings_firewall_stealth_mode_enable.sh
sudo zsh standards/scripts/scan/os_firewall_default_deny_require.sh
```

All three should return PASS.

| Result | Remediation |
|---|---|
| `system_settings_firewall_enable` FAIL | Re-deploy the unified profile or run §9.1 |
| `system_settings_firewall_stealth_mode_enable` FAIL | Re-deploy the profile or run `--setstealthmode on` |
| `os_firewall_default_deny_require` FAIL | Apply the pf rule in §9.3 |

---

## 10. Whitelist USB devices and start the USB watcher

### 10.1 USB Restricted Mode

**What it does:** When enabled, macOS requires the device to be unlocked before
a newly connected USB accessory can communicate. If the device has been locked
for more than one hour, any new USB connection is blocked until the operator
authenticates.

**Already set by the unified profile.** Verify:

```bash
sudo zsh standards/scripts/scan/system_settings_usb_restricted_mode.sh
# → PASS
```

### 10.2 Whitelist known-good USB devices

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

### 10.3 Grant Full Disk Access to the USB watcher

The USB watcher runs as a LaunchDaemon and reads the SQLite database under
`/Library/Application Support/hxguardian/data/`. On macOS Tahoe the watcher
binary needs Full Disk Access:

1. **System Settings → Privacy & Security → Full Disk Access**.
2. Click `+` → add `/Library/Application Support/hxguardian/bin/run-hxg-usbwatcher`
   (press **Cmd+Shift+G** in the file picker to type the path directly).
3. Toggle it on.

Without this, the watcher fails with `[Errno 1] Operation not permitted` and
nothing is ejected.

### 10.4 The USB watcher is already installed

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

### 10.5 Test the watcher

1. Insert an **unknown** USB stick. Within 5 seconds you should see a macOS
   notification, and the volume should be ejected.
2. The **Connections** page shows an entry in **UNAUTHORIZED USB EVENTS**.
3. Insert a **whitelisted** device — no notification, no ejection, shows green.

---

## 11. Run any remaining manual hardening

> **§4 (`rules_setup.sh`) handles the bulk of this automatically** — it applies
> all 100 scriptable fixes and creates all policy exemptions in one pass. This
> section covers the rules that require manual steps (pf firewall, SIP, Secure
> Boot, firmware password) that no fix script can automate.

The scan/fix pattern for any rule you want to check or re-run individually:

Exit codes: `0` = PASS / SUCCESS, `1` = FAIL, `2` = NOT_APPLICABLE, `3` = ERROR.

```bash
# Scripts are in the installed location after install.sh runs
SCRIPTS="/Library/Application Support/hxguardian/standards/scripts"
sudo zsh "$SCRIPTS/scan/<rule>.sh"    # check — outputs JSON
sudo zsh "$SCRIPTS/fix/<rule>.sh"     # remediate
```

The Dashboard is also available: **Rules** page → filter by FAIL → click
**Apply Fix** on each. The admin's TOTP is required for the first fix in a
session; the issued token covers further actions for 10 minutes.
Operators cannot apply fixes.

### 11.1 iCloud — MDM only (14 rules)

All iCloud rules are scan-only. Remediation is via the unified profile already
deployed in §6. No fix scripts exist; if a scan shows FAIL, re-deploy the
unified profile.

### 11.2 Screen lock

| Script | Purpose |
|---|---|
| `scan/system_settings_screensaver_timeout_enforce.sh` | Idle timeout ≤ 10 min |
| `scan/system_settings_screensaver_password_enforce.sh` | Password required to unlock |
| `scan/system_settings_screensaver_ask_for_password_delay_enforce.sh` | No delay before lock |
| `scan/os_screensaver_loginwindow_enforce.sh` | Loginwindow screensaver set |

### 11.3 Login window & guest account

| Script | Purpose |
|---|---|
| `scan/system_settings_guest_account_disable.sh` | Guest account off |
| `scan/os_guest_folder_removed.sh` + `fix/…` | Remove `/Users/Guest` |
| `scan/system_settings_guest_access_smb_disable.sh` + `fix/…` | Disable SMB guest |
| `scan/system_settings_automatic_login_disable.sh` | Auto-login disabled |
| `scan/system_settings_loginwindow_prompt_username_password_enforce.sh` | Show username + password fields |
| `scan/os_loginwindow_adminhostinfo_disabled.sh` | No host info at login window |

### 11.4 System Integrity Protection (SIP)

| Script | Purpose |
|---|---|
| `scan/os_sip_enable.sh` | Verify SIP on |
| `fix/os_sip_enable.sh` | Enable SIP |

> SIP changes require Recovery Mode. If the fix fails, reboot to Recovery
> (**hold Power** on Apple Silicon; **Cmd+R** on Intel) and run `csrutil enable`.

### 11.5 Gatekeeper

| Script | Purpose |
|---|---|
| `scan/os_gatekeeper_enable.sh` | Gatekeeper on |
| `scan/system_settings_gatekeeper_identified_developers_allowed.sh` | Allow identified devs |
| `scan/system_settings_gatekeeper_override_disallow.sh` | Block right-click overrides |

### 11.6 Siri & Dictation

`scan/system_settings_siri_disable.sh`, `scan/system_settings_siri_settings_disable.sh`,
`scan/os_siri_prompt_disable.sh`, `scan/os_dictation_disable.sh`,
`scan/system_settings_improve_siri_dictation_disable.sh`.

### 11.7 AirDrop

`scan/os_airdrop_disable.sh` (scan only — MDM via unified profile).

### 11.8 Bluetooth

| Script | Purpose |
|---|---|
| `scan/system_settings_bluetooth_disable.sh` | Bluetooth off (scan only) |
| `scan/system_settings_bluetooth_sharing_disable.sh` + `fix/…` | Disable Bluetooth sharing |

> On 800-53r5 High the unified profile leaves Bluetooth togglable; disable
> manually: **System Settings → Bluetooth → Turn Bluetooth Off**.

### 11.9 Sharing services

Pairs of `scan/fix` for: Screen Sharing, SSH (Remote Login), SMB, Remote
Management, Printer Sharing, Media Sharing.

### 11.10 Secure Boot & firmware password

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

### 11.11 Password policy

Already applied by `install.sh` via `pwpolicy` (§3.1 step 5). 7 scan scripts
verify compliance (min length, lockout, history, lifetime, complexity).
Fix scripts exist for `account_inactivity_enforce` and `minimum_lifetime_enforce`
if they show FAIL.

> **Admin password:** the installer intentionally does not force a change for
> the logged-in installer user. See §3.2 for the implications and the
> recommended voluntary `passwd` step before airgapping.

### 11.12 Audit logging

13 scan scripts + 3 fix scripts. Run all audit fixes in one pass:

```bash
for f in standards/scripts/fix/audit_*.sh; do sudo zsh "$f"; done
```

---

## 12. Final verification

### 12.1 Option A — Dashboard (recommended)

1. Open `http://127.0.0.1:8000`.
2. Dashboard → **Run Full Scan**.
3. Review compliance score and per-category charts.
4. Re-scan or re-fix any individual rule from the **Rules** page (TOTP prompt
   on fixes).

### 12.2 Option B — Command line

```bash
sudo zsh standards/800-53r5_high/800-53r5_high_compliance.sh
```

### 12.3 Expected state before airgapping

- All scriptable rules **PASS** (applied by `rules_setup.sh` in §4).
- **3 Touch ID rules**: **EXEMPT** (created by `rules_setup.sh` — excluded from score).
- **17 other policy rules** (smartcard, software updates, etc.): **EXEMPT** (created by `rules_setup.sh`).
- iCloud rules: **PASS** (enforced via unified profile).
- Firmware / Secure Boot: **PASS** (set manually in Recovery Mode).
- Password policy rules: **PASS** (set by `install.sh`).

---

## 13. Physical disconnect — airgap the device

> Only proceed once §12 is green.

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

**The device is now airgapped.** Daily operations continue in §14.

---

## 14. Daily operations

### 14.1 Open the dashboard

```
http://127.0.0.1:8000
```

No token, no login screen. 2FA prompts appear only when an operator attempts
a gated action (apply fix, change whitelist, grant exemption, disable 2FA).

### 14.2 Service management (modern `launchctl`)

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

### 14.3 Adding a USB device to the whitelist (post-airgap)

Whitelist changes are admin-only.

1. Log in as the **admin** (operators cannot complete this flow — gated on
   admin 2FA).
2. Connect the new USB device.
3. Dashboard → **Connections** → locate the device in **USB DEVICES**.
4. Click **Add to Whitelist**, fill in the purpose / owner note, save.
5. Enter the 6-digit TOTP from the **admin's** authenticator app.
6. The USB watcher picks up the change within 30 seconds — no restart needed.
7. The action is recorded in the **Audit Log** under the admin account.

### 14.4 Scheduling recurring scans

Dashboard → **Schedule** → configure a cron expression
(e.g. daily 02:00: `0 2 * * *`). The runner executes the scan session as root
and results appear in **Scan History**.

### 14.5 Generating reports

Dashboard → **Reports** → choose **HTML** (printable) or **CSV** (for archival).
Reports include the compliance score, per-rule status, audit-log excerpt, and
exemptions list.

### 14.6 Granting / revoking an exemption

Admin-only. Dashboard → **Exemptions** → **Grant Exemption** → enter rule ID,
reason, and expiry date. Admin TOTP prompt appears. Exempted rules are counted
as PASS in compliance reports but remain visible in the Rules list with an
**Exempt** badge.

---

## 15. Recovery procedures

### 15.1 Reset an operator password

Operators are standard users, so the admin resets from an admin shell:

```bash
sudo passwd operator01
```

The password policy installed in §3.1 still applies. If the operator is locked
out because of failed attempts, see §15.2.

**If the admin password itself is lost:**

1. Reboot into Recovery Mode (**hold Power** / **Cmd+R**).
2. Utilities → Terminal.
3. `resetpassword` — pick the admin user, set a new password.
4. Reboot normally.

> If FileVault is on and **both** the admin password and the PRK (§7.1) are lost,
> the data is unrecoverable by design.

### 15.2 Unlock a locked-out account

If the password-policy lockout triggers, unlock from an admin shell:

```bash
sudo pwpolicy -u operator01 -clearaccountpolicies
```

Then re-apply the site-wide policy so the account remains compliant:

```bash
sudo zsh app/install.sh     # idempotent — re-runs pwpolicy step
```

### 15.3 Re-enroll a Touch ID fingerprint

Only the owning operator can enroll or remove their own fingerprints:

1. Log in as the operator.
2. **System Settings → Touch ID & Password**.
3. Remove the old fingerprint (trash icon) and add a new one.

### 15.4 Reset admin 2FA (lost phone)

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
   temporarily unguarded. Immediately re-enroll via §8.4 on the replacement
   phone before doing anything else.
4. The SQLite delete and the re-enrollment are both recorded in the Audit Log.

### 15.5 Restore the pf configuration

If the dashboard becomes unreachable after §9.3:

```bash
sudo cp /etc/pf.conf.bak /etc/pf.conf
sudo pfctl -f /etc/pf.conf
```

### 15.6 Reinstall HX-Guardian from SD card

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

## 16. Troubleshooting

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
- Expected. Use the Finder + System Settings flow in §6.1 instead.

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
- Last-resort reset (admin's phone lost / unrecoverable): §15.4.

**Server fails to start / binary not found**
```bash
# Re-deploy binaries from the SD card bundle
sudo zsh ~/hxg-install/app/install.sh
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
