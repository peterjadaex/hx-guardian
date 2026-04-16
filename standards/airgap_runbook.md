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
| App access | `com.apple.applicationaccess.mobileconfig` | Blocks AirDrop, Siri, dictation |
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
