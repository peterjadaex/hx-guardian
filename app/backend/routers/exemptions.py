"""
Exemptions router — grant, list, and revoke rule exemptions.
GET    /api/exemptions         → list all exemptions
POST   /api/exemptions         → grant exemption
DELETE /api/exemptions/{rule}  → revoke exemption
"""
from datetime import datetime
from typing import Optional

from fastapi import APIRouter, BackgroundTasks, Depends, HTTPException
from pydantic import BaseModel
from sqlalchemy.orm import Session

import core.audit as audit
from core.two_factor import require_2fa
from core.database import get_db
from core.manifest import get_rule
from core.models import Exemption
from routers.scans import rescan_rule_background

router = APIRouter(prefix="/api/exemptions", tags=["exemptions"])


class ExemptionCreate(BaseModel):
    rule: str
    reason: str
    expires_at: Optional[str] = None  # ISO 8601 date string, or null for permanent


@router.get("")
def list_exemptions(
    db: Session = Depends(get_db),
):
    exemptions = db.query(Exemption).order_by(Exemption.granted_at.desc()).all()
    now = datetime.utcnow()
    return {
        "exemptions": [
            {
                "id": e.id,
                "rule": e.rule,
                "reason": e.reason,
                "expires_at": e.expires_at.isoformat() if e.expires_at else None,
                "granted_by": e.granted_by,
                "granted_at": e.granted_at.isoformat() if e.granted_at else None,
                "is_active": e.is_active,
                "is_expired": bool(e.expires_at and e.expires_at < now),
                "revoked_at": e.revoked_at.isoformat() if e.revoked_at else None,
            }
            for e in exemptions
        ]
    }


@router.post("")
def grant_exemption(
    body: ExemptionCreate,
    background_tasks: BackgroundTasks,
    db: Session = Depends(get_db),
    _: None = Depends(require_2fa),
):
    if not get_rule(body.rule):
        raise HTTPException(status_code=404, detail=f"Rule not found: {body.rule}")

    expires_at = None
    if body.expires_at:
        try:
            expires_at = datetime.fromisoformat(body.expires_at)
        except ValueError:
            raise HTTPException(status_code=422, detail="Invalid expires_at format — use ISO 8601")

    existing = db.query(Exemption).filter(Exemption.rule == body.rule).first()
    if existing:
        existing.reason = body.reason
        existing.expires_at = expires_at
        existing.granted_at = datetime.utcnow()
        existing.is_active = True
        existing.revoked_at = None
        db.commit()
        db.refresh(existing)
        exemption = existing
    else:
        exemption = Exemption(
            rule=body.rule,
            reason=body.reason,
            expires_at=expires_at,
        )
        db.add(exemption)
        db.commit()
        db.refresh(exemption)

    audit.log_action(db, audit.EXEMPTION_GRANTED, body.rule, {
        "reason": body.reason,
        "expires_at": body.expires_at,
    })

    # Trigger a rescan so the Rules page picks up the EXEMPT status without
    # waiting for the next full scan session.
    background_tasks.add_task(rescan_rule_background, body.rule)

    return {
        "id": exemption.id,
        "rule": exemption.rule,
        "reason": exemption.reason,
        "expires_at": exemption.expires_at.isoformat() if exemption.expires_at else None,
        "granted_at": exemption.granted_at.isoformat() if exemption.granted_at else None,
    }


@router.delete("/{rule_name}")
def revoke_exemption(
    rule_name: str,
    background_tasks: BackgroundTasks,
    db: Session = Depends(get_db),
    _: None = Depends(require_2fa),
):
    exemption = db.query(Exemption).filter(
        Exemption.rule == rule_name,
        Exemption.is_active == True,
    ).first()
    if not exemption:
        raise HTTPException(status_code=404, detail="No active exemption found for this rule")

    exemption.is_active = False
    exemption.revoked_at = datetime.utcnow()
    db.commit()

    audit.log_action(db, audit.EXEMPTION_REVOKED, rule_name)

    # Rescan the rule so its status updates from EXEMPT to its real result.
    background_tasks.add_task(rescan_rule_background, rule_name)

    return {"rule": rule_name, "revoked": True}
