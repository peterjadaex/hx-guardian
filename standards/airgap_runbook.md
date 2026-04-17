# Airgap Device Setup Runbook — macOS

This runbook covers end-to-end hardening of a macOS device for airgapped operation.
Every step is linked to the exact MDM profiles and scripts in this repository.

**Standards baseline used throughout:** NIST 800-53r5 High  
(Swap profile paths for `cisv8/` or `cis_lvl2/` if using a different baseline.)

**Touch ID policy:** Touch ID is intentionally kept enabled for operator convenience.
Three baseline rules that disable it are explicitly skipped — see [Phase 3 note](#touch-id-exception).

---

## Prerequisites

- macOS 12 Monterey or later (Apple Silicon or Intel)
- Device enrolled in MDM, or profiles deployed manually via `profiles install -path <file>`
- All steps in Phases 0–4 require internet access; Phase 5 is the point of disconnection

---

## Phase 0 — While Internet Is Available

Complete these steps **before** deploying any profiles or running any scripts.

### 0.1 Update macOS to Latest

```
System Settings > General > Software Update
```

Install all available updates including firmware. Reboot if required.
Verify: `sw_vers` — confirm expected OS version.

### 0.2 Download Required Software

Download everything the device will need offline:
- All application installers (verify SHA checksums against official sources)
- Xcode Command Line Tools: `xcode-select --install`
- Any package manager caches (Homebrew, pip wheels, etc.)

### 0.3 Sign Out of Apple ID

```
System Settings > [Apple ID] > Sign Out
```

Disable iCloud Drive, Find My Mac, and all iCloud sync before continuing.

---

## Phase 1 — Deploy MDM Profiles

Deploy all profiles from `standards/800-53r5_high/mobileconfigs/unsigned/` **before** running scripts.
Profiles enforce policy at the MDM layer and cannot be overridden by users.

```bash
# Deploy a single profile manually (no MDM server)
sudo profiles install -path standards/800-53r5_high/mobileconfigs/unsigned/<profile>.mobileconfig
```

### Profiles to Deploy

| Area | Profile File | Notes |
|------|-------------|-------|
| FileVault 2 | `com.apple.MCX.FileVault2.mobileconfig` | Enforces encryption at rest |
| Firewall | `com.apple.security.firewall.mobileconfig` | Enables firewall + stealth mode |
| iCloud restrictions | `com.apple.icloud.managed.mobileconfig` | Blocks all iCloud services |
| Login window | `com.apple.loginwindow.mobileconfig` | Hides username list, disables guest |
| Screen lock | `com.apple.screensaver.mobileconfig` | Idle timeout + password required |
| Software updates | `com.apple.SoftwareUpdate.mobileconfig` | Enforces update checks |
| Password policy | `com.apple.mobiledevice.passwordpolicy.mobileconfig` | Min length, complexity, history |
| Gatekeeper | `com.apple.systempolicy.control.mobileconfig` | Identified developers only |
| App access | `com.apple.applicationaccess.mobileconfig` | Blocks AirDrop, Siri, dictation, enforces USB restricted mode — see §1.5 |
| System preferences | `com.apple.systempreferences.mobileconfig` | Locks sensitive settings panes |
| Siri | `com.apple.assistant.support.mobileconfig` | Disables Siri + assistant |
| Setup assistant | `com.apple.SetupAssistant.managed.mobileconfig` | Suppresses setup prompts |
| Diagnostics | `com.apple.SubmitDiagInfo.mobileconfig` | Disables crash reporting to Apple |
| Smart card | `com.apple.security.smartcard.mobileconfig` | Optional: if using PIV/CAC cards |

#### Touch ID Exception — Profile Edit Required

The `com.apple.applicationaccess.mobileconfig` profile in the baseline sets
`allowFingerprintForUnlock = false`. Before deploying, open the file and either:
- Remove the `allowFingerprintForUnlock` key entirely, **or**
- Set it to `<true/>`

This allows operators to use Touch ID for unlock and sudo authentication.

---

## Phase 1.1 — Start HX-Guardian

HX-Guardian is the local compliance dashboard used throughout the rest of this runbook.
It must be running **before** Phase 1.5 (USB whitelisting) and **before** Phase 4 (verification).

### Prerequisites

- Python 3.11 or later (`python3 --version`)
- pip (`python3 -m pip --version`)
- The frontend is already built in `app/frontend/dist/` — no Node.js required unless you need to rebuild it

### 1.1.1 Install Python Dependencies

```bash
# From the repository root
pip install -r app/backend/requirements.txt
```

Run this once. After airgapping you can skip it (dependencies are already installed).

### 1.1.2 Start the Privileged Runner Daemon

The runner daemon executes scan and fix scripts as root. It must be running for any scan
or fix to work. Open a **dedicated terminal** and leave it running:

```bash
# Terminal 1 — keep this open at all times
sudo python3 app/backend/hxg_runner.py
```

Expected output:
```
2026-xx-xx [runner] INFO Manifest loaded: 266 rules
2026-xx-xx [runner] INFO hxg_runner listening on /var/run/hxg/runner.sock (uid=0)
```

> **Note:** The runner creates `/var/run/hxg/runner.sock` at startup. If you see
> `Manifest not found`, confirm you are running from the repository root.

### 1.1.3 Start the Dashboard Backend

Open a **second terminal** and run:

```bash
# Terminal 2 — keep this open at all times
cd app/backend
python3 -m uvicorn main:app --host 127.0.0.1 --port 8000
```

On startup uvicorn prints a session token to the log — **copy it now**:

```
INFO  ============================================================
INFO  Dashboard session token (copy this):
INFO    a3f8c2...  ← copy this entire string
INFO  Open: http://127.0.0.1:8000
INFO  ============================================================
```

> **The token changes every time the server restarts.** Keep Terminal 2 open; restarting
> requires re-copying the token and logging in again.

### 1.1.4 Log In to the Dashboard

1. Open `http://127.0.0.1:8000` in a browser
2. Paste the token from the startup log into the login field
3. Click **Sign In**

### 1.1.5 Verify Runner Is Connected

After logging in, check the runner connection:

```bash
curl -s -H "Authorization: Bearer <token>" http://127.0.0.1:8000/api/health
```

Expected response:
```json
{"status": "ok", "runner_connected": true, "version": "1.0.0"}
```

If `runner_connected` is `false`, the runner daemon (Terminal 1) is not running or failed
to create its socket. Check Terminal 1 for errors and restart it.

### 1.1.6 Rebuild the Frontend (Optional)

Only needed if you have modified the frontend source under `app/frontend/src/`.
Requires Node.js 18+:

```bash
cd app/frontend
npm install
npm run build
```

Then restart the backend (Terminal 2) to serve the new build.

---

## Phase 1.5 — USB Restriction & Device Whitelisting

Complete this phase **after** deploying MDM profiles and **before** airgapping, while internet and
USB peripherals are still accessible for whitelisting.

---

### 1.5.1 USB Restricted Mode

**What it does:** When enabled, macOS requires the device to be unlocked before a newly connected
USB accessory is allowed to communicate. If the device has been locked for more than one hour,
any new USB connection is blocked until the operator authenticates. This prevents USB-based
attacks (e.g. juice-jacking, hardware implants) against a locked, unattended airgapped device.

**MDM key:** `allowUSBRestrictedMode` in the `com.apple.applicationaccess` payload.

**Enable via the deployed profile:** The `com.apple.applicationaccess.mobileconfig` profile
already deployed in Phase 1 controls this setting. Before deploying the profile, open it and
ensure the following key is present in the payload dictionary:

```xml
<key>allowUSBRestrictedMode</key>
<true/>
```

If the key is missing, add it before running `profiles install`. If the profile is already
installed, update the plist and re-deploy:

```bash
sudo profiles remove -identifier com.apple.applicationaccess
sudo profiles install -path standards/800-53r5_high/mobileconfigs/unsigned/com.apple.applicationaccess.mobileconfig
```

**Verify compliance:**

```bash
sudo zsh standards/scripts/scan/system_settings_usb_restricted_mode.sh
```

Expected output: `PASS` (exit code 0). If `FAIL`, re-deploy the profile above.

> **Note:** USB Restricted Mode only controls *new* accessories connected while locked. Devices
> already trusted (connected and authenticated before locking) remain active.

---

### 1.5.2 Whitelist Known-Good USB Devices

Before airgapping, register all USB peripherals that will be used on this device (YubiKeys, CAC
readers, approved keyboards/mice, encrypted drives) in the HX Guardian whitelist. Any device
connected at runtime that is not on the whitelist will be flagged **Unauthorized** in the
Connection Monitor.

**Steps:**

1. Connect each approved USB device
2. Open HX Guardian → **Connections** (`http://127.0.0.1:8000/connections`)
3. Each connected device appears in the **USB DEVICES** section
   - Unrecognised devices show a red **Unauthorized** badge
4. Click **Add to Whitelist** next to each approved device — the form pre-fills with the
   device name, vendor, product ID, and serial number
5. Add an optional note (e.g. operator name, asset tag, purpose) and click **Add to Whitelist**
6. Verify the device now shows a green **Whitelisted** badge

**Whitelisting storage volumes (SD cards, USB drives):**

Mounted storage volumes (SD cards, USB drives) appear in the separate **USB VOLUMES** section
directly below USB DEVICES. Each volume shows its mount point, filesystem, size, and the name
of its parent USB device (the card reader or hub port it arrived through).

- Volumes inherit whitelist status from their **parent USB device** — whitelisting the device
  also permits its storage volumes
- Click **Add to Whitelist** on a volume row to pre-fill the form with the parent device's
  identifiers, then save
- If the USB watcher daemon is running, it will stop ejecting the volume within 30 seconds
  of the whitelist entry being saved (the daemon re-reads the DB every 30 s)

To manage the whitelist manually, use the **USB WHITELIST** card below the device list:
- **Add Device** — add a device by entering its identifiers manually
- **Remove** (trash icon) — revoke a previously whitelisted entry

All add/remove actions are written to the Audit Log (`/audit-log`).

**Match criteria:** A connected device is considered whitelisted if its `product_id` **or**
`serial` matches any whitelist entry (whichever fields are non-empty). Use serial when available
for strongest identity binding; product ID alone matches any unit of the same model.

---

### 1.5.3 Install the USB Enforcement Daemon

The HX Guardian USB Watcher is a root-level daemon that enforces the whitelist at the OS layer —
not just in the UI. Install it **before airgapping** while you still have admin access.

**Prerequisite — grant Terminal Full Disk Access:**

macOS requires the terminal to have Full Disk Access before `sudo python3` can read files
under `/Users/`. Without it the daemon fails with `[Errno 1] Operation not permitted`.

1. **System Settings → Privacy & Security → Full Disk Access**
2. Click `+` → add Terminal.app (or iTerm2)
3. Toggle it on, then quit and reopen the terminal

This is a one-time step. It is also required for the install script to work.

**Install via launchd (recommended — survives reboots):**

```bash
sudo zsh standards/scripts/setup/install_usb_watcher.sh
```

**Run manually for testing (foreground, no reboot persistence):**

```bash
sudo touch /var/log/hxguardian_usb.log
sudo chmod 644 /var/log/hxguardian_usb.log
sudo sh -c 'python3 /path/to/app/backend/usb_watcher.py >> /var/log/hxguardian_usb.log 2>&1' &
tail -f /var/log/hxguardian_usb.log
```

**What it does:**

| Action | Detail |
|--------|--------|
| Polls USB bus | Every 5 seconds via `system_profiler SPUSBDataType` |
| Checks whitelist | Reads `usb_whitelist` table directly from SQLite every 30 s |
| Ejects storage | Runs `diskutil eject` on any unauthorized removable volume |
| Re-ejects on replug | Tracks ejected BSD disk names — re-ejects if a card is removed and reinserted into the same reader |
| Notifies operator | macOS system notification with sound (`Basso`) via `launchctl asuser` |
| Logs to audit trail | Writes `USB_UNAUTHORIZED_DEVICE` record to HX Guardian `audit_log` |
| Survives reboots | `KeepAlive` LaunchDaemon — restarts automatically after crash or reboot |

**Start / stop (after launchd install):**

```bash
# Stop
sudo launchctl unload /Library/LaunchDaemons/com.hxguardian.usbwatcher.plist

# Start
sudo launchctl load /Library/LaunchDaemons/com.hxguardian.usbwatcher.plist

# Status
launchctl list com.hxguardian.usbwatcher

# Live log
tail -f /var/log/hxguardian_usb.log
```

**Stop manual background run:**

```bash
sudo kill $(pgrep -f usb_watcher.py)
```

**Uninstall:**

```bash
sudo launchctl unload /Library/LaunchDaemons/com.hxguardian.usbwatcher.plist
sudo rm /Library/LaunchDaemons/com.hxguardian.usbwatcher.plist
```

> **Note:** The daemon re-reads the whitelist every 30 seconds, so newly whitelisted devices
> take effect without a restart.

---

### 1.5.4 Post-Airgap USB Policy

Once airgapped:

- Operators should connect **only whitelisted** USB devices
- Any unrecognised device triggers an immediate macOS notification, storage ejection (if
  applicable), and an entry in the HX Guardian Audit Log and Connections page
- Unauthorized USB events appear in the **UNAUTHORIZED USB EVENTS** section on the
  Connections page (`http://127.0.0.1:8000/connections`)
- To add a new device after airgapping, an authorised operator must access HX Guardian locally,
  add the device via the whitelist form, and confirm the watcher picks it up within 30 seconds;
  this action is audit-logged

---

## Phase 2 — Create Operator Users

Run the operator user creation script **after** profiles are deployed but **before** airgapping,
so users can complete first-login password changes while internet is still available.

```bash
sudo zsh standards/scripts/setup/create_operator_users.sh
```

This creates five local standard (non-admin) accounts:

| Username | Full Name | UID |
|----------|-----------|-----|
| operator01 | Operator 01 | 511 |
| operator02 | Operator 02 | 512 |
| operator03 | Operator 03 | 513 |
| operator04 | Operator 04 | 514 |
| operator05 | Operator 05 | 515 |

**After the script runs:**
1. Log in as each operator user
2. Change the temporary password when prompted
3. Enroll Touch ID: `System Settings > Touch ID & Password > Add a Fingerprint`
4. Log out and return to admin account

**Touch ID enrollment must happen before airgapping** — the enrollment flow makes a one-time
network call to verify the Secure Enclave certificate on first use.

---

## Phase 3 — Script-Based Hardening

Run each scan script to check compliance, then the corresponding fix script to remediate.

```bash
# Pattern
sudo zsh standards/scripts/scan/<rule>.sh    # check — outputs JSON
sudo zsh standards/scripts/fix/<rule>.sh     # remediate
```

Exit codes: `0` = PASS / SUCCESS, `1` = FAIL, `2` = NOT_APPLICABLE, `3` = ERROR

---

### 3.1 FileVault (Full Disk Encryption)

| Script | Purpose |
|--------|---------|
| `scan/system_settings_filevault_enforce.sh` | Verify FileVault is on |
| `fix/system_settings_filevault_enforce.sh` | Enable FileVault |
| `scan/os_filevault_autologin_disable.sh` | Verify auto-login is blocked |
| `fix/os_filevault_autologin_disable.sh` | Disable auto-login |

> After enabling FileVault, save the **local recovery key** — do **not** use iCloud recovery
> (the device will be airgapped). Store the key offline, physically secured.

---

### 3.2 Firewall

| Script | Purpose |
|--------|---------|
| `scan/system_settings_firewall_enable.sh` | Verify firewall is on |
| `fix/system_settings_firewall_enable.sh` | Enable firewall |
| `scan/system_settings_firewall_stealth_mode_enable.sh` | Verify stealth mode |
| `fix/system_settings_firewall_stealth_mode_enable.sh` | Enable stealth mode |
| `scan/os_firewall_default_deny_require.sh` | Verify default-deny posture |

---

### 3.3 iCloud — MDM Only

All 14 iCloud rules are scan-only (no fix scripts). Remediation is via the
`com.apple.icloud.managed.mobileconfig` profile deployed in Phase 1.

| Scan Script | What It Checks |
|-------------|----------------|
| `scan/icloud_appleid_system_settings_disable.sh` | Apple ID pane hidden |
| `scan/icloud_sync_disable.sh` | iCloud sync off |
| `scan/icloud_drive_disable.sh` | iCloud Drive off |
| `scan/icloud_keychain_disable.sh` | iCloud Keychain off |
| `scan/icloud_photos_disable.sh` | iCloud Photos off |
| `scan/icloud_mail_disable.sh` | iCloud Mail off |
| `scan/icloud_calendar_disable.sh` | iCloud Calendar off |
| `scan/icloud_notes_disable.sh` | iCloud Notes off |
| `scan/icloud_reminders_disable.sh` | iCloud Reminders off |
| `scan/icloud_bookmarks_disable.sh` | iCloud Bookmarks off |
| `scan/icloud_private_relay_disable.sh` | Private Relay off |
| `scan/os_appleid_prompt_disable.sh` | Apple ID prompt suppressed |
| `scan/os_icloud_storage_prompt_disable.sh` | iCloud storage prompt off |

---

### 3.4 Screen Lock

| Script | Purpose |
|--------|---------|
| `scan/system_settings_screensaver_timeout_enforce.sh` | Idle timeout ≤ 10 min |
| `scan/system_settings_screensaver_password_enforce.sh` | Password required to unlock |
| `scan/system_settings_screensaver_ask_for_password_delay_enforce.sh` | No delay before lock |
| `scan/os_screensaver_loginwindow_enforce.sh` | Loginwindow screensaver set |

---

### 3.5 Login Window & Guest Account

| Script | Purpose |
|--------|---------|
| `scan/system_settings_guest_account_disable.sh` | Guest account off |
| `scan/os_guest_folder_removed.sh` | /Users/Guest removed |
| `fix/os_guest_folder_removed.sh` | Remove /Users/Guest |
| `scan/system_settings_guest_access_smb_disable.sh` | SMB guest access off |
| `fix/system_settings_guest_access_smb_disable.sh` | Disable SMB guest |
| `scan/system_settings_automatic_login_disable.sh` | Auto-login disabled |
| `scan/system_settings_loginwindow_prompt_username_password_enforce.sh` | Show username+password fields |
| `scan/os_loginwindow_adminhostinfo_disabled.sh` | No host info at login window |

---

### 3.6 System Integrity Protection (SIP)

| Script | Purpose |
|--------|---------|
| `scan/os_sip_enable.sh` | Verify SIP is on |
| `fix/os_sip_enable.sh` | Enable SIP |

> SIP changes require Recovery Mode. If the fix script fails, reboot to Recovery
> (`hold Power` on Apple Silicon, `Cmd+R` on Intel) and run `csrutil enable`.

---

### 3.7 Gatekeeper

| Script | Purpose |
|--------|---------|
| `scan/os_gatekeeper_enable.sh` | Gatekeeper on |
| `scan/system_settings_gatekeeper_identified_developers_allowed.sh` | Allow identified devs |
| `scan/system_settings_gatekeeper_override_disallow.sh` | Block right-click overrides |

---

### 3.8 Siri & Dictation

| Script | Purpose |
|--------|---------|
| `scan/system_settings_siri_disable.sh` | Siri disabled |
| `scan/system_settings_siri_settings_disable.sh` | Siri settings pane hidden |
| `scan/os_siri_prompt_disable.sh` | Siri setup prompt off |
| `scan/os_dictation_disable.sh` | Dictation off |
| `scan/system_settings_improve_siri_dictation_disable.sh` | Siri improvement opt-out |

---

### 3.9 AirDrop

| Script | Purpose |
|--------|---------|
| `scan/os_airdrop_disable.sh` | AirDrop disabled (scan only — MDM via applicationaccess profile) |

---

### 3.10 Bluetooth

| Script | Purpose |
|--------|---------|
| `scan/system_settings_bluetooth_disable.sh` | Bluetooth off (scan only — MDM via controlcenter profile) |
| `scan/system_settings_bluetooth_sharing_disable.sh` | Bluetooth sharing off |
| `fix/system_settings_bluetooth_sharing_disable.sh` | Disable Bluetooth sharing |

> Full Bluetooth disable requires `com.apple.controlcenter.mobileconfig` (available in CIS v8/L2
> baselines). If using 800-53r5 High, disable Bluetooth manually:
> `System Settings > Bluetooth > Turn Bluetooth Off`.

---

### 3.11 Sharing Services

| Script | Purpose |
|--------|---------|
| `scan/system_settings_screen_sharing_disable.sh` | Screen sharing off |
| `fix/system_settings_screen_sharing_disable.sh` | Disable screen sharing |
| `scan/system_settings_ssh_disable.sh` | Remote Login (SSH) off |
| `fix/system_settings_ssh_disable.sh` | Disable SSH |
| `scan/system_settings_smbd_disable.sh` | File sharing (SMB) off |
| `fix/system_settings_smbd_disable.sh` | Disable SMB |
| `scan/system_settings_remote_management_disable.sh` | Remote Management off |
| `fix/system_settings_remote_management_disable.sh` | Disable Remote Management |
| `scan/system_settings_printer_sharing_disable.sh` | Printer sharing off |
| `scan/system_settings_media_sharing_disabled.sh` | Media sharing off |

---

### 3.12 Secure Boot & Firmware Password

These are **scan-only** — remediation requires manual steps in Recovery Mode.

| Script | What It Checks |
|--------|----------------|
| `scan/os_secure_boot_verify.sh` | Secure Boot set to Full Security |
| `scan/os_firmware_password_require.sh` | EFI/Startup Security password set |

**Set firmware password manually:**
1. Reboot to Recovery Mode (`hold Power` / `Cmd+R`)
2. Utilities > Startup Security Utility
3. Set to **Full Security** and enable password requirement
4. On Apple Silicon: this is controlled by Activation Lock and MDM enrollment

---

### 3.13 Password Policy

| Script | Purpose |
|--------|---------|
| `scan/pwpolicy_minimum_length_enforce.sh` | Min 15 chars |
| `scan/pwpolicy_account_lockout_enforce.sh` | Lock after N attempts |
| `scan/pwpolicy_account_lockout_timeout_enforce.sh` | Lockout duration |
| `scan/pwpolicy_history_enforce.sh` | No password reuse |
| `scan/pwpolicy_max_lifetime_enforce.sh` | Password expiry |
| `scan/pwpolicy_alpha_numeric_enforce.sh` | Require letters + numbers |
| `scan/pwpolicy_special_character_enforce.sh` | Require special chars |
| `fix/pwpolicy_account_inactivity_enforce.sh` | Lock inactive accounts |
| `fix/pwpolicy_minimum_lifetime_enforce.sh` | Min password age |

---

### 3.14 Audit Logging

| Script | Purpose |
|--------|---------|
| `scan/audit_auditd_enabled.sh` | auditd running |
| `fix/audit_auditd_enabled.sh` | Start auditd |
| `scan/audit_flags_lo_configure.sh` | Log login/logout events |
| `scan/audit_flags_aa_configure.sh` | Log auth/auth events |
| `scan/audit_flags_ad_configure.sh` | Log admin activity |
| `scan/audit_flags_ex_configure.sh` | Log process exec |
| `scan/audit_flags_fd_configure.sh` | Log file deletion |
| `scan/audit_flags_fr_configure.sh` | Log file reads |
| `scan/audit_flags_fw_configure.sh` | Log file writes |
| `scan/audit_flags_fm_failed_configure.sh` | Log failed file attr changes |
| `scan/audit_retention_configure.sh` | Retention policy set |
| `scan/audit_acls_files_configure.sh` | Audit file ACLs |
| `fix/audit_acls_files_configure.sh` | Remove ACLs from audit files |

Run all audit fix scripts together:
```bash
for f in standards/scripts/fix/audit_*.sh; do sudo zsh "$f"; done
```

---

### Touch ID Exception

The following three rules will show **FAIL** in compliance reports — this is intentional.
Do **not** run these fix scripts or deploy the Touch ID–disabling MDM keys.

| Rule | Why Skipped |
|------|-------------|
| `system_settings_touchid_unlock_disable` | Operators use Touch ID for unlock |
| `system_settings_touch_id_settings_disable` | Operators need to manage their fingerprints |
| `os_touchid_prompt_disable` | Enrollment prompt required for new operators |

---

## Phase 4 — Verification

**Option A — HX-Guardian dashboard (recommended)**

With the runner and backend running (Phase 1.1), open `http://127.0.0.1:8000` and click
**Run Full Scan** on the Dashboard. HX-Guardian runs all 266 rules, shows a compliance
score, and highlights failures by category. Individual rules can be re-scanned or fixed
from the Rules page without re-running the full suite.

**Option B — Command line**

Run the master compliance script and review the report:

```bash
sudo zsh standards/800-53r5_high/800-53r5_high_compliance.sh
```

Expected outcome before airgapping:
- All rules **PASS** except the 3 Touch ID exceptions above (intentional FAIL)
- iCloud rules: **PASS** (enforced via MDM profile)
- Firmware/secure boot: **PASS** (set manually in Recovery Mode)

---

## Phase 5 — Physical Disconnect

Once all of the above passes:

1. Forget all saved Wi-Fi networks: `System Settings > Wi-Fi > (each network) > Forget`
2. Turn off Wi-Fi: `System Settings > Wi-Fi > off`
3. Disable Bluetooth if not needed: `System Settings > Bluetooth > off`
4. If Ethernet: physically remove the adapter
5. Final verification — confirm no active interfaces:
   ```bash
   ifconfig | grep 'inet ' | grep -v 127.0.0.1
   sudo lsof -i | grep ESTABLISHED
   ```
   Both commands should return no output.

**The device is now airgapped.**

---

## Appendix: Script Quick Reference

All scripts live under `standards/scripts/` and require `sudo zsh <script>`.

| Category | Scan Count | Fix Count |
|----------|-----------|-----------|
| Audit | 25 | 25 |
| Authentication | 7 | 4 |
| iCloud | 14 | 0 (MDM only) |
| Operating System | 91 | 40 |
| Password Policy | 11 | 2 |
| System Settings | 66 | 15 |

Full rule index: `standards/scripts/manifest.json`  
Standards comparison: `standards/security_standards_comparison.md`

### USB Enforcement

| Script / File | Purpose |
|---------------|---------|
| `standards/scripts/setup/install_usb_watcher.sh` | Install & start the USB enforcement daemon |
| `app/backend/usb_watcher.py` | The daemon itself (do not run directly; use launchd) |
| `standards/launchd/com.hxguardian.usbwatcher.plist` | LaunchDaemon template (path filled at install time) |
| `/Library/LaunchDaemons/com.hxguardian.usbwatcher.plist` | Installed plist (post-install) |
| `/var/log/hxguardian_usb.log` | Daemon runtime log |
