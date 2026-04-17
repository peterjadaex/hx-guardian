"""
Manifest loader — reads standards/scripts/manifest.json and provides
rule lookup, filtering, and path resolution helpers.
"""
import json
from functools import lru_cache
from pathlib import Path
from typing import Optional

STANDARDS_BASE = Path(__file__).parent.parent.parent.parent / "standards"
MANIFEST_PATH = STANDARDS_BASE / "scripts" / "manifest.json"


@lru_cache(maxsize=1)
def load_manifest() -> dict:
    """Load and cache the manifest. Returns dict keyed by rule name."""
    if not MANIFEST_PATH.exists():
        raise FileNotFoundError(f"Manifest not found: {MANIFEST_PATH}")
    with open(MANIFEST_PATH) as f:
        return json.load(f)


def get_all_rules() -> list[dict]:
    return list(load_manifest().values())


def get_rule(name: str) -> Optional[dict]:
    return load_manifest().get(name)


def get_scannable_rules() -> list[dict]:
    return [r for r in get_all_rules() if r.get("scan_script")]


def get_fixable_rules() -> list[dict]:
    return [r for r in get_all_rules() if r.get("fix_script")]


def get_mdm_only_rules() -> list[dict]:
    return [r for r in get_all_rules() if not r.get("scan_script") and not r.get("fix_script")]


def get_rules_by_category(category: str) -> list[dict]:
    return [r for r in get_all_rules() if r.get("category", "").lower() == category.lower()]


def get_rules_by_standard(standard: str) -> list[dict]:
    return [r for r in get_all_rules() if r.get("standards", {}).get(standard)]


def resolve_scan_script(rule_name: str) -> Optional[str]:
    rule = get_rule(rule_name)
    if not rule or not rule.get("scan_script"):
        return None
    return str(STANDARDS_BASE / rule["scan_script"])


def resolve_fix_script(rule_name: str) -> Optional[str]:
    rule = get_rule(rule_name)
    if not rule or not rule.get("fix_script"):
        return None
    return str(STANDARDS_BASE / rule["fix_script"])


def get_categories() -> list[str]:
    cats = {r.get("category", "") for r in get_all_rules()}
    return sorted(c for c in cats if c)


def get_standards() -> list[str]:
    return ["800-53r5_high", "cisv8", "cis_lvl2"]


def is_valid_rule(name: str) -> bool:
    return name in load_manifest()


# ── Severity & impact ─────────────────────────────────────────────────────────

_HIGH_CATEGORIES = {"Authentication", "Auditing"}
_LOW_CATEGORIES  = {"iCloud", "Other"}

_IMPACT_TEMPLATES: dict = {
    "Authentication":   "Without this control, unauthorized users may access the device or escalate privileges — potentially compromising signing keys and all signed artifacts.",
    "Auditing":         "Audit records will not be captured or may be tampered with. Signing operations cannot be traced, attributed, or audited, violating non-repudiation requirements.",
    "Operating System": "Core OS security is weakened. Attackers may gain elevated access, bypass signing restrictions, or exfiltrate cryptographic material.",
    "Password Policy":  "Weak password controls increase the risk of unauthorized account access. A compromised account on a signing device can result in fraudulent signatures.",
    "System Settings":  "Unnecessary services expose attack surface. Data may leak or external connections may be established, breaking airgap isolation.",
    "iCloud":           "Apple cloud sync may be active. Files, keychain entries, or clipboard content could be synced off the airgap device, exposing signing credentials.",
    "Other":            "Security control is not enforced. Review manual implementation requirements for this airgap environment.",
}


def compute_severity(rule: dict) -> str:
    """
    Derive severity from standards coverage and category.
    Returns 'high', 'medium', or 'low'.
    """
    category        = rule.get("category", "")
    standards       = rule.get("standards", {})
    standards_count = sum(1 for v in standards.values() if v)

    if category in _HIGH_CATEGORIES:
        return "high"
    if standards_count == 3:
        return "high"
    if category == "Operating System" and standards.get("800-53r5_high"):
        return "high"
    if category in _LOW_CATEGORIES:
        return "low"
    if standards_count == 1 and not standards.get("800-53r5_high"):
        return "low"
    return "medium"


def compute_impact(rule: dict) -> str:
    """Return the airgap-device impact statement for a rule's category."""
    return _IMPACT_TEMPLATES.get(rule.get("category", ""), _IMPACT_TEMPLATES["Other"])
