#!/usr/bin/env python3
"""
Generate individual scan and fix shell scripts for each security rule.

Parses compliance.sh files from each standard and the security_standards_comparison.md
to generate standalone, automation-friendly scripts.

Priority order: NIST 800-53r5 High > CIS v8 > CIS Level 2

Usage:
    python3 generate_scripts.py

Output:
    build/scripts/scan/<rule_name>.sh   - check compliance (exit 0=PASS, 1=FAIL, 2=N/A, 3=ERROR)
    build/scripts/fix/<rule_name>.sh    - apply remediation (exit 0=OK, 2=N/A, 3=ERROR)
    build/scripts/manifest.json         - index of all rules and scripts
"""

import json
import os
import re
import stat
import sys

BUILD_DIR = os.path.dirname(os.path.abspath(__file__))

STANDARDS_PRIORITY = ["800-53r5_high", "cisv8", "cis_lvl2"]

COMPLIANCE_FILES = {
    "800-53r5_high": os.path.join(BUILD_DIR, "800-53r5_high", "800-53r5_high_compliance.sh"),
    "cisv8": os.path.join(BUILD_DIR, "cisv8", "cisv8_compliance.sh"),
    "cis_lvl2": os.path.join(BUILD_DIR, "cis_lvl2", "cis_lvl2_compliance.sh"),
}

COMPARISON_MD = os.path.join(BUILD_DIR, "security_standards_comparison.md")


# ---------------------------------------------------------------------------
# Parsing
# ---------------------------------------------------------------------------

def parse_comparison_md():
    """Parse comparison MD to get all rules and their standard memberships."""
    rules = {}
    current_category = ""

    with open(COMPARISON_MD) as f:
        for line in f:
            cat_match = re.match(r"^## (.+)", line)
            if cat_match:
                current_category = cat_match.group(1).strip()
                continue

            # Rule lines start with | **rule_name**
            if not line.startswith("| **"):
                continue

            # Extract rule name
            name_match = re.search(r"\*\*([\w-]+)\*\*", line)
            if not name_match:
                continue
            rule_name = name_match.group(1)

            # Extract short description (between <br> and first |)
            desc_match = re.search(r"<br>([^|]+)\|", line)
            description = desc_match.group(1).strip() if desc_match else ""

            # Extract status columns - last 3 checkmark/dash indicators
            statuses = re.findall(r"(✅|—)", line)
            if len(statuses) < 3:
                continue

            rules[rule_name] = {
                "description": description,
                "category": current_category,
                "standards": {
                    "cis_lvl2": statuses[-3] == "✅",
                    "cisv8": statuses[-2] == "✅",
                    "800-53r5_high": statuses[-1] == "✅",
                },
            }

    return rules


def split_scan_fix_sections(content):
    """Split compliance.sh content into scan and fix sections."""
    scan_start = content.find("run_scan(){")
    fix_start = content.find("run_fix(){")

    if scan_start < 0:
        return "", ""

    scan_section = content[scan_start:fix_start] if fix_start > scan_start else content[scan_start:]
    fix_section = content[fix_start:] if fix_start > 0 else ""

    return scan_section, fix_section


def extract_rule_blocks(section):
    """Split a section into per-rule blocks keyed by rule name."""
    blocks = {}
    parts = re.split(r"(#####----- Rule: [\w-]+ -----#####)", section)

    for i in range(1, len(parts), 2):
        name_match = re.search(r"Rule: ([\w-]+)", parts[i])
        if name_match and i + 1 < len(parts):
            blocks[name_match.group(1)] = parts[i + 1]

    return blocks


def extract_scan_info(block):
    """Extract arch, check command, and expected value from a scan block."""
    info = {"arch": "", "check_command": None, "expected_value": None, "expected_type": None}

    # Architecture
    arch_match = re.search(r'rule_arch="([^"]*)"', block)
    if arch_match:
        info["arch"] = arch_match.group(1)

    # Check command: collect lines from result_value=$( until # expected result
    lines = block.split("\n")
    in_cmd = False
    cmd_lines = []

    for line in lines:
        if "result_value=$(" in line:
            in_cmd = True
            idx = line.index("result_value=$(") + len("result_value=$(")
            cmd_lines.append(line[idx:])
        elif in_cmd:
            if "# expected result" in line:
                in_cmd = False
            else:
                cmd_lines.append(line)

    if cmd_lines:
        cmd = "\n".join(cmd_lines).rstrip()
        # Strip trailing ) that closes the $()
        if cmd.rstrip().endswith(")"):
            cmd = cmd.rstrip()[:-1].rstrip()
        info["check_command"] = cmd

    # Expected result - handle integer, string, and boolean types
    exp_int = re.search(r"# expected result \{'integer': (-?\d+)\}", block)
    exp_str = re.search(r"# expected result \{'string': '([^']*)'\}", block)
    exp_bool = re.search(r"# expected result \{'boolean': (\d+)\}", block)

    if exp_int:
        info["expected_value"] = exp_int.group(1)
        info["expected_type"] = "integer"
    elif exp_str:
        info["expected_value"] = exp_str.group(1)
        info["expected_type"] = "string"
    elif exp_bool:
        info["expected_value"] = exp_bool.group(1)
        info["expected_type"] = "boolean"
    else:
        exp_b64 = re.search(r"# expected result \{'base64': '([^']*)'\}", block)
        if exp_b64:
            info["expected_value"] = exp_b64.group(1)
            info["expected_type"] = "base64"

    return info


def extract_fix_commands(block):
    """Extract the actual fix commands from a fix block."""
    lines = block.split("\n")
    in_fix = False
    fix_lines = []

    for line in lines:
        if 'logmessage "Running the command to configure' in line:
            in_fix = True
            continue
        if in_fix:
            # The closing fi is at 8-space indent
            if re.match(r"^        fi\s*$", line):
                break
            fix_lines.append(line)

    if fix_lines:
        return "\n".join(fix_lines).strip()
    return None


def parse_all_standards():
    """Parse all compliance.sh files and return scan/fix blocks per standard."""
    all_data = {}

    for std_name, filepath in COMPLIANCE_FILES.items():
        if not os.path.exists(filepath):
            print(f"  Warning: {filepath} not found, skipping")
            continue

        with open(filepath) as f:
            content = f.read()

        scan_section, fix_section = split_scan_fix_sections(content)
        all_data[std_name] = {
            "scan": extract_rule_blocks(scan_section),
            "fix": extract_rule_blocks(fix_section),
        }

    return all_data


# ---------------------------------------------------------------------------
# Script generation
# ---------------------------------------------------------------------------

SCRIPT_HEADER = """#!/bin/zsh --no-rcs
# =============================================================================
# Rule:      {rule_name}
# Source:    {source}
# Category:  {category}
# Standards: {standards}
# Description: {description}
# =============================================================================
# Auto-generated - do not edit manually.
# Exit codes: 0=PASS/OK  1=FAIL/ERROR  2=NOT_APPLICABLE  3=ERROR(root)

if [[ $EUID -ne 0 ]]; then
    printf '{{"rule":"{rule_name}","status":"ERROR","message":"Must be run as root"}}\\n'
    exit 3
fi

arch=$(/usr/bin/arch)
CURRENT_USER=$(/usr/bin/defaults read /Library/Preferences/com.apple.loginwindow lastUserName)
CURR_USER_UID=$(/usr/bin/id -u $CURRENT_USER)
"""


def generate_scan_script(rule_name, rule_info, scan_info, source):
    standards_str = ", ".join(s for s, v in rule_info["standards"].items() if v)
    desc = rule_info["description"][:120]

    header = SCRIPT_HEADER.format(
        rule_name=rule_name,
        source=source,
        category=rule_info["category"],
        standards=standards_str,
        description=desc,
    )

    arch_check = ""
    if scan_info["arch"]:
        arch_check = f"""
rule_arch="{scan_info['arch']}"
if [[ "$arch" != "$rule_arch" ]]; then
    printf '{{"rule":"{rule_name}","status":"NOT_APPLICABLE","message":"Requires {scan_info['arch']} architecture"}}\\n'
    exit 2
fi
"""

    cmd = scan_info["check_command"]
    expected = scan_info["expected_value"]

    body = f"""{arch_check}
result_value=$({cmd}
)
expected_value="{expected}"

if [[ "$result_value" == "$expected_value" ]]; then
    printf '{{"rule":"{rule_name}","status":"PASS","result":"%s","expected":"%s"}}\\n' "$result_value" "$expected_value"
    exit 0
else
    printf '{{"rule":"{rule_name}","status":"FAIL","result":"%s","expected":"%s"}}\\n' "$result_value" "$expected_value"
    exit 1
fi
"""
    return header + body


def generate_fix_script(rule_name, rule_info, fix_cmd, scan_info, source):
    standards_str = ", ".join(s for s, v in rule_info["standards"].items() if v)
    desc = rule_info["description"][:120]

    header = SCRIPT_HEADER.format(
        rule_name=rule_name,
        source=source,
        category=rule_info["category"],
        standards=standards_str,
        description=desc,
    )

    arch = scan_info["arch"] if scan_info else ""
    arch_check = ""
    if arch:
        arch_check = f"""
rule_arch="{arch}"
if [[ "$arch" != "$rule_arch" ]]; then
    printf '{{"rule":"{rule_name}","action":"NOT_APPLICABLE","message":"Requires {arch} architecture"}}\\n'
    exit 2
fi
"""

    body = f"""{arch_check}
{fix_cmd}

printf '{{"rule":"{rule_name}","action":"EXECUTED","message":"Fix applied"}}\\n'
exit 0
"""
    return header + body


# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

def main():
    print("Parsing security_standards_comparison.md ...")
    rules = parse_comparison_md()
    print(f"  Found {len(rules)} rules")

    print("Parsing compliance.sh files ...")
    all_data = parse_all_standards()
    for std in STANDARDS_PRIORITY:
        if std in all_data:
            print(f"  {std}: {len(all_data[std]['scan'])} scan blocks, {len(all_data[std]['fix'])} fix blocks")

    # Output directories
    scan_dir = os.path.join(BUILD_DIR, "scripts", "scan")
    fix_dir = os.path.join(BUILD_DIR, "scripts", "fix")
    os.makedirs(scan_dir, exist_ok=True)
    os.makedirs(fix_dir, exist_ok=True)

    manifest = {}
    stats = {"scan": 0, "fix": 0, "no_scan": [], "no_fix": []}

    for rule_name in sorted(rules):
        rule_info = rules[rule_name]

        # Find scan info using priority order
        scan_info = None
        scan_source = None
        for std in STANDARDS_PRIORITY:
            if std in all_data and rule_name in all_data[std]["scan"]:
                info = extract_scan_info(all_data[std]["scan"][rule_name])
                if info["check_command"] and info["expected_value"] is not None:
                    scan_info = info
                    scan_source = std
                    break

        # Find fix commands using priority order
        fix_cmd = None
        fix_source = None
        for std in STANDARDS_PRIORITY:
            if std in all_data and rule_name in all_data[std]["fix"]:
                cmd = extract_fix_commands(all_data[std]["fix"][rule_name])
                if cmd:
                    fix_cmd = cmd
                    fix_source = std
                    break

        entry = {
            "rule": rule_name,
            "description": rule_info["description"],
            "category": rule_info["category"],
            "standards": {k: v for k, v in rule_info["standards"].items() if v},
            "scan_script": None,
            "fix_script": None,
            "scan_source": scan_source,
            "fix_source": fix_source,
        }

        # Generate scan script
        if scan_info:
            script = generate_scan_script(rule_name, rule_info, scan_info, scan_source)
            path = os.path.join(scan_dir, f"{rule_name}.sh")
            with open(path, "w") as f:
                f.write(script)
            os.chmod(path, os.stat(path).st_mode | stat.S_IEXEC | stat.S_IXGRP | stat.S_IXOTH)
            entry["scan_script"] = f"scripts/scan/{rule_name}.sh"
            stats["scan"] += 1
        else:
            stats["no_scan"].append(rule_name)

        # Generate fix script
        if fix_cmd:
            script = generate_fix_script(rule_name, rule_info, fix_cmd, scan_info, fix_source)
            path = os.path.join(fix_dir, f"{rule_name}.sh")
            with open(path, "w") as f:
                f.write(script)
            os.chmod(path, os.stat(path).st_mode | stat.S_IEXEC | stat.S_IXGRP | stat.S_IXOTH)
            entry["fix_script"] = f"scripts/fix/{rule_name}.sh"
            stats["fix"] += 1
        else:
            stats["no_fix"].append(rule_name)

        manifest[rule_name] = entry

    # Write manifest
    manifest_path = os.path.join(BUILD_DIR, "scripts", "manifest.json")
    with open(manifest_path, "w") as f:
        json.dump(manifest, f, indent=2, sort_keys=True)

    # Summary
    print(f"\nGenerated {stats['scan']} scan scripts  -> {scan_dir}")
    print(f"Generated {stats['fix']} fix scripts   -> {fix_dir}")
    print(f"Manifest                   -> {manifest_path}")

    if stats["no_scan"]:
        print(f"\nRules without scan ({len(stats['no_scan'])}):")
        for r in stats["no_scan"]:
            print(f"  - {r}")

    if stats["no_fix"]:
        print(f"\nRules without fix ({len(stats['no_fix'])}):")
        for r in stats["no_fix"]:
            print(f"  - {r}")


if __name__ == "__main__":
    main()
