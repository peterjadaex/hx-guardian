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
