# HX-Guardian Hardening Controls

**Baselines:** NIST 800-53r5 High · CIS Controls v8 · CIS macOS Benchmark Level 2
**Total rules:** 268 (102 auto-remediated · 166 scan-only or MDM-enforced)
**Source of truth:** [standards/scripts/manifest.json](scripts/manifest.json)

---

## 1. Auditing & Logging

**28 controls · 25 auto-fixable · maps to NIST AU family, CIS Control 8**

### 1.1 Audit Daemon
- Security auditing (`auditd`) enabled
- System shutdown on audit failure
- Audit failure notification configured

### 1.2 Audit Event Flags
- Authorization & authentication events (`aa`)
- Administrative actions (`ad`)
- Failed program execution (`ex`)
- Object deletion (`fd`)
- Failed object-attribute changes (`fm_failed`)
- Failed read actions (`fr`)
- Failed write actions (`fw`)
- Login / logout events (`lo`)

### 1.3 Audit Trail Integrity
- `audit_control` — owner root, group wheel, mode 440, no ACLs
- Audit log files — owner root, group wheel, mode 440, no ACLs
- Audit log folders — owner root, group wheel, mode 700
- Cryptographic protection of audit records

### 1.4 Retention, Capacity, Off-Load
- Configurable audit retention period
- Capacity warning threshold
- Off-load of audit records to external storage
- Record reduction and report generation

### 1.5 System Logs
- Apple System Log (ASL) — root:wheel, mode 640
- `newsyslog`-managed logs — root:wheel, mode 640
- `install.log` retention enforced
- Sudo command logging enforced

---

## 2. Authentication & Identity

**7 authentication controls + 15 password-policy controls · maps to NIST IA family, CIS Controls 5 & 6**

### 2.1 Smartcard / MFA
- Smartcard hardware is not deployed in the HX-Guardian air-gap environment
- Smartcard login, `su`, `sudo`, trust, token-removal, and supplemental rules
  are permanently exempted and excluded from functional testing
- SSH password authentication disabled

### 2.2 Password Policy

Enforced locally or by the unified profile:

- Minimum length: 15 characters
- Uppercase, lowercase, numeric, and special-character requirements
- Lockout threshold: 5 failed attempts
- Password hints removed from accounts
- Stored passwords encrypted; passwords obscured on entry

The lockout has no automatic recovery timeout. The timeout rule is permanently
exempted because local-node timeout enforcement is unreliable on macOS Tahoe;
an administrator performs recovery using the documented operator procedure.

Permanently exempted to avoid local authentication failures on macOS Tahoe:

- Account inactivity disable
- Automatic lockout recovery timeout
- Site-specific custom regex
- Password history
- Maximum password lifetime
- Minimum password lifetime
- Repeating / ascending / descending sequence restriction

Tracked through manual evidence:

- Force password change at next logon
- Auto-disable temporary accounts within 72 h
- Auto-disable emergency accounts within 72 h

### 2.3 Re-Authentication
- Devices must re-authenticate when authenticators change
- Users must re-authenticate when authenticators change

---

## 3. iCloud & Cloud Service Isolation

**14 controls · all MDM-enforced · maps to NIST AC-20 / SC-7, CIS Control 3**

All of the following are **disabled**:

- Apple ID system settings pane
- iCloud Address Book
- iCloud Bookmarks
- iCloud Calendar
- iCloud Drive (document sync)
- iCloud Desktop & Documents folder sync
- iCloud Freeform
- iCloud Game Center
- iCloud Keychain sync
- iCloud Mail
- iCloud Notes
- iCloud Photo Library
- iCloud Private Relay
- iCloud Reminders

---

## 4. Operating System Hardening

**129 controls · 50 auto-fixable · maps to NIST AC / CM / SC / SI families, CIS Controls 2 & 4**

### 4.1 Boot & Code Integrity
- System Integrity Protection (SIP) enabled
- Secure Boot set to Full
- Authenticated Root enabled
- System volume read-only
- Apple Mobile File Integrity enabled
- Library Validation enabled
- Firmware password required
- Recovery Lock enabled

### 4.2 Code-Execution Control
- Gatekeeper enabled — identified developers only
- Gatekeeper end-user override disallowed
- Application sandboxing (separate execution domains) enforced
- Approved anti-virus required
- Memory protection from unauthorised code execution
- XProtect Remediator & Gatekeeper auto-updates
- Rapid Security Response enforced; user-undo disabled
- Malicious-code protection mechanisms

### 4.3 Network Services Disabled
- AirDrop
- Bonjour multicast
- Handoff
- iPhone Mirroring
- Infrared (IR) support
- Built-in web server (`httpd`)
- NFS daemon
- TFTP service
- UUCP service

### 4.4 SSH (if Enabled)
- FIPS-compliant ciphers only
- Per-source penalties
- Server / client alive interval & count limits
- SSHD channel and unused-connection timeouts
- Root login denied over SSH
- Policy banner displayed
- Otherwise SSH disabled entirely

### 4.5 Apple Intelligence / Generative AI
All of the following are **disabled**:

- Image Playground
- Genmoji
- Writing Tools
- Mail Smart Replies
- Mail Summary
- Notes Transcription & Summary
- Safari Reader Summary
- Photos Enhanced Visual Search
- External Intelligence integrations + sign-in
- Apple Intelligence skipped during Setup Assistant

### 4.6 FileVault
- FileVault enforced
- Enforced in Setup Assistant
- Auto-login disabled
- Authorised-user list controlled

### 4.7 Identity & Access
- Root account login disabled
- Concurrent GUI sessions capped at 10
- Login to other users' active / locked sessions disabled
- `AdminHostInfo` hidden at login window
- Unique user & process identification
- MDM enrolment enforced
- MFA required for network access to privileged accounts

### 4.8 Cryptography
- Approved cryptography implementation
- Required cryptographic module met
- SSH and SSHD restricted to FIPS-compliant connections

### 4.9 Filesystem Permissions
- No world-writable files in `/Library`
- No world-writable files in `/System`
- System-wide applications permission audit
- User home folders secured
- Guest folder removed

### 4.10 Safari Hardening
- Cross-site tracking prevention enabled
- Fraudulent-website warning enabled
- Status bar displayed
- Full URL displayed
- Advertising privacy protection enabled
- Auto-open of "safe" downloads disabled

### 4.11 Sudo
- Sudo event logging enforced
- Sudo timeout configured
- Sudoers timestamp type configured (tty_tickets)

### 4.12 Power & Sleep
- Power Nap disabled
- Sleep / display sleep enforced on Apple Silicon

---

## 5. System Settings (Device & UI)

**69 controls · 21 auto-fixable · maps to NIST AC / SC, CIS Control 2**

### 5.1 Network Interfaces & Sharing
All **disabled** in production:

- Wi-Fi interface (and forced off when on Ethernet)
- Ethernet interface
- Internet Sharing
- Content Caching
- Media Sharing
- Printer Sharing
- SMB sharing (and guest SMB access)
- Screen Sharing / Apple Remote Desktop
- Remote Apple Events
- Remote Management
- AirPlay Receiver
- Wake-for-Network access

Other:

- Application Firewall enabled with **stealth mode**
- Bluetooth disabled when no approved device is connected
- Bluetooth Sharing disabled
- Bluetooth system settings pane disabled

### 5.2 Session Lock
- Screensaver password required
- Screensaver timeout enforced
- Password-after-screensaver delay = 0 (immediate)
- Auto-logout after inactivity
- Apple Watch unlock disabled
- Touch ID unlock disabled
- Touch ID settings pane disabled
- Smart-token removal is out of scope because smartcard hardware is not deployed
- Hot Corners disabled / secured

### 5.3 Login Window
- Custom policy banner displayed
- Prompt for username + password (no user list)
- Automatic login disabled
- Guest account disabled

### 5.4 Software Updates
- Critical security updates enforced via DDM
- macOS updates auto-installed via DDM
- Software Update app updates auto-installed
- Software Update deferral window enforced
- Time server configured & enforced (NTP)

### 5.5 Privacy & Telemetry
All **disabled**:

- Diagnostic & usage data to Apple
- Improve Search information
- Improve Siri & Dictation information
- Assistive Voice transcripts to Apple
- Personalized Advertising
- Siri service + settings pane + "Listen for"
- Dictation (or on-device only when required)
- Find My
- Location Services (production)
- Internet Accounts system pane
- Wallet & Apple Pay settings pane

### 5.6 Time Machine
- Automatic backups enabled
- Backup volumes encrypted

### 5.7 USB
- USB Restricted Mode enforced (devices must be authorised before connecting)

---

## 6. Supplemental & Manually-Verified Controls

**6 entries · not script-remediated · documented in audit evidence**

- FileVault supplemental procedures
- Packet Filter (pf) supplemental rules
- Password policy supplemental
- Smartcard supplemental (hardware-dependent — exempted with documented reason where reader absent)
- CIS manual recommendations
- Out-of-scope supplemental controls register

---

*Per-rule framework cross-walk is in [standards/scripts/manifest.json](scripts/manifest.json) — each rule lists `standards.{800-53r5_high, cis_lvl2, cisv8}` booleans and the source baseline used for its scan and fix script.*
