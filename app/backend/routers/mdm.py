"""
MDM profiles router — map rules to mobileconfig profiles.
GET /api/device/profiles         → list profiles with install status
GET /api/device/profiles/refresh → re-check installed profiles
GET /api/device/profiles/{id}/download → serve mobileconfig file
"""
import asyncio
import json
import logging
import re
from datetime import datetime
from pathlib import Path
from typing import Optional

from fastapi import APIRouter, Depends, HTTPException
from fastapi.responses import FileResponse
from sqlalchemy.orm import Session

from core.auth import verify_token
from core.database import get_db
from core.models import MdmProfile

logger = logging.getLogger(__name__)
router = APIRouter(prefix="/api/device/profiles", tags=["mdm"])

STANDARDS_BASE = Path(__file__).parent.parent.parent.parent / "standards"


def _discover_profiles() -> list[dict]:
    """
    Discover all mobileconfig files across the standards directory
    and build a mapping of profile_id → {standard, path, display_name, rules}.
    """
    profiles = {}
    for standard in ["800-53r5_high", "cisv8", "cis_lvl2"]:
        mobileconfigs_dir = STANDARDS_BASE / standard / "mobileconfigs" / "unsigned"
        if not mobileconfigs_dir.exists():
            continue
        for mc_file in mobileconfigs_dir.glob("*.mobileconfig"):
            try:
                content = mc_file.read_text(errors="replace")
                # Extract PayloadIdentifier
                m = re.search(r"<key>PayloadIdentifier</key>\s*<string>([^<]+)</string>", content)
                profile_id = m.group(1) if m else mc_file.stem
                # Extract PayloadDisplayName
                m2 = re.search(r"<key>PayloadDisplayName</key>\s*<string>([^<]+)</string>", content)
                display_name = m2.group(1) if m2 else mc_file.stem

                if profile_id not in profiles:
                    profiles[profile_id] = {
                        "profile_id": profile_id,
                        "display_name": display_name,
                        "standard": standard,
                        "mobileconfig_path": str(mc_file),
                        "rules": [],
                    }
            except Exception as e:
                logger.warning("Failed to parse %s: %s", mc_file, e)

    # Associate MDM-only rules to profiles based on their preference domain
    from core.manifest import get_mdm_only_rules
    mdm_rules = get_mdm_only_rules()

    # Simple heuristic: map rules by looking at preference domain patterns
    domain_rule_map = {
        "com.apple.MCX": [],
        "com.apple.security.firewall": [],
        "com.apple.security.smartcard": [],
        "com.apple.mobiledevice.passwordpolicy": [],
        "com.apple.loginwindow": [],
        "com.apple.screensaver": [],
        "com.apple.SoftwareUpdate": [],
        "com.apple.Safari": [],
        "com.apple.icloud": [],
    }

    for rule in mdm_rules:
        rule_name = rule["rule"]
        if "password" in rule_name or "lockout" in rule_name or "complexity" in rule_name:
            domain_rule_map.get("com.apple.mobiledevice.passwordpolicy", []).append(rule_name)
        elif "firewall" in rule_name:
            domain_rule_map.get("com.apple.security.firewall", []).append(rule_name)
        elif "smartcard" in rule_name or "pam" in rule_name:
            domain_rule_map.get("com.apple.security.smartcard", []).append(rule_name)
        elif "screensaver" in rule_name:
            domain_rule_map.get("com.apple.screensaver", []).append(rule_name)
        elif "icloud" in rule_name or "safari" in rule_name:
            domain_rule_map.get("com.apple.Safari", []).append(rule_name)
        else:
            domain_rule_map.get("com.apple.MCX", []).append(rule_name)

    # Apply mappings to profiles
    for profile in profiles.values():
        for domain, rules in domain_rule_map.items():
            if domain in profile["profile_id"] or domain in profile.get("display_name", ""):
                profile["rules"].extend(rules)

    return list(profiles.values())


async def _check_installed_profiles() -> set[str]:
    """Run 'profiles list' to detect installed MDM profiles."""
    try:
        proc = await asyncio.create_subprocess_exec(
            "/usr/bin/profiles", "list",
            stdout=asyncio.subprocess.PIPE,
            stderr=asyncio.subprocess.DEVNULL,
        )
        stdout, _ = await asyncio.wait_for(proc.communicate(), timeout=10.0)
        output = stdout.decode("utf-8", errors="replace")
        # Extract profile identifiers from output
        installed = set(re.findall(r"profileIdentifier: ([^\s]+)", output))
        # Also try JSON format
        if not installed:
            try:
                proc2 = await asyncio.create_subprocess_exec(
                    "/usr/bin/profiles", "list", "-output", "stdout-xml",
                    stdout=asyncio.subprocess.PIPE,
                    stderr=asyncio.subprocess.DEVNULL,
                )
                xml_out, _ = await asyncio.wait_for(proc2.communicate(), timeout=10.0)
                installed = set(re.findall(
                    r"<key>ProfileIdentifier</key>\s*<string>([^<]+)</string>",
                    xml_out.decode("utf-8", errors="replace")
                ))
            except Exception:
                pass
        return installed
    except Exception as e:
        logger.warning("profiles list failed: %s", e)
        return set()


@router.get("")
async def list_profiles(
    db: Session = Depends(get_db),
    _: str = Depends(verify_token),
):
    discovered = _discover_profiles()
    installed_ids = await _check_installed_profiles()

    # Upsert into DB for tracking
    for p in discovered:
        existing = db.query(MdmProfile).filter(MdmProfile.profile_id == p["profile_id"]).first()
        is_installed = p["profile_id"] in installed_ids
        if existing:
            existing.is_installed = is_installed
            existing.last_checked = datetime.utcnow()
            existing.rules_json = json.dumps(p["rules"])
        else:
            db.add(MdmProfile(
                profile_id=p["profile_id"],
                display_name=p["display_name"],
                standard=p["standard"],
                is_installed=is_installed,
                last_checked=datetime.utcnow(),
                mobileconfig_path=p["mobileconfig_path"],
                rules_json=json.dumps(p["rules"]),
            ))
    db.commit()

    return {
        "profiles": [
            {**p, "is_installed": p["profile_id"] in installed_ids}
            for p in discovered
        ],
        "total": len(discovered),
        "installed_count": len(installed_ids),
    }


@router.get("/refresh")
async def refresh_profiles(
    db: Session = Depends(get_db),
    _: str = Depends(verify_token),
):
    """Re-run profile check and update DB."""
    installed_ids = await _check_installed_profiles()
    profiles = db.query(MdmProfile).all()
    for p in profiles:
        p.is_installed = p.profile_id in installed_ids
        p.last_checked = datetime.utcnow()
    db.commit()
    return {"installed_count": len(installed_ids), "checked_at": datetime.utcnow().isoformat()}


@router.get("/{profile_id:path}/download")
async def download_profile(
    profile_id: str,
    db: Session = Depends(get_db),
    _: str = Depends(verify_token),
):
    """Serve a mobileconfig file for download."""
    profile = db.query(MdmProfile).filter(MdmProfile.profile_id == profile_id).first()
    if not profile or not profile.mobileconfig_path:
        # Try to discover it
        discovered = _discover_profiles()
        match = next((p for p in discovered if p["profile_id"] == profile_id), None)
        if not match:
            raise HTTPException(status_code=404, detail="Profile not found")
        path = Path(match["mobileconfig_path"])
    else:
        path = Path(profile.mobileconfig_path)

    if not path.exists():
        raise HTTPException(status_code=404, detail="Mobileconfig file not found on disk")

    # Security: ensure the path is inside the standards directory
    try:
        path.resolve().relative_to(STANDARDS_BASE.resolve())
    except ValueError:
        raise HTTPException(status_code=403, detail="Access denied")

    return FileResponse(
        path=str(path),
        media_type="application/x-apple-aspen-config",
        filename=path.name,
    )
