"""
MDM profiles router — map rules to mobileconfig profiles.
GET  /api/device/profiles              → list profiles with install status
GET  /api/device/profiles/refresh      → re-check installed profiles
POST /api/device/profiles/install-all  → install all profiles (optional standard filter)
GET  /api/device/profiles/install-all/stream → SSE stream for batch install progress
GET  /api/device/profiles/{id}/download → serve mobileconfig file
POST /api/device/profiles/{id}/install  → install a single profile via runner
"""
import asyncio
import json
import logging
import re
import sys
from datetime import datetime
from pathlib import Path
from typing import AsyncGenerator, Optional

from fastapi import APIRouter, Depends, HTTPException, Request
from fastapi.responses import FileResponse, StreamingResponse
from pydantic import BaseModel
from sqlalchemy.orm import Session

from core import audit, runner_client
from core.database import get_db
from core.models import MdmProfile

logger = logging.getLogger(__name__)
router = APIRouter(prefix="/api/device/profiles", tags=["mdm"])

if getattr(sys, 'frozen', False):
    STANDARDS_BASE = Path("/Library/Application Support/hxguardian")
else:
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
                # Extract top-level PayloadIdentifier — use the LAST match because
                # payload content items also have PayloadIdentifier (with mscp. prefix
                # and UUID) and appear earlier in the file than the top-level one.
                ids = re.findall(r"<key>PayloadIdentifier</key>\s*<string>([^<]+)</string>", content)
                profile_id = ids[-1] if ids else mc_file.stem
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
    try:
        from core.manifest import get_mdm_only_rules
        mdm_rules = get_mdm_only_rules()
    except Exception as e:
        logger.warning("Could not load MDM rules from manifest: %s", e)
        mdm_rules = []

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
    """Check installed MDM profiles via the privileged runner daemon (runs as root)."""
    try:
        from core.runner_client import list_profiles as _runner_list_profiles
        return await _runner_list_profiles()
    except Exception as e:
        logger.warning("profiles list via runner failed: %s", e)
        return set()


@router.get("")
async def list_profiles(
    db: Session = Depends(get_db),
):
    try:
        discovered = _discover_profiles()
    except Exception as e:
        logger.error("Failed to discover MDM profiles: %s", e)
        raise HTTPException(status_code=503, detail=f"Profile discovery failed: {e}")

    installed_ids = await _check_installed_profiles()

    # Upsert into DB for tracking
    try:
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
    except Exception as e:
        logger.error("Failed to update MDM profile records in DB: %s", e)
        db.rollback()
        # Still return whatever was discovered even if DB write failed
        return {
            "profiles": [
                {**p, "is_installed": p["profile_id"] in installed_ids}
                for p in discovered
            ],
            "total": len(discovered),
            "installed_count": len(installed_ids),
        }

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
):
    """Re-run profile check and update DB."""
    installed_ids = await _check_installed_profiles()
    profiles = db.query(MdmProfile).all()
    for p in profiles:
        p.is_installed = p.profile_id in installed_ids
        p.last_checked = datetime.utcnow()
    db.commit()
    return {"installed_count": len(installed_ids), "checked_at": datetime.utcnow().isoformat()}


class InstallAllRequest(BaseModel):
    standard: Optional[str] = None


def _resolve_profile_path(profile_id: str, db: Session) -> str:
    """Look up the mobileconfig_path for a profile_id from DB or discovery."""
    profile = db.query(MdmProfile).filter(MdmProfile.profile_id == profile_id).first()
    if profile and profile.mobileconfig_path:
        return profile.mobileconfig_path
    discovered = _discover_profiles()
    match = next((p for p in discovered if p["profile_id"] == profile_id), None)
    if not match:
        raise HTTPException(status_code=404, detail="Profile not found")
    return match["mobileconfig_path"]


@router.post("/install-all")
async def install_all_profiles(
    body: InstallAllRequest = InstallAllRequest(),
    db: Session = Depends(get_db),
):
    """Install all (or per-standard) profiles via the runner daemon."""
    discovered = _discover_profiles()
    installed_ids = await _check_installed_profiles()

    profiles_to_install = [
        p for p in discovered
        if p["profile_id"] not in installed_ids
        and (body.standard is None or p["standard"] == body.standard)
    ]

    if not profiles_to_install:
        return {"installed": 0, "failed": 0, "results": [],
                "message": "All profiles already installed"}

    results = []
    installed = 0
    failed = 0

    for p in profiles_to_install:
        try:
            result = await runner_client.install_profile(p["mobileconfig_path"])
            status = result.get("status", "ERROR")
            results.append({
                "profile_id": p["profile_id"],
                "display_name": p["display_name"],
                "status": status,
                "message": result.get("message", ""),
            })
            if status == "INSTALLED":
                installed += 1
                audit.log_action(db, audit.PROFILE_INSTALLED,
                                 target=p["profile_id"],
                                 detail={"standard": p["standard"]})
            else:
                failed += 1
                audit.log_action(db, audit.PROFILE_INSTALL_FAILED,
                                 target=p["profile_id"],
                                 detail={"status": status,
                                         "message": result.get("message", "")})
        except runner_client.RunnerError as e:
            failed += 1
            results.append({
                "profile_id": p["profile_id"],
                "display_name": p["display_name"],
                "status": "ERROR",
                "message": str(e),
            })

    return {"installed": installed, "failed": failed, "results": results}


async def _install_stream_generator(
    profiles: list[dict], db: Session
) -> AsyncGenerator[str, None]:
    """Install profiles one at a time and yield SSE events."""
    total = len(profiles)
    installed = 0
    failed = 0

    for i, p in enumerate(profiles):
        try:
            result = await runner_client.install_profile(p["mobileconfig_path"])
            status = result.get("status", "ERROR")
            if status == "INSTALLED":
                installed += 1
                audit.log_action(db, audit.PROFILE_INSTALLED,
                                 target=p["profile_id"],
                                 detail={"standard": p["standard"]})
            else:
                failed += 1
                audit.log_action(db, audit.PROFILE_INSTALL_FAILED,
                                 target=p["profile_id"],
                                 detail={"status": status,
                                         "message": result.get("message", "")})
            event = {
                "profile_id": p["profile_id"],
                "display_name": p["display_name"],
                "status": status,
                "message": result.get("message", ""),
                "progress": i + 1,
                "total": total,
            }
        except runner_client.RunnerError as e:
            failed += 1
            event = {
                "profile_id": p["profile_id"],
                "display_name": p["display_name"],
                "status": "ERROR",
                "message": str(e),
                "progress": i + 1,
                "total": total,
            }

        yield f"event: profile_install\ndata: {json.dumps(event)}\n\n"

    summary = {"installed": installed, "failed": failed, "total": total}
    yield f"event: complete\ndata: {json.dumps(summary)}\n\n"


@router.get("/install-all/stream")
async def install_all_stream(
    standard: Optional[str] = None,
    db: Session = Depends(get_db),
):
    """SSE stream that installs profiles and reports progress in real time."""
    discovered = _discover_profiles()
    installed_ids = await _check_installed_profiles()

    profiles_to_install = [
        p for p in discovered
        if p["profile_id"] not in installed_ids
        and (standard is None or p["standard"] == standard)
    ]

    if not profiles_to_install:
        async def empty_gen():
            yield f"event: complete\ndata: {json.dumps({'installed': 0, 'failed': 0, 'total': 0, 'message': 'All profiles already installed'})}\n\n"
        return StreamingResponse(empty_gen(), media_type="text/event-stream",
                                 headers={"Cache-Control": "no-cache",
                                          "X-Accel-Buffering": "no",
                                          "Connection": "keep-alive"})

    return StreamingResponse(
        _install_stream_generator(profiles_to_install, db),
        media_type="text/event-stream",
        headers={"Cache-Control": "no-cache",
                 "X-Accel-Buffering": "no",
                 "Connection": "keep-alive"},
    )


@router.post("/{profile_id:path}/install")
async def install_profile(
    profile_id: str,
    db: Session = Depends(get_db),
):
    """Install a single MDM profile via the runner daemon."""
    mc_path = _resolve_profile_path(profile_id, db)

    try:
        result = await runner_client.install_profile(mc_path)
    except runner_client.RunnerError as e:
        raise HTTPException(status_code=502, detail=str(e))

    status = result.get("status", "ERROR")
    if status == "INSTALLED":
        # Update DB
        existing = db.query(MdmProfile).filter(MdmProfile.profile_id == profile_id).first()
        if existing:
            existing.is_installed = True
            existing.last_checked = datetime.utcnow()
            db.commit()
        audit.log_action(db, audit.PROFILE_INSTALLED, target=profile_id)
    else:
        audit.log_action(db, audit.PROFILE_INSTALL_FAILED, target=profile_id,
                         detail={"status": status, "message": result.get("message", "")})

    return {
        "profile_id": profile_id,
        "status": status,
        "message": result.get("message", ""),
    }


@router.get("/{profile_id:path}/download")
async def download_profile(
    profile_id: str,
    db: Session = Depends(get_db),
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
