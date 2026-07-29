# HX-Guardian Hardening Test Checklist

Use this checklist to verify an HX-Guardian-hardened macOS signing device after
installation, after a hardening change, and before release to production.

This is a verification procedure, not a remediation procedure. Do not apply
fixes, install profiles, change security settings, restart services, or reboot
the device while executing a test unless the case explicitly requires a
controlled maintenance window and the change has been approved.

## 1. Test record

Complete this section once for each test cycle.

| Field | Actual result |
|---|---|
| Test cycle ID |  |
| Device asset ID |  |
| macOS version and build |  |
| Hardware model / architecture |  |
| HX-Guardian version / commit |  |
| Installed baseline |  |
| Unified profile identifier / version |  |
| Tester |  |
| Test date and time |  |
| Environment | ☐ Disposable test device ☐ Production candidate ☐ Production |
| Network posture | ☐ Air-gapped ☐ Approved connected-test posture |
| Approved maintenance window |  |
| Previous scan session ID |  |
| Current scan session ID |  |

## 2. Status and evidence rules

Use one final status for every test case:

- [ ] **PASS** — every expected result was observed and evidence was captured.
- [ ] **FAIL** — at least one expected result was not observed.
- [ ] **BLOCKED** — the case could not be completed; record the blocker.
- [ ] **NOT APPLICABLE** — the control does not apply; record the approved basis.

For every case:

1. Record observed values under **Actual result**. Do not write only “as
   expected.”
2. Record evidence identifiers without embedding secrets, credentials, tokens,
   database contents, or sensitive log data.
3. Use screenshots, exported reports, scan session IDs, rule IDs, or approved
   audit-record references as evidence.
4. Treat `ERROR` as a failed test until the execution problem is understood.
5. Treat `MDM_REQUIRED` as pending manual/profile evidence, not as a pass.
6. Accept `EXEMPT` only when the exemption is approved, current, and supported
   by a documented reason.

## 3. Entry criteria

- [ ] The tester has read [Hardening Controls](hardening_controls.md).
- [ ] The tester has read the applicable installation and verification sections
      of [Airgap Device Admin & Operator Guide](airgap_readme.md).
- [ ] Installation or update activity is complete.
- [ ] The device is in its intended production network posture.
- [ ] The tester can access `http://127.0.0.1:8000`.
- [ ] The admin and authenticator are available for cases that verify 2FA.
- [ ] Any reboot, authentication-failure, peripheral, or recovery testing has a
      separately approved maintenance window.
- [ ] A recovery method is available before disruptive testing.

### Out of functional-test scope

Smartcard hardware is not deployed. Do not execute a smartcard functional test.
The following rules remain in the manifest and should appear as permanent
exemptions during HXG-SCAN-002, but they are excluded from the detailed test
cases:

- `auth_pam_login_smartcard_enforce`
- `auth_pam_su_smartcard_enforce`
- `auth_pam_sudo_smartcard_enforce`
- `auth_smartcard_allow`
- `auth_smartcard_certificate_trust_enforce_high`
- `auth_smartcard_enforce`
- `supplemental_smartcard`
- `system_settings_token_removal_enforce`

## 4. Command procedures and test summary

### 4.1 Command safety

- Run these commands locally on the target Mac in Terminal.
- The commands in this checklist are read-only unless a case is explicitly
  labeled **Controlled**.
- Do not prefix a command with `sudo`. HX-Guardian's runner already executes
  allowlisted scan scripts with the required privilege.
- Do not run anything from `standards/scripts/fix/` or
  `standards/scripts/undo_fix/` while executing this checklist.
- Replace values inside angle brackets, such as `<SESSION_ID>`, before running
  a command.
- If a command reports a permission error, record the case as BLOCKED and use
  dashboard scan evidence. Do not weaken file permissions to make a check run.
- Review command output before attaching it as evidence. Redact device serial
  numbers, usernames, media identifiers, network addresses, and other
  restricted identifiers according to the evidence-handling policy.
- When an individual case has no native macOS command block, run the
  category-result command printed immediately below that section heading. The
  remaining steps are intentionally UI or evidence-review steps because a
  safe, stable read-only CLI check is not available for that control.

### 4.2 Reusable HX-Guardian API commands

Set the local base URL once in each Terminal session:

```bash
HXG_BASE_URL='http://127.0.0.1:8000'
```

Check application and runner health:

```bash
/usr/bin/curl -fsS "$HXG_BASE_URL/api/health"
/usr/bin/curl -fsS "$HXG_BASE_URL/api/runner/status"
/usr/bin/curl -fsS "$HXG_BASE_URL/api/internal/startup"
```

Start a full read-only scan:

```bash
/usr/bin/curl -fsS \
  -X POST \
  -H 'Content-Type: application/json' \
  -d '{"filter":null}' \
  "$HXG_BASE_URL/api/scans"
```

The response contains `session_id`. Set it before polling:

```bash
HXG_SESSION_ID='<SESSION_ID>'
/usr/bin/curl -fsS "$HXG_BASE_URL/api/scans/$HXG_SESSION_ID"
```

Repeat the status command until `"is_running":false`, then retrieve all
results:

```bash
/usr/bin/curl -fsS \
  "$HXG_BASE_URL/api/scans/$HXG_SESSION_ID/results?limit=500"
```

Retrieve results for one category from the recorded session:

```bash
HXG_CATEGORY='Auditing'
/usr/bin/curl -fsSG \
  --data-urlencode 'limit=500' \
  --data-urlencode "category=$HXG_CATEGORY" \
  "$HXG_BASE_URL/api/scans/$HXG_SESSION_ID/results"
```

List current rule states for a category without starting another scan:

```bash
HXG_CATEGORY='Operating System'
/usr/bin/curl -fsSG \
  --data-urlencode "category=$HXG_CATEGORY" \
  "$HXG_BASE_URL/api/rules"
```

Retrieve one rule and its recent history:

```bash
HXG_RULE_ID='<RULE_ID>'
/usr/bin/curl -fsS "$HXG_BASE_URL/api/rules/$HXG_RULE_ID"
```

For the detailed cases below, define this read-only helper once. It rejects
unexpected rule-ID characters and retrieves the latest recorded state without
applying a fix:

```bash
hxg_show_rules() {
  for HXG_RULE_ID in "$@"; do
    case "$HXG_RULE_ID" in
      (*[!a-z0-9_-]*|'')
        echo "Invalid rule ID: $HXG_RULE_ID" >&2
        return 2
        ;;
    esac
    printf '\n===== %s =====\n' "$HXG_RULE_ID"
    /usr/bin/curl -fsS "$HXG_BASE_URL/api/rules/$HXG_RULE_ID" || return
    printf '\n'
  done
}
```

For every `hxg_show_rules` result, inspect and record:

| JSON field | PASS criterion |
|---|---|
| `rule` | Exactly matches the requested rule ID |
| `current_status` | `PASS`; or approved `EXEMPT` / justified `NOT_APPLICABLE` |
| `last_scan.status` | `PASS` for a scripted, non-exempt control |
| `last_scan.result_value` | Matches `last_scan.expected_value` |
| `has_scan` | `true`, unless the control is intentionally manual/MDM-only |
| `exemption` | `null`, unless the exception has current approval evidence |

Interpret other values as follows:

- `FAIL` — mark the test FAIL and record the rule ID, observed value, expected
  value, and defect.
- `ERROR` — mark the test FAIL; record the error separately from compliance.
- `NEVER_SCANNED` — mark BLOCKED and run HXG-SCAN-001.
- `MDM_REQUIRED` or `has_scan:false` — do not mark PASS from API output alone.
  Record the profile payload identifier, System Settings observation, or
  approved manual-control artifact named by the test.

Start a category-only scan when a new scan is required:

```bash
HXG_CATEGORY='System Settings'
/usr/bin/curl -fsS \
  -X POST \
  -H 'Content-Type: application/json' \
  -d "{\"filter\":{\"category\":\"$HXG_CATEGORY\"}}" \
  "$HXG_BASE_URL/api/scans"
```

Valid category values are `Auditing`, `Authentication`, `Password Policy`,
`iCloud`, `Operating System`, `System Settings`, and `Other`.

### 4.3 Test summary

| Test ID | Test case | Type | Status | Evidence / defect |
|---|---|---|---|---|
| HXG-BASE-001 | Record device and baseline identity | Read-only |  |  |
| HXG-BASE-002 | Verify service health and localhost binding | Read-only |  |  |
| HXG-BASE-003 | Verify privilege separation and runner connectivity | Read-only |  |  |
| HXG-SCAN-001 | Run the complete compliance scan | Read-only scan |  |  |
| HXG-SCAN-002 | Reconcile scan inventory and result states | Evidence review |  |  |
| HXG-AUD-001 | Verify audit daemon and failure handling | Read-only scan |  |  |
| HXG-AUD-002 | Verify configured audit event flags | Read-only scan |  |  |
| HXG-AUD-003 | Verify audit trail ownership and permissions | Read-only scan |  |  |
| HXG-AUD-004 | Verify retention, capacity, and off-load controls | Mixed evidence |  |  |
| HXG-AUD-005 | Verify system and sudo logging | Mixed evidence |  |  |
| HXG-AUTH-002 | Verify password policy | Read-only scan |  |  |
| HXG-AUTH-003 | Verify five-attempt lockout and manual recovery posture | Read-only |  |  |
| HXG-AUTH-004 | Verify authenticator-change re-authentication | Controlled |  |  |
| HXG-ICLD-001 | Verify iCloud and cloud-service isolation | Profile / UI |  |  |
| HXG-OS-001 | Verify boot and code integrity | Mixed evidence |  |  |
| HXG-OS-002 | Verify code-execution protections | Mixed evidence |  |  |
| HXG-OS-003 | Verify unnecessary network services are disabled | Mixed evidence |  |  |
| HXG-OS-004 | Verify SSH hardening or disabled state | Mixed evidence |  |  |
| HXG-OS-005 | Verify Apple Intelligence restrictions | Profile / UI |  |  |
| HXG-OS-006 | Verify FileVault and automatic-login posture | Mixed evidence |  |  |
| HXG-OS-007 | Verify identity and privileged-access controls | Mixed evidence |  |  |
| HXG-OS-008 | Verify cryptographic controls | Mixed evidence |  |  |
| HXG-OS-009 | Verify filesystem and home-folder permissions | Read-only scan |  |  |
| HXG-OS-010 | Verify Safari hardening | Profile / scan |  |  |
| HXG-OS-011 | Verify sudo policy | Read-only scan |  |  |
| HXG-OS-012 | Verify power and sleep policy | Profile / scan |  |  |
| HXG-SYS-001 | Verify interfaces and sharing services | Mixed evidence |  |  |
| HXG-SYS-002 | Verify application firewall and stealth mode | Mixed evidence |  |  |
| HXG-SYS-003 | Verify Bluetooth restrictions | Mixed evidence |  |  |
| HXG-SYS-004 | Verify session-lock controls | Controlled |  |  |
| HXG-SYS-005 | Verify login-window controls | Controlled |  |  |
| HXG-SYS-006 | Verify software-update and time controls | Profile / scan |  |  |
| HXG-SYS-007 | Verify privacy, telemetry, Siri, and location controls | Profile / UI |  |  |
| HXG-SYS-008 | Verify Time Machine policy | Mixed evidence |  |  |
| HXG-SYS-009 | Verify USB Restricted Mode and whitelist enforcement | Controlled |  |  |
| HXG-SUP-001 | Verify supplemental and manual-control evidence | Evidence review |  |  |
| HXG-SEC-001 | Verify sensitive actions require admin 2FA | Controlled |  |  |
| HXG-SEC-002 | Verify security actions are audit logged | Controlled |  |  |
| HXG-REP-001 | Verify report and evidence export | Read-only |  |  |
| HXG-PERS-001 | Verify hardening persists after reboot | Controlled reboot |  |  |
| HXG-CLOSE-001 | Reconcile exceptions, failures, and residual risk | Evidence review |  |  |

## 5. Baseline and scan verification

### HXG-BASE-001 — Record device and baseline identity

**Purpose:** Establish traceability between the test evidence, device, operating
system, application build, and selected security baseline.

**Prerequisites:** Read-only access to the dashboard and local macOS system
information.

**Execution steps:**

1. Record the device asset ID without recording its serial number unless the
   evidence-handling policy permits it.
2. Record the macOS version, build, hardware model, and architecture:

   ```bash
   /usr/bin/sw_vers
   /usr/bin/uname -m
   /usr/sbin/sysctl -n hw.model
   ```

3. Retrieve the application-reported version:

   ```bash
   HXG_BASE_URL='http://127.0.0.1:8000'
   /usr/bin/curl -fsS "$HXG_BASE_URL/api/health"
   ```

4. Record the `version` field and compare it with the release manifest or
   approved commit/tag supplied with the bundle.
5. Record the selected baseline from the test authorization and the unified
   profile display name/identifier shown in System Settings → General → Device
   Management.
6. Record the release/change-ticket ID. If no release reference or baseline is
   supplied, mark BLOCKED.

**Expected result:**

- The test record uniquely identifies the device and software under test.
- The selected baseline is one of NIST 800-53r5 High, CIS Controls v8, or CIS
  macOS Benchmark Level 2.
- Version information matches the approved release package.

**Actual result:**

> Device / OS / HX-Guardian / baseline observed:

**Status:** ☐ PASS ☐ FAIL ☐ BLOCKED ☐ NOT APPLICABLE

**Evidence / defect reference:**

>

### HXG-BASE-002 — Verify service health and localhost binding

**Purpose:** Confirm that the dashboard is healthy and is not exposed on a
non-loopback interface.

**Prerequisites:** HX-Guardian services are expected to be running.

**Execution steps:**

1. Open `http://127.0.0.1:8000` locally and confirm the dashboard loads.
2. Run:

   ```bash
   curl -s http://127.0.0.1:8000/api/health
   ```

3. Run the following read-only listener check:

   ```bash
   /usr/sbin/lsof -nP -iTCP:8000 -sTCP:LISTEN
   ```

4. Confirm the listener address is `127.0.0.1:8000` and is not `0.0.0.0`,
   `[::]`, or a physical-interface address.

**Expected result:**

- The dashboard and health endpoint respond locally.
- Health reports `status: "ok"` and `ready: true`.
- Port 8000 listens only on IPv4 loopback.
- No physical or wildcard interface exposes the dashboard.

**Actual result:**

> Health response and listener address:

**Status:** ☐ PASS ☐ FAIL ☐ BLOCKED ☐ NOT APPLICABLE

**Evidence / defect reference:**

>

### HXG-BASE-003 — Verify privilege separation and runner connectivity

**Purpose:** Confirm the web server remains unprivileged while privileged scan
execution remains isolated behind the runner.

**Prerequisites:** HX-Guardian services are expected to be running.

**Execution steps:**

1. Run:

   ```bash
   HXG_BASE_URL='http://127.0.0.1:8000'
   /usr/bin/curl -fsS "$HXG_BASE_URL/api/runner/status"
   ```

2. Review the installed service/process inventory:

   ```bash
   /bin/ps -axo user=,pid=,comm= |
     /usr/bin/grep -E 'hxg-(server|runner|usb-watcher|shell-watcher)'
   ```

3. Confirm the server runs as the configured non-root admin user.
4. Inspect the runner socket and containing directory:

   ```bash
   /bin/ls -ld /var/run/hxg
   /bin/ls -l /var/run/hxg/runner.sock
   ```

5. From `ps`, require `hxg-server` to run as the configured admin user and
   `hxg-runner`, `hxg-usb-watcher`, and `hxg-shell-watcher` to run as root.
6. Record the owner, group, and mode printed for `/var/run/hxg` and
   `runner.sock`; compare them with the installed launchd/installer release
   evidence. Group/world write access outside the documented service group is
   FAIL.
7. In Dashboard → Rules, confirm only manifest rule IDs can be selected. Do
   not probe the runner with an invented path or command.

**Expected result:**

- Runner status reports `runner_connected: true`.
- The FastAPI server does not run as root.
- Privileged actions cross the documented Unix-socket boundary.
- Only manifest-listed scripts can be selected for execution.

**Actual result:**

> Runner response, process identities, and boundary observations:

**Status:** ☐ PASS ☐ FAIL ☐ BLOCKED ☐ NOT APPLICABLE

**Evidence / defect reference:**

>

### HXG-SCAN-001 — Run the complete compliance scan

**Purpose:** Produce current per-rule evidence without applying remediation.

**Prerequisites:** Runner connected; no fix operation is authorized by this
case.

**Execution steps:**

1. Start the full read-only scan:

   ```bash
   HXG_BASE_URL='http://127.0.0.1:8000'
   /usr/bin/curl -fsS \
     -X POST \
     -H 'Content-Type: application/json' \
     -d '{"filter":null}' \
     "$HXG_BASE_URL/api/scans"
   ```

2. Copy `session_id` from the JSON response, then poll:

   ```bash
   HXG_SESSION_ID='<SESSION_ID>'
   /usr/bin/curl -fsS "$HXG_BASE_URL/api/scans/$HXG_SESSION_ID"
   ```

   Repeat only this GET command until `"is_running":false`.
3. Record the scan session ID and completion time.
4. Record counts for PASS, FAIL, ERROR, NOT_APPLICABLE, MDM_REQUIRED, and
   EXEMPT.
5. Do not select **Apply Fix** for any failed result.
6. Retrieve and save the session response in the Actual result field. Require
   `"is_running":false`, `"total_rules":268`, and `"error_count":0`.

**Expected result:**

- The scan completes without runner disconnection or timeout.
- The session contains 268 total rule results.
- `ERROR` count is zero.
- Every `FAIL`, `MDM_REQUIRED`, and `EXEMPT` result is carried into later
  manual review; none is silently treated as verified compliance.

**Actual result:**

> Session ID, duration, and result counts:

**Status:** ☐ PASS ☐ FAIL ☐ BLOCKED ☐ NOT APPLICABLE

**Evidence / defect reference:**

>

### HXG-SCAN-002 — Reconcile scan inventory and result states

**Purpose:** Confirm the test evidence covers the complete manifest.

**Prerequisites:** HXG-SCAN-001 completed.

**Execution steps:**

1. Retrieve the manifest metadata and current scan results:

   ```bash
   HXG_BASE_URL='http://127.0.0.1:8000'
   HXG_SESSION_ID='<SESSION_ID>'
   /usr/bin/curl -fsS "$HXG_BASE_URL/api/rules/meta"
   /usr/bin/curl -fsS \
     "$HXG_BASE_URL/api/scans/$HXG_SESSION_ID/results?limit=500"
   ```

2. Compare the scan category totals with the current manifest inventory.
3. Confirm the expected category counts: Auditing 28, Authentication 7,
   Password Policy 15, iCloud 14, Operating System 129, System Settings 69,
   and Other 6.
4. Confirm every active exemption has an owner, reason, approval reference,
   and valid expiry or permanent-exception basis.
5. Retrieve the exemption inventory:

   ```bash
   /usr/bin/curl -fsS "$HXG_BASE_URL/api/exemptions"
   ```

   For every active entry, record `rule`, `reason`, `granted_by`,
   `granted_at`, and `expires_at`. `is_expired:true` or blank justification is
   FAIL.
6. Retrieve rules requiring manual/profile evidence:

   ```bash
   /usr/bin/curl -fsSG \
     --data-urlencode 'status=MDM_REQUIRED' \
     "$HXG_BASE_URL/api/rules"
   ```

   Record one evidence reference for every returned rule.
7. Retrieve execution errors:

   ```bash
   /usr/bin/curl -fsSG \
     --data-urlencode 'status=ERROR' \
     "$HXG_BASE_URL/api/rules"
   ```

8. Open every `ERROR` result and record its execution failure separately from
   the control state.

**Expected result:**

- The category counts reconcile to 268 rules.
- No rule is missing from the scan or manual-evidence set.
- No expired, unexplained, or unapproved exemption is accepted.
- No execution error is recorded as PASS.

**Actual result:**

> Reconciliation totals and exceptions:

**Status:** ☐ PASS ☐ FAIL ☐ BLOCKED ☐ NOT APPLICABLE

**Evidence / defect reference:**

>

## 6. Auditing and logging

For HXG-AUD cases, retrieve the completed category results before reviewing
individual controls:

```bash
HXG_BASE_URL='http://127.0.0.1:8000'
HXG_SESSION_ID='<SESSION_ID>'
HXG_CATEGORY='Auditing'
/usr/bin/curl -fsSG \
  --data-urlencode 'limit=500' \
  --data-urlencode "category=$HXG_CATEGORY" \
  "$HXG_BASE_URL/api/scans/$HXG_SESSION_ID/results"
```

### HXG-AUD-001 — Verify audit daemon and failure handling

**Execution steps:**

1. Retrieve the three exact rules:

   ```bash
   hxg_show_rules \
     audit_auditd_enabled \
     audit_failure_halt \
     audit_settings_failure_notify
   ```

2. For each JSON response, apply the field criteria in §4.2 and record
   `current_status`, `result_value`, and `expected_value`.
3. Inspect the effective audit policy without changing it:

   ```bash
   /usr/bin/awk -F: \
     '/^(flags|policy|minfree|expire-after):/{print $1 ":" $2}' \
     /etc/security/audit_control
   ```

4. Confirm the `policy:` output contains the audit-failure behavior required
   by `audit_failure_halt`; use the rule JSON as the authoritative
   interpretation.
5. If a command returns no output or permission denied, record the exact
   message and mark the case BLOCKED rather than changing permissions.

**Expected result:**

- Security auditing is enabled.
- Audit-failure handling and notification match the approved hardening policy.
- All three control outcomes have current evidence and no unexplained failure.

**Actual result:**

> Rule IDs, statuses, and evidence:

**Status:** ☐ PASS ☐ FAIL ☐ BLOCKED ☐ NOT APPLICABLE

**Evidence / defect reference:**

>

### HXG-AUD-002 — Verify configured audit event flags

**Execution steps:**

1. Retrieve every required flag rule:

   ```bash
   hxg_show_rules \
     audit_flags_aa_configure \
     audit_flags_ad_configure \
     audit_flags_ex_configure \
     audit_flags_fd_configure \
     audit_flags_fm_failed_configure \
     audit_flags_fr_configure \
     audit_flags_fw_configure \
     audit_flags_lo_configure
   ```

2. Display the configured flag line:

   ```bash
   /usr/bin/awk -F: '/^flags:/{print $2}' /etc/security/audit_control
   ```

3. Verify each JSON result is `PASS`.
4. Confirm the output covers successful or failed forms required by the eight
   rule checks: `aa`, `ad`, `ex`, `fd`, `fm`, `fr`, `fw`, and `lo`.
5. For any non-PASS result, record its exact `result_value` and
   `expected_value`; do not infer compliance from the combined flag line.

**Expected result:**

- All required event flags are present in the effective audit configuration.
- No required flag is missing or malformed.

**Actual result:**

> Observed flags and related rule statuses:

**Status:** ☐ PASS ☐ FAIL ☐ BLOCKED ☐ NOT APPLICABLE

**Evidence / defect reference:**

>

### HXG-AUD-003 — Verify audit trail ownership and permissions

**Execution steps:**

1. Retrieve the exact ownership, mode, and ACL rules:

   ```bash
   hxg_show_rules \
     audit_control_owner_configure \
     audit_control_group_configure \
     audit_control_mode_configure \
     audit_control_acls_configure \
     audit_files_owner_configure \
     audit_files_group_configure \
     audit_files_mode_configure \
     audit_acls_files_configure \
     audit_folder_owner_configure \
     audit_folder_group_configure \
     audit_folders_mode_configure \
     audit_acls_folders_configure
   ```

2. Inspect the control-file metadata:

   ```bash
   /usr/bin/stat -f '%Su:%Sg %Lp %N' /etc/security/audit_control
   /bin/ls -lde /etc/security/audit_control
   ```

3. Display the configured audit directory path without listing audit-record
   contents:

   ```bash
   /usr/bin/awk -F: '/^dir:/{print $2}' /etc/security/audit_control
   ```

4. Confirm `/etc/security/audit_control` reports `root:wheel` and mode `440`
   or stricter. In `ls -lde` output, confirm there are no numbered ACL entries.
5. Use the JSON results to verify the configured audit directory and its files;
   do not list or copy audit-record contents.
6. Record every failing path and rule ID, but not the contents of the file.

**Expected result:**

- `audit_control` and audit log files are owned by `root:wheel`, have mode 440
  or a stricter approved mode, and do not carry unauthorized ACLs.
- Audit folders are owned by `root:wheel` and have mode 700 or a stricter
  approved mode.
- Audit record integrity/protection evidence is present.

**Actual result:**

> Rule statuses and permission observations:

**Status:** ☐ PASS ☐ FAIL ☐ BLOCKED ☐ NOT APPLICABLE

**Evidence / defect reference:**

>

### HXG-AUD-004 — Verify retention, capacity, and off-load controls

**Execution steps:**

1. Retrieve the scripted and manual rules:

   ```bash
   hxg_show_rules \
     audit_retention_configure \
     audit_configure_capacity_notify \
     audit_off_load_records \
     audit_record_reduction_report_generation \
     audit_records_processing \
     os_crypto_audit \
     os_non_repudiation
   ```

2. Verify the first two rules are `PASS`. The final three should report
   `has_scan:false` or `MDM_REQUIRED` and require the artifacts below.
3. Display the configured retention and capacity values:

   ```bash
   /usr/bin/awk -F: \
     '/^(expire-after|minfree):/{print $1 ":" $2}' \
     /etc/security/audit_control
   ```

4. Record the literal `expire-after` and `minfree` values.
5. For `audit_off_load_records`, record the approved procedure document ID,
   destination class, owner, frequency, and last successful off-load evidence.
6. For the two reduction/reporting rules, record one generated report ID and
   confirm its source scan/audit records remain present after generation.
7. If any required manual artifact is missing or expired, mark FAIL and name
   the missing artifact.

**Expected result:**

- Retention and capacity thresholds match approved policy.
- Audit off-load has a documented owner, destination, frequency, and integrity
  control.
- Report generation does not modify the source audit records.

**Actual result:**

> Observed settings and procedure references:

**Status:** ☐ PASS ☐ FAIL ☐ BLOCKED ☐ NOT APPLICABLE

**Evidence / defect reference:**

>

### HXG-AUD-005 — Verify system and sudo logging

**Execution steps:**

1. Retrieve the exact log-control rules:

   ```bash
   hxg_show_rules \
     os_asl_log_files_owner_group_configure \
     os_asl_log_files_permissions_configure \
     os_newsyslog_files_owner_group_configure \
     os_newsyslog_files_permissions_configure \
     os_install_log_retention_configure \
     os_sudo_log_enforce
   ```

2. Verify each JSON response is `PASS`.
3. Inspect relevant configuration metadata without reading log contents:

   ```bash
   /usr/bin/stat -f '%Su:%Sg %Lp %N' \
     /etc/asl.conf \
     /etc/newsyslog.conf
   ```

4. Confirm the two configuration files are owned by an approved system owner
   and are not group/world writable; the per-log rules remain authoritative
   for individual log files.
5. In Dashboard → Audit Log, select **All Actions**, record the latest
   timestamp, then start a single read-only rule scan from Rules.
6. Refresh Audit Log and record the new scan action and completion timestamps.
   Do not perform a privileged configuration change merely to generate
   evidence.

**Expected result:**

- System log files meet approved ownership, mode, and retention requirements.
- Sudo or privileged operator activity is recorded in the intended audit
  source.
- Evidence includes timestamp and actor attribution where the platform exposes
  it.

**Actual result:**

> Rule statuses and observed audit event:

**Status:** ☐ PASS ☐ FAIL ☐ BLOCKED ☐ NOT APPLICABLE

**Evidence / defect reference:**

>

## 7. Authentication and identity

Retrieve the Password Policy category. SSH authentication is tested in
HXG-OS-004. Hardware-token controls are excluded as documented above.

```bash
HXG_BASE_URL='http://127.0.0.1:8000'
HXG_SESSION_ID='<SESSION_ID>'
/usr/bin/curl -fsSG \
  --data-urlencode 'limit=500' \
  --data-urlencode 'category=Password Policy' \
  "$HXG_BASE_URL/api/scans/$HXG_SESSION_ID/results"
```

### HXG-AUTH-002 — Verify password policy

**Execution steps:**

1. Retrieve all 15 Password Policy rules:

   ```bash
   hxg_show_rules \
     pwpolicy_account_inactivity_enforce \
     pwpolicy_account_lockout_enforce \
     pwpolicy_account_lockout_timeout_enforce \
     pwpolicy_alpha_numeric_enforce \
     pwpolicy_custom_regex_enforce \
     pwpolicy_emergency_accounts_disable \
     pwpolicy_force_password_change \
     pwpolicy_history_enforce \
     pwpolicy_max_lifetime_enforce \
     pwpolicy_minimum_length_enforce \
     pwpolicy_minimum_lifetime_enforce \
     pwpolicy_simple_sequence_disable \
     pwpolicy_special_character_enforce \
     pwpolicy_temporary_accounts_disable \
     pwpolicy_temporary_or_emergency_accounts_disable \
     os_obscure_password \
     os_store_encrypted_passwords \
     os_password_hint_remove \
     system_settings_password_hints_disable \
     os_provide_automated_account_management
   ```

2. Display the effective account policy. This output contains policy
   configuration, not password hashes:

   ```bash
   /usr/bin/pwpolicy -getaccountpolicies 2>/dev/null
   ```

3. Retrieve the exemption inventory:

   ```bash
   /usr/bin/curl -fsS "$HXG_BASE_URL/api/exemptions"
   ```

4. Require these enforced rules to be `PASS`:

   - `pwpolicy_account_lockout_enforce` — maximum 5 failed attempts.
   - `pwpolicy_alpha_numeric_enforce` — alphanumeric requirement.
   - `pwpolicy_minimum_length_enforce` — minimum 15 characters.
   - `pwpolicy_special_character_enforce` — at least one special character.

5. Require these seven rules to be active, permanent `EXEMPT` entries with
   `is_expired:false` and the safety reason configured by
   `app/rules_setup.sh`:

   - `pwpolicy_account_inactivity_enforce`
   - `pwpolicy_account_lockout_timeout_enforce`
   - `pwpolicy_custom_regex_enforce`
   - `pwpolicy_history_enforce`
   - `pwpolicy_max_lifetime_enforce`
   - `pwpolicy_minimum_lifetime_enforce`
   - `pwpolicy_simple_sequence_disable`

   Do not require these rules to PASS and do not run their fix scripts.
6. For each of the four `has_scan:false` lifecycle rules, record the account
   management procedure ID, responsible owner, last review date, and one
   sanitized sample record demonstrating the required action.
7. For `os_password_hint_remove`,
   `system_settings_password_hints_disable`, `os_obscure_password`,
   `os_store_encrypted_passwords`, and
   `os_provide_automated_account_management`, apply the normal rule/manual
   evidence criteria from §4.2.
8. If the raw policy, exemption inventory, and rule JSON disagree, record all
   values and mark FAIL;
   do not choose the more favorable result.

**Expected result:**

- The four locally/profile-enforced password controls are PASS.
- The seven Tahoe-incompatible controls are active permanent exemptions with
  the exact deployment safety rationale.
- Password hints are absent.
- Stored passwords are protected by the operating system and password entry is
  obscured.
- Manual-only controls have current evidence.

**Actual result:**

> Policy values, rule statuses, and manual evidence:

**Status:** ☐ PASS ☐ FAIL ☐ BLOCKED ☐ NOT APPLICABLE

**Evidence / defect reference:**

>

### HXG-AUTH-003 — Verify five-attempt lockout and manual recovery posture

**Test type:** Read-only. Do not intentionally fail authentication or lock an
account.

**Execution steps:**

1. Retrieve the exact lockout rules:

   ```bash
   hxg_show_rules \
     pwpolicy_account_lockout_enforce \
     pwpolicy_account_lockout_timeout_enforce
   ```

2. Extract the configured maximum failed-authentication count:

   ```bash
   /usr/bin/pwpolicy -getaccountpolicies 2>/dev/null |
     /usr/bin/tail -n +2 |
     /usr/bin/xmllint \
       --xpath '//dict/key[text()="policyAttributeMaximumFailedAuthentications"]/following-sibling::integer[1]/text()' -
   ```

3. Require the command output to equal `5` and
   `pwpolicy_account_lockout_enforce` to be `PASS`.
4. Query exemptions:

   ```bash
   /usr/bin/curl -fsS "$HXG_BASE_URL/api/exemptions"
   ```

5. Require `pwpolicy_account_lockout_timeout_enforce` to be active, permanent
   `EXEMPT` with the reason that automatic recovery requires an MDM-delivered
   policy and is not enforced locally to avoid a login trap.
6. Open [Airgap Device Admin & Operator Guide](airgap_readme.md), §11.2, and
   record the manual admin recovery procedure/version and responsible role.
   Do not execute the recovery command during this test.
7. Confirm the evidence explicitly states: five failed attempts trigger
   lockout; there is no automatic timeout; recovery requires an administrator.

**Expected result:**

- The enforced threshold is exactly five failed authentications.
- `pwpolicy_account_lockout_enforce` is PASS.
- `pwpolicy_account_lockout_timeout_enforce` is a current permanent exemption,
  not PASS or unapproved FAIL.
- Manual administrator recovery is documented and no account is altered by
  this test.

**Actual result:**

> Threshold value, timeout exemption, and recovery procedure reference:

**Status:** ☐ PASS ☐ FAIL ☐ BLOCKED ☐ NOT APPLICABLE

**Evidence / defect reference:**

>

### HXG-AUTH-004 — Verify authenticator-change re-authentication

**Test type:** Controlled. Use a disposable account or approved maintenance
window.

**Execution steps:**

1. Retrieve the two manual rules:

   ```bash
   hxg_show_rules \
     os_reauth_devices_change_authenticators \
     os_reauth_users_change_authenticators
   ```

2. Record the manual test account and maintenance approval ID.
3. For a user authenticator, open System Settings → Users & Groups → the
   approved test user → **Change Password**.
4. Confirm macOS requests the current password or an administrator credential
   before accepting a replacement; cancel without entering a new credential.
5. For a device authenticator, open only the approved device-authenticator
   management flow named in the site procedure. Confirm re-authentication is
   requested, then cancel.
6. Record the prompt text and cancellation outcome. Mark BLOCKED if no safe
   test account or documented device flow is available.

**Expected result:**

- Authenticator changes cannot complete without re-authentication.
- Canceling the test leaves the current authenticator unchanged.

**Actual result:**

> Flow tested and prompt observed:

**Status:** ☐ PASS ☐ FAIL ☐ BLOCKED ☐ NOT APPLICABLE

**Evidence / defect reference:**

>

## 8. iCloud and cloud-service isolation

Retrieve iCloud rule states without reading Apple ID account data:

```bash
HXG_BASE_URL='http://127.0.0.1:8000'
HXG_SESSION_ID='<SESSION_ID>'
HXG_CATEGORY='iCloud'
/usr/bin/curl -fsSG \
  --data-urlencode 'limit=500' \
  --data-urlencode "category=$HXG_CATEGORY" \
  "$HXG_BASE_URL/api/scans/$HXG_SESSION_ID/results"
```

Do not use `defaults read MobileMeAccounts` or attach account-database output
as evidence.

### HXG-ICLD-001 — Verify iCloud and cloud-service isolation

**Execution steps:**

1. Retrieve all 14 iCloud rule states:

   ```bash
   hxg_show_rules \
     icloud_addressbook_disable \
     icloud_appleid_system_settings_disable \
     icloud_bookmarks_disable \
     icloud_calendar_disable \
     icloud_drive_disable \
     icloud_freeform_disable \
     icloud_game_center_disable \
     icloud_keychain_disable \
     icloud_mail_disable \
     icloud_notes_disable \
     icloud_photos_disable \
     icloud_private_relay_disable \
     icloud_reminders_disable \
     icloud_sync_disable \
     os_appleid_prompt_disable \
     os_icloud_storage_prompt_disable \
     os_account_modification_disable
   ```

2. Confirm the 14 iCloud responses and three Apple-ID/setup restrictions are
   `PASS`; record any `FAIL`, `ERROR`, or unexpected exemption by rule ID.
3. Confirm the HX-Guardian unified profile is present in System Settings →
   General → Device Management.
4. Open System Settings → Apple Account. Confirm sign-in and managed iCloud
   controls are unavailable or disabled; do not sign in.
5. Confirm Address Book, Bookmarks, Calendar, Drive, Desktop & Documents,
   Freeform, Game Center, Keychain, Mail, Notes, Photos, Private Relay, and
   Reminders synchronization are disabled.
6. Record the profile display name, identifier, and installation status without
   exporting the profile payload or account data.

**Expected result:**

- The unified profile is installed and reports no unresolved installation
  error.
- All 14 cloud-service restrictions have current evidence.
- The device has no active Apple ID or iCloud synchronization.

**Actual result:**

> Profile state and observed restrictions:

**Status:** ☐ PASS ☐ FAIL ☐ BLOCKED ☐ NOT APPLICABLE

**Evidence / defect reference:**

>

## 9. Operating system hardening

Retrieve Operating System results:

```bash
HXG_BASE_URL='http://127.0.0.1:8000'
HXG_SESSION_ID='<SESSION_ID>'
HXG_CATEGORY='Operating System'
/usr/bin/curl -fsSG \
  --data-urlencode 'limit=500' \
  --data-urlencode "category=$HXG_CATEGORY" \
  "$HXG_BASE_URL/api/scans/$HXG_SESSION_ID/results"
```

### HXG-OS-001 — Verify boot and code integrity

**Execution steps:**

1. Retrieve the exact boot and integrity rules:

   ```bash
   hxg_show_rules \
     os_sip_enable \
     os_secure_boot_verify \
     os_authenticated_root_enable \
     os_system_read_only \
     os_mobile_file_integrity_enable \
     os_library_validation_enabled \
     os_firmware_password_require \
     os_recover_lock_enable \
     os_recovery_lock_enable \
     os_fail_secure_state
   ```

2. Run the read-only platform checks:

   ```bash
   /usr/bin/csrutil status
   /usr/bin/csrutil authenticated-root status
   /usr/sbin/system_profiler SPiBridgeDataType
   ```

   Review `system_profiler` output before attaching it because hardware
   identifiers may require redaction.

3. Confirm the applicable integrity rules are `PASS`. For a
   `NOT_APPLICABLE` result, record the hardware model/architecture and the
   rule's message.
4. For firmware password or Recovery Lock, record which hardware-specific
   control applies and verify that rule is `PASS`; do not attempt to enter
   Recovery merely to test the lock.
5. Record the literal output of both `csrutil` commands. Any disabled or
   unknown state is FAIL.

**Expected result:**

- SIP, Authenticated Root, system-volume protection, AMFI, and Library
  Validation are enabled.
- Secure Boot is Full where supported.
- Firmware password or Recovery Lock meets the approved hardware-specific
  requirement.

**Actual result:**

> Observed integrity states and hardware-specific evidence:

**Status:** ☐ PASS ☐ FAIL ☐ BLOCKED ☐ NOT APPLICABLE

**Evidence / defect reference:**

>

### HXG-OS-002 — Verify code-execution protections

**Execution steps:**

1. Retrieve the exact scripted and manual protection rules:

   ```bash
   hxg_show_rules \
     os_gatekeeper_enable \
     system_settings_gatekeeper_identified_developers_allowed \
     system_settings_gatekeeper_override_disallow \
     os_application_sandboxing \
     os_implement_memory_protection \
     os_anti_virus_installed \
     os_config_data_install_enforce \
     os_config_profile_ui_install_disable \
     os_rapid_security_response_allow \
     os_rapid_security_response_removal_disable \
     os_malicious_code_prevention \
     os_ess_installed \
     os_information_validation \
     os_isolate_security_functions \
     os_separate_functionality
   ```

2. Run:

   ```bash
   /usr/sbin/spctl --status
   /usr/bin/xprotect status
   ```

3. Confirm Gatekeeper, override prevention, antivirus, and configuration-data
   scripted rules are `PASS`.
4. Record `spctl` output containing `assessments enabled`. Record the `xprotect`
   status fields used by `os_anti_virus_installed`; if the command is
   unavailable on the tested macOS version, retain the scan result and mark
   the independent check BLOCKED.
5. For each `has_scan:false` rule, record the approved platform-assurance or
   profile artifact ID and review date. Missing evidence is FAIL.
6. Do not download or execute an untrusted sample to test these controls.

**Expected result:**

- Gatekeeper allows only approved identified-developer policy and users cannot
  bypass it.
- Platform malware, sandbox, and memory protections are enabled.
- Security response and protection-data updates are enforced as documented.

**Actual result:**

> Rule statuses and protection evidence:

**Status:** ☐ PASS ☐ FAIL ☐ BLOCKED ☐ NOT APPLICABLE

**Evidence / defect reference:**

>

### HXG-OS-003 — Verify unnecessary network services are disabled

**Execution steps:**

1. Retrieve every prohibited-service rule:

   ```bash
   hxg_show_rules \
     os_airdrop_disable \
     os_bonjour_disable \
     os_handoff_disable \
     os_iphone_mirroring_disable \
     os_ir_support_disable \
     os_httpd_disable \
     os_nfsd_disable \
     os_tftpd_disable \
     os_uucp_disable \
     os_nonlocal_maintenance \
     os_prohibit_remote_activation_collab_devices \
     os_secure_name_resolution
   ```

2. Confirm each rule is `PASS` or has a specifically approved exemption.
3. Review current listening services:

   ```bash
   /usr/sbin/lsof -nP -iTCP -sTCP:LISTEN
   /usr/sbin/lsof -nP -iUDP
   ```

4. Search the output for ports/services associated with HTTP, NFS, TFTP, and
   other prohibited listeners. Record process name, protocol, and local
   address; redact remote/network identifiers.
5. Any active prohibited listener without an approved exception is FAIL even
   if its scan result is stale PASS.

**Expected result:**

- Every prohibited network service is disabled.
- No prohibited service has an active listener or advertised sharing state.

**Actual result:**

> Rule statuses and unexpected listeners, if any:

**Status:** ☐ PASS ☐ FAIL ☐ BLOCKED ☐ NOT APPLICABLE

**Evidence / defect reference:**

>

### HXG-OS-004 — Verify SSH hardening or disabled state

**Execution steps:**

1. Record the site decision: **SSH disabled** or **SSH approved and hardened**,
   including its approval reference.
2. Retrieve the exact SSH rules:

   ```bash
   hxg_show_rules \
     auth_ssh_password_authentication_disable \
     system_settings_ssh_disable \
     system_settings_ssh_enable \
     os_ssh_fips_compliant \
     os_sshd_fips_compliant \
     os_sshd_permit_root_login_configure \
     os_ssh_server_alive_interval_configure \
     os_ssh_server_alive_count_max_configure \
     os_sshd_client_alive_interval_configure \
     os_sshd_client_alive_count_max_configure \
     os_sshd_channel_timeout_configure \
     os_sshd_unused_connection_timeout_configure \
     os_sshd_per_source_penalties_configure \
     os_policy_banner_ssh_configure \
     os_policy_banner_ssh_enforce
   ```

3. Check for an SSH listener:

   ```bash
   /usr/sbin/lsof -nP -iTCP:22 -sTCP:LISTEN
   ```

   No output is expected when SSH is disabled.

4. If SSH is disabled, require `system_settings_ssh_disable=PASS`, no port 22
   listener, and no exception that enables SSH. Record
   `system_settings_ssh_enable` according to the baseline/exemption model
   rather than treating the contradictory rule as proof to enable SSH.
5. If SSH is approved, require every applicable FIPS, root-login,
   password-authentication, timeout, penalty, and banner rule to be `PASS`;
   record any baseline conflict or exemption individually.
6. Do not enable SSH solely to execute this case.

**Expected result:**

- SSH is disabled, or every approved SSH hardening requirement is enforced.
- Root and password-based SSH authentication are unavailable.
- Any SSH exception is documented and approved.

**Actual result:**

> Approved posture and observed SSH state:

**Status:** ☐ PASS ☐ FAIL ☐ BLOCKED ☐ NOT APPLICABLE

**Evidence / defect reference:**

>

### HXG-OS-005 — Verify Apple Intelligence restrictions

**Execution steps:**

1. Retrieve the complete Apple Intelligence rule set:

   ```bash
   hxg_show_rules \
     os_image_playground_disable \
     os_genmoji_disable \
     os_writing_tools_disable \
     os_mail_smart_reply_disable \
     os_mail_summary_disable \
     os_notes_transcription_disable \
     os_notes_transcription_summary_disable \
     os_safari_reader_summary_disable \
     os_photos_enhanced_search_disable \
     system_settings_external_intelligence_disable \
     system_settings_external_intelligence_sign_in_disable \
     os_skip_apple_intelligence_enable \
     os_siri_prompt_disable
   ```

2. Confirm every rule is `PASS`. Record unsupported hardware/version results as
   `NOT_APPLICABLE` only when the rule message explains the basis.
3. Open System Settings → Apple Intelligence & Siri. Confirm Apple
   Intelligence and external integration sign-in cannot be enabled by the
   operator.
4. Confirm Image Playground, Genmoji, Writing Tools, Mail Smart Replies and
   Summary, Notes transcription/summary, Safari Reader Summary, Photos
   Enhanced Visual Search, and external intelligence integrations are
   disabled.
5. Confirm external intelligence sign-in and Setup Assistant enablement are
   blocked.

**Expected result:**

- Every listed Apple Intelligence and generative-AI function is disabled or
  unavailable.
- No external intelligence account is connected.

**Actual result:**

> Profile payload evidence and UI observations:

**Status:** ☐ PASS ☐ FAIL ☐ BLOCKED ☐ NOT APPLICABLE

**Evidence / defect reference:**

>

### HXG-OS-006 — Verify FileVault and automatic-login posture

**Execution steps:**

1. Retrieve all FileVault and automatic-login rules:

   ```bash
   hxg_show_rules \
     system_settings_filevault_enforce \
     os_setup_assistant_filevault_enforce \
     os_filevault_autologin_disable \
     system_settings_automatic_login_disable \
     os_filevault_authorized_users \
     supplemental_filevault
   ```

2. Open System Settings → Privacy & Security → FileVault.
3. Confirm the command-line status:

   ```bash
   /usr/bin/fdesetup status
   /usr/bin/defaults read \
     /Library/Preferences/com.apple.loginwindow autoLoginUser 2>/dev/null
   ```

   `autoLoginUser` should be absent. Do not run `fdesetup list`, because its
   user inventory is not needed for routine evidence.

4. Require the four scripted rules to be `PASS`.
5. Confirm `fdesetup status` reports FileVault is On.
6. Confirm `autoLoginUser` produces no configured username. If it prints a
   username, mark FAIL and redact it from evidence.
7. For `os_filevault_authorized_users` and `supplemental_filevault`, record the
   approved escrow/authorized-user procedure ID and last review date.
8. Review the authorized FileVault user list through the approved
   administration view without recording recovery keys.

**Expected result:**

- FileVault is enabled and enforced.
- Automatic login is disabled.
- Only approved users can unlock the encrypted volume.
- No recovery key appears in the test evidence.

**Actual result:**

> FileVault status and authorized-user review:

**Status:** ☐ PASS ☐ FAIL ☐ BLOCKED ☐ NOT APPLICABLE

**Evidence / defect reference:**

>

### HXG-OS-007 — Verify identity and privileged-access controls

**Execution steps:**

1. Retrieve the exact identity/access rules:

   ```bash
   hxg_show_rules \
     os_root_disable \
     os_limit_gui_sessions \
     os_unlock_active_user_session_disable \
     os_loginwindow_adminhostinfo_disabled \
     os_unique_identification \
     os_mdm_require \
     os_mfa_network_access \
     os_directory_services_configured \
     os_identify_non-org_users \
     os_enforce_access_restrictions \
     os_logical_access \
     os_managed_access_control_points \
     os_prevent_priv_functions \
     os_prevent_unauthorized_disclosure \
     system_settings_system_wide_preferences_configure \
     os_terminal_secure_keyboard_enable
   ```

2. Check the configured root shell:

   ```bash
   /usr/bin/dscl . -read /Users/root UserShell
   ```

3. Require the scripted root, session-unlock, admin-host-info, and MDM rules to
   be `PASS`.
4. Confirm the root shell output ends in `/usr/bin/false`.
5. For GUI session limit, unique identification, and privileged-network MFA,
   record the manual procedure/policy artifact ID and its approval date.
6. From the approved account register—not raw password databases—confirm each
   local interactive account has an owner, role, and review date.

**Expected result:**

- Direct root login is unavailable.
- GUI-session and login-window restrictions match policy.
- Interactive identities are unique and attributable.
- MDM and privileged network access requirements have current evidence.

**Actual result:**

> Rule statuses and identity inventory observations:

**Status:** ☐ PASS ☐ FAIL ☐ BLOCKED ☐ NOT APPLICABLE

**Evidence / defect reference:**

>

### HXG-OS-008 — Verify cryptographic controls

**Execution steps:**

1. Retrieve the exact cryptographic rules:

   ```bash
   hxg_show_rules \
     os_implement_cryptography \
     os_required_crypto_module \
     os_certificate_authority_trust \
     os_ssh_fips_compliant \
     os_sshd_fips_compliant
   ```

2. If SSH is disabled, record the HXG-OS-004 evidence and mark the SSH cipher
   rules NOT APPLICABLE only when the approved baseline allows it.
3. If SSH is enabled, require both FIPS connection rules to be `PASS`.
4. For the two manual cryptography rules, record the approved cryptographic
   module/product evidence ID, version, approver, and review date.
5. For an exception, record service, algorithm, owner, approval, compensating
   control, and expiry. Any missing field is FAIL.

**Expected result:**

- Approved platform cryptography and required modules are used.
- SSH uses only approved FIPS-compliant connections when enabled.
- No unapproved algorithm or unresolved exception is present.

**Actual result:**

> Cryptographic evidence and exceptions:

**Status:** ☐ PASS ☐ FAIL ☐ BLOCKED ☐ NOT APPLICABLE

**Evidence / defect reference:**

>

### HXG-OS-009 — Verify filesystem and home-folder permissions

**Execution steps:**

1. Retrieve the exact filesystem rules:

   ```bash
   hxg_show_rules \
     os_world_writable_library_folder_configure \
     os_world_writable_system_folder_configure \
     os_system_wide_applications_configure \
     os_home_folders_secure \
     os_guest_folder_removed
   ```

2. Require all five rules to be `PASS`.
3. For a failure, record `rule`, `result_value`, `expected_value`, and only the
   affected path names shown by approved diagnostics. Do not open or copy file
   contents.
4. If a scan timed out, mark FAIL/ERROR and create a diagnostic defect; do not
   narrow the scan scope and call the control PASS.

**Expected result:**

- No unauthorized world-writable file exists in protected system trees.
- Application and home-folder permissions match policy.
- The guest folder is absent where required.

**Actual result:**

> Rule statuses and affected paths, if any:

**Status:** ☐ PASS ☐ FAIL ☐ BLOCKED ☐ NOT APPLICABLE

**Evidence / defect reference:**

>

### HXG-OS-010 — Verify Safari hardening

**Execution steps:**

1. Retrieve all Safari hardening rules:

   ```bash
   hxg_show_rules \
     os_safari_prevent_cross-site_tracking_enable \
     os_safari_warn_fraudulent_website_enable \
     os_safari_show_status_bar_enabled \
     os_safari_show_full_website_address_enable \
     os_safari_advertising_privacy_protection_enable \
     os_safari_open_safe_downloads_disable
   ```

2. Require all six rule states to be `PASS`.
3. Open Safari → Settings → Privacy and General, then View. Verify the managed
   settings correspond to the six controls and cannot be relaxed by the
   operator.
4. Record the observed UI label/value for each rule; do not browse to an
   external site during production air-gap testing.

**Expected result:**

- Tracking prevention and fraudulent-site warning are enabled.
- Status bar and full URL display meet policy.
- Advertising privacy protection is enabled.
- Automatic opening of “safe” downloads is disabled.

**Actual result:**

> Rule statuses and Safari observations:

**Status:** ☐ PASS ☐ FAIL ☐ BLOCKED ☐ NOT APPLICABLE

**Evidence / defect reference:**

>

### HXG-OS-011 — Verify sudo policy

**Execution steps:**

1. Retrieve the three sudo rules:

   ```bash
   hxg_show_rules \
     os_sudo_log_enforce \
     os_sudo_timeout_configure \
     os_sudoers_timestamp_type_configure
   ```

2. Require all three rules to be `PASS`.
3. Record the timeout `result_value` and `expected_value` from the JSON.
4. Confirm the timestamp-type rule reports the effective per-terminal
   (`tty_tickets`) behavior required by the baseline.
5. Do not run `sudo`, edit `sudoers`, or refresh a credential timestamp for
   this test.

**Expected result:**

- Sudo events are logged.
- Timeout matches the approved policy.
- Credential caching is scoped per terminal.

**Actual result:**

> Rule statuses and effective values:

**Status:** ☐ PASS ☐ FAIL ☐ BLOCKED ☐ NOT APPLICABLE

**Evidence / defect reference:**

>

### HXG-OS-012 — Verify power and sleep policy

**Execution steps:**

1. Retrieve the exact power rules:

   ```bash
   hxg_show_rules \
     os_power_nap_disable \
     os_sleep_and_display_sleep_apple_silicon_enable
   ```

2. Display the effective settings:

   ```bash
   /usr/bin/pmset -g custom
   ```

3. Require `os_power_nap_disable=PASS`.
4. On Apple Silicon portable hardware, require the sleep/display rule to be
   `PASS` and record the battery `sleep` and `displaysleep` values from
   `pmset`.
5. For `NOT_APPLICABLE`, record the architecture and desktop/portable hardware
   basis from the rule message.

**Expected result:**

- Power Nap is disabled.
- Sleep and display-sleep values match the approved baseline.
- Hardware-specific non-applicability is explained.

**Actual result:**

> Power settings and rule statuses:

**Status:** ☐ PASS ☐ FAIL ☐ BLOCKED ☐ NOT APPLICABLE

**Evidence / defect reference:**

>

## 10. System settings, interfaces, and peripherals

Retrieve System Settings results:

```bash
HXG_BASE_URL='http://127.0.0.1:8000'
HXG_SESSION_ID='<SESSION_ID>'
HXG_CATEGORY='System Settings'
/usr/bin/curl -fsSG \
  --data-urlencode 'limit=500' \
  --data-urlencode "category=$HXG_CATEGORY" \
  "$HXG_BASE_URL/api/scans/$HXG_SESSION_ID/results"
```

### HXG-SYS-001 — Verify interfaces and sharing services

**Execution steps:**

1. Retrieve the exact interface and sharing rules:

   ```bash
   hxg_show_rules \
     system_settings_wifi_disable \
     system_settings_wifi_disable_when_connected_to_ethernet \
     system_settings_ethernet_disable \
     system_settings_internet_sharing_disable \
     system_settings_content_caching_disable \
     system_settings_media_sharing_disabled \
     system_settings_printer_sharing_disable \
     system_settings_smbd_disable \
     system_settings_guest_access_smb_disable \
     system_settings_screen_sharing_disable \
     system_settings_rae_disable \
     system_settings_remote_management_disable \
     system_settings_airplay_receiver_disable \
     system_settings_wake_network_access_disable \
     system_settings_wifi_menu_enable
   ```

2. Record the approved production interface posture before interpreting Wi-Fi
   and Ethernet rules. A baseline conflict must be resolved by an approved
   exception, not by enabling connectivity for the test.
3. List configured interfaces and active listeners:

   ```bash
   /usr/sbin/networksetup -listallhardwareports
   /usr/sbin/networksetup -listallnetworkservices
   /usr/sbin/netstat -anv -p tcp
   ```

   Redact hardware addresses and network addresses before attaching output.

4. Review configured sharing services:

   ```bash
   /usr/sbin/sharing -l
   ```

5. Require all applicable sharing-service rules to be `PASS`.
6. For `system_settings_wifi_disable_when_connected_to_ethernet`
   (`has_scan:false`), record the profile/procedure ID that enforces the
   conditional behavior.
7. In System Settings → General → Sharing, verify every prohibited sharing
   switch is Off. In System Settings → Network, record Wi-Fi/Ethernet state
   without turning an interface on.

**Expected result:**

- Interfaces and sharing services are disabled as required by the production
  posture.
- Any required physical interface has a documented exception and compensating
  control.
- No prohibited sharing service is active.

**Actual result:**

> Interface states, service states, and exceptions:

**Status:** ☐ PASS ☐ FAIL ☐ BLOCKED ☐ NOT APPLICABLE

**Evidence / defect reference:**

>

### HXG-SYS-002 — Verify application firewall and stealth mode

**Execution steps:**

1. Retrieve all firewall controls:

   ```bash
   hxg_show_rules \
     system_settings_firewall_enable \
     system_settings_firewall_stealth_mode_enable \
     os_firewall_default_deny_require \
     supplemental_firewall_pf
   ```

2. Run:

   ```bash
   /usr/libexec/ApplicationFirewall/socketfilterfw --getglobalstate
   /usr/libexec/ApplicationFirewall/socketfilterfw --getstealthmode
   ```

3. Require both System Settings firewall rules to be `PASS`.
4. Confirm the native commands report global firewall enabled and stealth mode
   enabled.
5. Open System Settings → Network → Firewall → Options. Record each allowed
   application by approved inventory ID; do not capture user-specific paths.
6. For default-deny and packet-filter supplemental controls, record the
   approved rule-set artifact, owner, version, and last review date.

**Expected result:**

- Application Firewall and stealth mode are enabled.
- Allowed applications are limited to the approved inventory.
- No test changes the firewall configuration.

**Actual result:**

> Firewall state and approved exceptions:

**Status:** ☐ PASS ☐ FAIL ☐ BLOCKED ☐ NOT APPLICABLE

**Evidence / defect reference:**

>

### HXG-SYS-003 — Verify Bluetooth restrictions

**Execution steps:**

1. Retrieve all Bluetooth rules:

   ```bash
   hxg_show_rules \
     system_settings_bluetooth_disable \
     system_settings_bluetooth_sharing_disable \
     system_settings_bluetooth_settings_disable \
     system_settings_bluetooth_menu_enable
   ```

2. Require the disable/sharing/settings rules to be `PASS`; evaluate the menu
   rule according to the selected baseline and approved exception.
3. Open System Settings → Bluetooth. With no approved device connected, verify
   Bluetooth is Off and the operator cannot enable it if the pane is managed.
4. If an approved device is required, compare its displayed name with the
   approved asset register. Do not record its hardware address and do not pair
   a new device.

**Expected result:**

- Bluetooth is disabled when no approved device requires it.
- Bluetooth Sharing is disabled.
- Settings access and exceptions match policy.

**Actual result:**

> Bluetooth state, approved device, and exception reference:

**Status:** ☐ PASS ☐ FAIL ☐ BLOCKED ☐ NOT APPLICABLE

**Evidence / defect reference:**

>

### HXG-SYS-004 — Verify session-lock controls

**Test type:** Controlled. Coordinate with the current operator before allowing
the session to lock or auto-logout.

**Execution steps:**

1. Retrieve every session-lock rule:

   ```bash
   hxg_show_rules \
     system_settings_screensaver_password_enforce \
     system_settings_screensaver_timeout_enforce \
     system_settings_screensaver_ask_for_password_delay_enforce \
     system_settings_automatic_logout_enforce \
     system_settings_apple_watch_unlock_disable \
     system_settings_touchid_unlock_disable \
     system_settings_touch_id_settings_disable \
     system_settings_hot_corners_disable \
     system_settings_hot_corners_secure \
     os_skip_unlock_with_watch_enable \
     os_touchid_prompt_disable
   ```

2. Display the current user's lock settings:

   ```bash
   /usr/bin/defaults read com.apple.screensaver askForPassword 2>/dev/null
   /usr/bin/defaults read com.apple.screensaver askForPasswordDelay 2>/dev/null
   /usr/bin/defaults -currentHost read com.apple.screensaver idleTime 2>/dev/null
   ```

3. Require every applicable non-exempt rule to be `PASS`.
4. Record `askForPassword=1`, `askForPasswordDelay=0`, and the actual
   `idleTime`. If a key is absent, rely on the corresponding rule JSON and
   record the missing direct value.
5. Choose Apple menu → Lock Screen, wait for the lock screen, and verify the
   approved authentication method is required. Do not test repeated failures.
6. If timeout behavior is approved, record start time, observed lock time, and
   elapsed seconds; compare with the rule's expected timeout.
7. For Touch ID exceptions, record each exact rule ID, reason, approver, and
   exemption expiry.

**Expected result:**

- Screen lock requires immediate authentication.
- Automatic lock/logout occurs within the approved interval.
- Apple Watch unlock is disabled.
- Touch ID and smart-token behavior match approved policy or documented
  exceptions.
- Hot Corners cannot bypass locking requirements.

**Actual result:**

> Configured values and observed lock behavior:

**Status:** ☐ PASS ☐ FAIL ☐ BLOCKED ☐ NOT APPLICABLE

**Evidence / defect reference:**

>

### HXG-SYS-005 — Verify login-window controls

**Test type:** Controlled. A logout is not required unless approved.

**Execution steps:**

1. Retrieve the exact login-window rules:

   ```bash
   hxg_show_rules \
     system_settings_loginwindow_loginwindowtext_enable \
     system_settings_loginwindow_prompt_username_password_enforce \
     system_settings_automatic_login_disable \
     system_settings_guest_account_disable \
     os_policy_banner_loginwindow_enforce \
     os_screensaver_loginwindow_enforce
   ```

2. Display the effective login-window values:

   ```bash
   /usr/bin/defaults read \
     /Library/Preferences/com.apple.loginwindow SHOWFULLNAME 2>/dev/null
   /usr/bin/defaults read \
     /Library/Preferences/com.apple.loginwindow GuestEnabled 2>/dev/null
   /usr/bin/defaults read \
     /Library/Preferences/com.apple.loginwindow autoLoginUser 2>/dev/null
   ```

3. Require all five rules to be `PASS`.
4. Confirm `SHOWFULLNAME=1`, `GuestEnabled=0`, and no `autoLoginUser` value.
5. During an approved logout/reboot window, photograph or record the policy
   banner text/version and confirm username/password fields are shown instead
   of a user list.
6. Do not attempt guest or unauthorized authentication. Mark behavioral
   verification BLOCKED if no logout window is approved.

**Expected result:**

- The approved policy banner is displayed.
- Login prompts for username and password rather than showing a user list.
- Automatic login and guest account are disabled.

**Actual result:**

> Scan evidence and login-window observations:

**Status:** ☐ PASS ☐ FAIL ☐ BLOCKED ☐ NOT APPLICABLE

**Evidence / defect reference:**

>

### HXG-SYS-006 — Verify software-update and time controls

**Execution steps:**

1. Retrieve the exact update and time rules:

   ```bash
   hxg_show_rules \
     system_settings_critical_update_install_enforce \
     system_settings_security_update_install \
     system_settings_download_software_update_enforce \
     system_settings_software_update_download_enforce \
     system_settings_install_macos_updates_enforce \
     system_settings_softwareupdate_current \
     os_software_update_app_update_enforce \
     os_software_update_deferral \
     os_time_server_enabled \
     system_settings_time_server_configure \
     system_settings_time_server_enforce
   ```

2. Require each applicable scripted rule to be `PASS` or have the documented
   software-update exception used by this deployment.
3. Record the current macOS version/build from HXG-BASE-001 and compare it with
   the approved offline release baseline—not with an online update service.
4. Record the time-server `result_value` and `expected_value` from the rule
   JSON. They must match the authorized internal/local time source policy.
5. Open the offline update procedure and record its document version and media
   release ID. Do not connect the production device to the internet or invoke
   an update download.

**Expected result:**

- Update policy and deferral match the approved baseline.
- The current OS status is documented against the approved release.
- Time synchronization policy is configured.
- Production update instructions do not require network access.

**Actual result:**

> Update policy, OS status, and time configuration:

**Status:** ☐ PASS ☐ FAIL ☐ BLOCKED ☐ NOT APPLICABLE

**Evidence / defect reference:**

>

### HXG-SYS-007 — Verify privacy, telemetry, Siri, and location controls

**Execution steps:**

1. Retrieve the exact privacy and telemetry rules:

   ```bash
   hxg_show_rules \
     system_settings_diagnostics_reports_disable \
     system_settings_improve_search_disable \
     system_settings_improve_siri_dictation_disable \
     system_settings_improve_assistive_voice_disable \
     system_settings_personalized_advertising_disable \
     system_settings_siri_disable \
     system_settings_siri_listen_disable \
     system_settings_siri_settings_disable \
     os_dictation_disable \
     os_on_device_dictation_enforce \
     system_settings_find_my_disable \
     system_settings_location_services_disable \
     system_settings_location_services_enable \
     system_settings_location_services_menu_enforce \
     system_settings_internet_accounts_disable \
     system_settings_wallet_applepay_settings_disable \
     os_password_proximity_disable \
     os_password_sharing_disable \
     os_privacy_setup_prompt_disable
   ```

2. Require each applicable rule to be `PASS`; resolve the Dictation and
   Location Services enable/disable policy against the selected baseline and
   approved exceptions.
3. Open System Settings → Privacy & Security, Siri, Internet Accounts, and
   Wallet & Apple Pay. Record each disabled/managed UI state without enabling
   a service.
4. For approved on-device Dictation, record the exact exception and evidence
   that processing is restricted on-device.

**Expected result:**

- Telemetry and cloud-assisted features are disabled.
- Siri, Find My, Location Services, Internet Accounts, and Wallet panes or
  services are disabled as required.
- Dictation is disabled or constrained to an approved on-device exception.

**Actual result:**

> Profile evidence, UI state, and exceptions:

**Status:** ☐ PASS ☐ FAIL ☐ BLOCKED ☐ NOT APPLICABLE

**Evidence / defect reference:**

>

### HXG-SYS-008 — Verify Time Machine policy

**Execution steps:**

1. Determine whether Time Machine is required or formally exempted for this
   signing device.
2. Retrieve both rules:

   ```bash
   hxg_show_rules \
     system_settings_time_machine_auto_backup_enable \
     system_settings_time_machine_encrypted_configure
   ```

3. Check current Time Machine activity:

   ```bash
   /usr/bin/tmutil status
   ```

4. If required, require both rules to be `PASS`; record whether `tmutil status`
   is Running or Not Running at the instant of observation without starting a
   backup.
5. In System Settings → General → Time Machine, record the approved destination
   label and encryption indicator; redact volume identifiers.
6. If exempted, record rule ID, reason, alternative backup control, owner,
   approver, and review/expiry date.
7. Do not attach unapproved backup media.

**Expected result:**

- Automatic encrypted backup is configured, or a current approved exception
  and compensating control exist.
- No unencrypted or unapproved destination is accepted.

**Actual result:**

> Backup state or exemption evidence:

**Status:** ☐ PASS ☐ FAIL ☐ BLOCKED ☐ NOT APPLICABLE

**Evidence / defect reference:**

>

### HXG-SYS-009 — Verify USB Restricted Mode and whitelist enforcement

**Test type:** Controlled peripheral test. Use only approved test media with no
sensitive data.

**Execution steps:**

1. Retrieve the exact rules:

   ```bash
   hxg_show_rules \
     system_settings_usb_restricted_mode \
     os_external_storage_access_defined \
     os_access_control_mobile_devices \
     os_auth_peripherals
   ```

2. Require `system_settings_usb_restricted_mode=PASS`. For the remaining
   manual controls, record the approved removable-media procedure ID and last
   review date.
3. Open Dashboard → Connections → USB Devices. Record whitelist entry labels
   and purposes only; do not copy serial numbers.
4. Connect the approved test device named in the maintenance plan. Record
   connection time and confirm it remains available.
5. Only if explicitly approved, connect the designated non-whitelisted test
   device. Record detection time, block/isolation outcome, and watcher message.
6. Open Dashboard → Audit Log → All Actions and verify
   `USB_UNAUTHORIZED_DEVICE` for the designated negative test.
7. Disconnect all test media and confirm no unexpected device remains listed.

**Expected result:**

- USB Restricted Mode is enforced.
- Approved media follows the whitelist policy.
- A designated unapproved test device is detected and blocked or isolated.
- The event is audit logged.
- No test media contains production secrets.

**Actual result:**

> Device labels, watcher response, and audit reference:

**Status:** ☐ PASS ☐ FAIL ☐ BLOCKED ☐ NOT APPLICABLE

**Evidence / defect reference:**

>

## 11. Supplemental controls and dashboard safeguards

Retrieve supplemental/manual rule states:

```bash
HXG_BASE_URL='http://127.0.0.1:8000'
HXG_SESSION_ID='<SESSION_ID>'
HXG_CATEGORY='Other'
/usr/bin/curl -fsSG \
  --data-urlencode 'limit=500' \
  --data-urlencode "category=$HXG_CATEGORY" \
  "$HXG_BASE_URL/api/scans/$HXG_SESSION_ID/results"
```

### HXG-SUP-001 — Verify supplemental and manual-control evidence

**Execution steps:**

1. Retrieve all six manual entries:

   ```bash
   hxg_show_rules \
     supplemental_filevault \
     supplemental_firewall_pf \
     supplemental_password_policy \
     supplemental_cis_manual \
     supplemental_controls \
     os_continuous_monitoring \
     os_protect_dos_attacks
   ```

2. Confirm each supplemental/manual response states `has_scan:false`; API
   status alone is not PASS.
3. For each rule, record the exact evidence document ID, owner, approver, issue
   date, review/expiry date, and storage reference.
4. For `supplemental_controls`, list every out-of-scope control ID with
   rationale, compensating control, residual risk, and approval.
5. Mark FAIL for a missing/expired artifact or an out-of-scope item without
   approval.

**Expected result:**

- All six supplemental entries have current evidence.
- No manual control is assumed compliant solely because no scan script exists.
- Out-of-scope decisions are approved and reviewable.

**Actual result:**

> Evidence set and unresolved manual controls:

**Status:** ☐ PASS ☐ FAIL ☐ BLOCKED ☐ NOT APPLICABLE

**Evidence / defect reference:**

>

### HXG-SEC-001 — Verify sensitive actions require admin 2FA

**Test type:** Controlled. Do not complete a state-changing action.

**Execution steps:**

1. Sign in to a normal operator session without an active HX-Guardian 2FA
   token.
2. Record the current rule and exemption state:

   ```bash
   HXG_BASE_URL='http://127.0.0.1:8000'
   HXG_TEST_RULE_ID='<APPROVED_NONCOMPLIANT_TEST_RULE_ID>'
   /usr/bin/curl -fsS "$HXG_BASE_URL/api/rules/$HXG_TEST_RULE_ID"
   /usr/bin/curl -fsS "$HXG_BASE_URL/api/exemptions"
   ```

3. Record `current_status`, exemption state, and scan timestamp so an
   unintended change can be detected.
4. Open Dashboard → Rules → select the same test rule →
   **Apply Fix**, but do not confirm. Confirm the 6-digit TOTP prompt appears.
5. Cancel, then open Dashboard → Exemptions → **Grant Exemption**. Enter the
   designated test rule and reason, continue only to the TOTP prompt, and
   confirm the same gate appears.
6. Enter the maintenance-plan invalid TOTP once in one flow. Confirm the UI
   reports rejection and the action does not complete; do not make repeated
   invalid attempts.
7. Re-run both GET commands from step 2 and confirm the rule/exemption state
   is unchanged.
8. Cancel all dialogs. A valid-code path requires the admin and a separately
   approved reversible test action.

**Expected result:**

- Sensitive actions cannot complete without valid admin TOTP.
- One invalid code is rejected without applying a change.
- Read-only dashboard access remains available locally.

**Actual result:**

> Action tested, prompt observed, and rejection result:

**Status:** ☐ PASS ☐ FAIL ☐ BLOCKED ☐ NOT APPLICABLE

**Evidence / defect reference:**

>

### HXG-SEC-002 — Verify security actions are audit logged

**Test type:** Controlled. Use an approved benign action.

**Execution steps:**

1. Query and record the latest scan audit entries:

   ```bash
   HXG_BASE_URL='http://127.0.0.1:8000'
   /usr/bin/curl -fsSG \
     --data-urlencode 'limit=20' \
     --data-urlencode 'action=SCAN_RUN' \
     "$HXG_BASE_URL/api/audit-log"
   /usr/bin/curl -fsSG \
     --data-urlencode 'limit=20' \
     --data-urlencode 'action=SCAN_COMPLETE' \
     "$HXG_BASE_URL/api/audit-log"
   ```

2. Record the newest entry IDs and timestamps.
3. In Dashboard → Rules, open one scripted rule and select **Scan Now**.
4. Repeat the two commands and identify the new `SCAN_RUN` and
   `SCAN_COMPLETE` entries by timestamp/target.
5. Require the new entries to identify the scan target/session and to occur
   after step 2.
6. If HXG-SEC-001 included an approved admin action, query its documented
   action type and record the new entry without capturing TOTP or secret data.

**Expected result:**

- The read-only scan produces attributable start/completion audit records.
- Approved security changes produce the documented action type.
- Records include usable timestamps and target identifiers.
- Existing audit records cannot be edited from the dashboard.

**Actual result:**

> Audit action types, timestamps, and references:

**Status:** ☐ PASS ☐ FAIL ☐ BLOCKED ☐ NOT APPLICABLE

**Evidence / defect reference:**

>

### HXG-REP-001 — Verify report and evidence export

**Execution steps:**

1. Set an existing approved evidence directory and verify it is a directory:

   ```bash
   HXG_REPORT_DIR='<APPROVED_EXISTING_DIRECTORY>'
   test -d "$HXG_REPORT_DIR"
   ```

   Stop and mark BLOCKED if this check fails. Do not substitute `/`, a home
   directory, or an unapproved removable volume.
2. Export both formats for the recorded scan:

   ```bash
   HXG_BASE_URL='http://127.0.0.1:8000'
   HXG_SESSION_ID='<SESSION_ID>'
   /usr/bin/curl -fsS \
     -o "$HXG_REPORT_DIR/hxg-session-$HXG_SESSION_ID.html" \
     "$HXG_BASE_URL/api/reports/html?session_id=$HXG_SESSION_ID"
   /usr/bin/curl -fsS \
     -o "$HXG_REPORT_DIR/hxg-session-$HXG_SESSION_ID.csv" \
     "$HXG_BASE_URL/api/reports/csv?session_id=$HXG_SESSION_ID"
   /bin/ls -lh \
     "$HXG_REPORT_DIR/hxg-session-$HXG_SESSION_ID.html" \
     "$HXG_REPORT_DIR/hxg-session-$HXG_SESSION_ID.csv"
   ```

3. Open the HTML locally and inspect the CSV using an approved offline viewer.
4. Require session ID and counts to match HXG-SCAN-001. Confirm FAIL, EXEMPT,
   NOT_APPLICABLE, and MDM-required states remain visible.
5. Search visually for unexpected secrets, keys, TOTP values, tokens, or
   unrelated runtime data. Do not use a command that prints possible secrets
   into the terminal transcript.

**Expected result:**

- Report generation completes offline.
- Counts reconcile with the recorded scan session.
- Exemptions and unresolved states remain visible.
- Evidence is stored only in an approved location.

**Actual result:**

> Report type, totals, storage reference, and content review:

**Status:** ☐ PASS ☐ FAIL ☐ BLOCKED ☐ NOT APPLICABLE

**Evidence / defect reference:**

>

## 12. Persistence and closure

### HXG-PERS-001 — Verify hardening persists after reboot

**Test type:** Controlled reboot. Execute only during an approved maintenance
window with a recovery method available.

**Execution steps:**

1. Record the pre-reboot scan ID and run:

   ```bash
   HXG_BASE_URL='http://127.0.0.1:8000'
   /usr/bin/curl -fsS "$HXG_BASE_URL/api/health"
   /usr/bin/curl -fsS "$HXG_BASE_URL/api/runner/status"
   ```

2. Confirm the maintenance approval and recovery contact are recorded.
3. Use Apple menu → Restart. Do not use a terminal reboot command from this
   checklist.
4. At startup, record whether FileVault unlock and the policy login banner
   appear as expected; never record the password or recovery key.
5. After login, repeat the two health commands and the listener/process/socket
   commands from HXG-BASE-002 and HXG-BASE-003.
6. Run HXG-SCAN-001 again and record the post-reboot session ID.
7. Compare pre/post totals and list every rule whose status changed. Any
   unexplained regression is FAIL.

**Expected result:**

- FileVault/login controls operate as approved.
- HX-Guardian services return automatically.
- The dashboard remains loopback-only and the runner reconnects.
- No previously compliant hardening control regresses after reboot.

**Actual result:**

> Reboot window, post-reboot health, scan ID, and differences:

**Status:** ☐ PASS ☐ FAIL ☐ BLOCKED ☐ NOT APPLICABLE

**Evidence / defect reference:**

>

### HXG-CLOSE-001 — Reconcile exceptions, failures, and residual risk

**Execution steps:**

1. Confirm every test case has one final status.
2. Query every unresolved rule state:

   ```bash
   HXG_BASE_URL='http://127.0.0.1:8000'
   for HXG_STATUS in FAIL ERROR MDM_REQUIRED EXEMPT NOT_APPLICABLE; do
     printf '\n===== %s =====\n' "$HXG_STATUS"
     /usr/bin/curl -fsSG \
       --data-urlencode "status=$HXG_STATUS" \
       "$HXG_BASE_URL/api/rules"
   done
   ```

3. Reconcile the command output with the 41-case summary and scan session.
4. For each FAIL, ERROR, BLOCKED, unverified MDM control, exemption, or
   NOT_APPLICABLE result, record rule/test ID, owner, severity, defect/risk
   reference, due date, compensating control, and release disposition.
5. Confirm PASS + FAIL + BLOCKED + NOT APPLICABLE equals 41.
6. Obtain security reviewer, device administrator, and release-owner approval.
   Missing required approval means the release decision cannot be Approved.

**Expected result:**

- No blank test status remains.
- Every unresolved result has an accountable owner and disposition.
- Release approval explicitly accounts for residual risk.
- Evidence is complete without containing secrets or credentials.

**Actual result:**

> Final totals, unresolved items, and approval references:

**Status:** ☐ PASS ☐ FAIL ☐ BLOCKED ☐ NOT APPLICABLE

**Evidence / defect reference:**

>

## 13. Final sign-off

| Role | Name | Decision | Date | Signature / approval reference |
|---|---|---|---|---|
| Tester |  | ☐ Approve ☐ Reject |  |  |
| Security reviewer |  | ☐ Approve ☐ Reject |  |  |
| Device administrator |  | ☐ Approve ☐ Reject |  |  |
| Release owner |  | ☐ Approve ☐ Reject |  |  |

### Final counts

| Result | Count |
|---|---:|
| PASS |  |
| FAIL |  |
| BLOCKED |  |
| NOT APPLICABLE |  |
| Total test cases | 41 |

### Residual risk statement

>

### Release decision

- [ ] Approved for production.
- [ ] Approved with documented residual risk.
- [ ] Rejected pending remediation and re-test.
