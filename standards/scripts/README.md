# Security Scripts - Integration Guide

This document explains how the individual scan and fix scripts are organized, how they were generated, and how to integrate them into a backend monitoring/automation system.

## Overview

We extracted **266 unique security rules** from three macOS security baselines and generated standalone shell scripts for each. Every rule has at most one scan script and one fix script, chosen from the highest-priority standard that defines it.

| Metric | Count |
|---|---|
| Total rules | 266 |
| Scan scripts (check compliance) | 214 |
| Fix scripts (apply remediation) | 86 |
| Manual / MDM-only (no script) | 52 |

## Source Priority

When a rule exists in multiple standards, the script is taken from the highest-priority source to ensure the strictest implementation:

| Priority | Standard | Rules sourced |
|---|---|---|
| 1 (highest) | NIST 800-53r5 High | 170 |
| 2 | CIS Controls v8 | 41 |
| 3 (lowest) | CIS Level 2 | 3 |

The `manifest.json` records which standard each script was sourced from (`scan_source` / `fix_source`).

## Directory Structure

```
build/scripts/
  manifest.json                          # Index of all 266 rules
  README.md                              # This file
  scan/
    audit_acls_files_configure.sh        # One scan script per rule
    audit_acls_folders_configure.sh
    ...                                  # 214 files
  fix/
    audit_acls_files_configure.sh        # One fix script per rule
    audit_acls_folders_configure.sh
    ...                                  # 86 files
```

## Rule Categories

Rules are grouped into 7 categories from the upstream baselines:

| Category | Scan | Fix | Manual/MDM |
|---|---|---|---|
| Auditing | 25 | 25 | 3 |
| Authentication | 7 | 4 | 0 |
| iCloud | 14 | 0 | 0 |
| Operating System | 91 | 40 | 37 |
| Password Policy | 11 | 2 | 4 |
| System Settings | 66 | 15 | 2 |
| Other (supplemental) | 0 | 0 | 6 |

## Script Interface

All scripts are designed for non-interactive, machine-driven execution. They output a single JSON line to stdout and use exit codes for flow control.

### Scan Scripts

**Purpose:** Check whether the system is compliant with a specific rule.

**Run:** `sudo zsh scripts/scan/<rule_name>.sh`

**Exit codes:**

| Code | Meaning |
|---|---|
| `0` | PASS - system is compliant |
| `1` | FAIL - system is not compliant |
| `2` | NOT_APPLICABLE - rule does not apply (e.g., wrong CPU architecture) |
| `3` | ERROR - script could not run (e.g., not root) |

**Output format (JSON):**

```json
{"rule":"audit_acls_files_configure","status":"PASS","result":"0","expected":"0"}
```

```json
{"rule":"os_dictation_disable","status":"NOT_APPLICABLE","message":"Requires i386 architecture"}
```

### Fix Scripts

**Purpose:** Remediate a non-compliant setting.

**Run:** `sudo zsh scripts/fix/<rule_name>.sh`

**Exit codes:**

| Code | Meaning |
|---|---|
| `0` | Fix applied successfully |
| `2` | NOT_APPLICABLE - rule does not apply to this system |
| `3` | ERROR - script could not run |

**Output format (JSON):**

```json
{"rule":"audit_acls_files_configure","action":"EXECUTED","message":"Fix applied"}
```

### Requirements

- Must run as **root** (`sudo`)
- Shell: **zsh** (macOS default)
- No interactive prompts - safe for cron, launchd, or backend orchestration

## Manifest (manifest.json)

The manifest is the main integration point. It contains every rule with metadata your backend can use to drive automation.

**Schema per entry:**

```json
{
  "rule": "audit_acls_files_configure",
  "description": "Configure Audit Log Files to Not Contain Access Control Lists",
  "category": "Auditing",
  "standards": {
    "800-53r5_high": true,
    "cisv8": true,
    "cis_lvl2": true
  },
  "scan_script": "scripts/scan/audit_acls_files_configure.sh",
  "fix_script": "scripts/fix/audit_acls_files_configure.sh",
  "scan_source": "800-53r5_high",
  "fix_source": "800-53r5_high"
}
```

**Fields:**

| Field | Type | Description |
|---|---|---|
| `rule` | string | Unique rule identifier |
| `description` | string | Human-readable rule name |
| `category` | string | Grouping (Auditing, Authentication, iCloud, etc.) |
| `standards` | object | Which baselines include this rule |
| `scan_script` | string or null | Relative path to scan script, null if no check exists |
| `fix_script` | string or null | Relative path to fix script, null if no shell fix exists |
| `scan_source` | string or null | Which standard the scan was taken from |
| `fix_source` | string or null | Which standard the fix was taken from |

## Backend Integration Patterns

### 1. Run All Scans (Compliance Audit)

```python
import json, subprocess

manifest = json.load(open("scripts/manifest.json"))

results = []
for rule_name, rule in manifest.items():
    if not rule["scan_script"]:
        continue
    proc = subprocess.run(
        ["sudo", "zsh", rule["scan_script"]],
        capture_output=True, text=True, timeout=30
    )
    result = json.loads(proc.stdout.strip())
    result["exit_code"] = proc.returncode
    results.append(result)

# results is now a list of JSON objects with status PASS/FAIL/NOT_APPLICABLE
```

### 2. Scan Then Fix (Auto-Remediate)

```python
for rule_name, rule in manifest.items():
    if not rule["scan_script"]:
        continue

    scan = subprocess.run(
        ["sudo", "zsh", rule["scan_script"]],
        capture_output=True, text=True, timeout=30
    )

    if scan.returncode == 1 and rule["fix_script"]:
        fix = subprocess.run(
            ["sudo", "zsh", rule["fix_script"]],
            capture_output=True, text=True, timeout=60
        )
```

### 3. Filter by Standard or Category

```python
# Only NIST 800-53 rules
nist_rules = {k: v for k, v in manifest.items() if v["standards"].get("800-53r5_high")}

# Only Auditing category
audit_rules = {k: v for k, v in manifest.items() if v["category"] == "Auditing"}
```

### 4. Run a Single Rule (API endpoint)

```bash
# Scan one rule
sudo zsh scripts/scan/system_settings_firewall_enable.sh
# {"rule":"system_settings_firewall_enable","status":"PASS","result":"true","expected":"true"}

# Fix one rule
sudo zsh scripts/fix/os_guest_folder_removed.sh
# {"rule":"os_guest_folder_removed","action":"EXECUTED","message":"Fix applied"}
```

## Why Some Rules Have No Scripts

| Reason | Count | Examples |
|---|---|---|
| **MDM profile required** | ~128 scan-only | iCloud, System Settings, most OS rules - these are enforced via configuration profiles, not shell commands |
| **Inherent OS compliance** | ~37 manual | `os_application_sandboxing`, `os_implement_memory_protection` - macOS is inherently compliant |
| **Supplemental guidance** | 6 | `supplemental_filevault`, `supplemental_smartcard` - documentation only |
| **No shell check exists** | ~15 | `os_wifi_disable`, `os_rapid_security_response_allow` - only enforceable via MDM |

Rules with `scan_script: null` and `fix_script: null` in the manifest should be tracked as manual verification items or handled through your MDM solution.

## Regenerating Scripts

If baselines are updated, re-run the generator:

```bash
python3 build/generate_scripts.py
```

This re-parses the three `*_compliance.sh` files and `security_standards_comparison.md`, then overwrites the `scripts/` directory.
