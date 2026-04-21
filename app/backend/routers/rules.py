"""
Rules router — read-only views of compliance rules with latest scan status.
GET /api/rules          → all rules with last status
GET /api/rules/{rule}   → single rule detail + scan history
"""
import json
from typing import Optional
from fastapi import APIRouter, Depends, HTTPException, Query
from sqlalchemy.orm import Session

from core.database import get_db
from core.manifest import get_all_rules, get_rule, get_categories, get_standards, compute_severity, compute_impact
from core.models import ScanResult, Exemption, ScanSession

router = APIRouter(prefix="/api/rules", tags=["rules"])


def _latest_status(rule_name: str, db: Session) -> Optional[dict]:
    """Get the most recent scan result for a rule."""
    result = (
        db.query(ScanResult)
        .filter(ScanResult.rule == rule_name)
        .order_by(ScanResult.scanned_at.desc())
        .first()
    )
    if not result:
        return None
    return {
        "status": result.status,
        "result_value": result.result_value,
        "expected_value": result.expected_value,
        "scanned_at": result.scanned_at.isoformat() if result.scanned_at else None,
        "session_id": result.session_id,
    }


def _is_exempt(rule_name: str, db: Session) -> Optional[dict]:
    from datetime import datetime
    ex = db.query(Exemption).filter(
        Exemption.rule == rule_name,
        Exemption.is_active == True,
    ).first()
    if not ex:
        return None
    if ex.expires_at and ex.expires_at < datetime.utcnow():
        return None
    return {
        "reason": ex.reason,
        "expires_at": ex.expires_at.isoformat() if ex.expires_at else None,
        "granted_by": ex.granted_by,
        "granted_at": ex.granted_at.isoformat() if ex.granted_at else None,
    }


@router.get("")
def list_rules(
    category: Optional[str] = Query(None),
    status: Optional[str] = Query(None),
    standard: Optional[str] = Query(None),
    severity: Optional[str] = Query(None),
    q: Optional[str] = Query(None),
    db: Session = Depends(get_db),
):
    rules = get_all_rules()

    if category:
        rules = [r for r in rules if r.get("category", "").lower() == category.lower()]
    if standard:
        rules = [r for r in rules if r.get("standards", {}).get(standard)]
    if q:
        q_lower = q.lower()
        rules = [r for r in rules
                 if q_lower in r.get("rule", "").lower()
                 or q_lower in r.get("description", "").lower()]

    results = []
    for r in rules:
        latest = _latest_status(r["rule"], db)
        exemption = _is_exempt(r["rule"], db)
        current_status = "NEVER_SCANNED"
        if exemption:
            current_status = "EXEMPT"
        elif latest:
            current_status = latest["status"]
        elif not r.get("scan_script"):
            current_status = "MDM_REQUIRED"

        if status and current_status != status:
            continue

        results.append({
            **r,
            "current_status": current_status,
            "last_scan": latest,
            "exemption": exemption,
            "has_scan": bool(r.get("scan_script")),
            "has_fix": bool(r.get("fix_script")),
            "severity": compute_severity(r),
            "impact": compute_impact(r),
        })

    if severity:
        results = [r for r in results if r["severity"] == severity.lower()]

    return {"rules": results, "total": len(results)}


@router.get("/meta")
def get_meta():
    """Return available categories and standards for filter dropdowns."""
    return {"categories": get_categories(), "standards": get_standards()}


@router.get("/{rule_name}")
def get_rule_detail(
    rule_name: str,
    db: Session = Depends(get_db),
):
    rule = get_rule(rule_name)
    if not rule:
        raise HTTPException(status_code=404, detail=f"Rule not found: {rule_name}")

    latest = _latest_status(rule_name, db)
    exemption = _is_exempt(rule_name, db)

    # Last 30 scan results for history sparkline
    history = (
        db.query(ScanResult)
        .filter(ScanResult.rule == rule_name)
        .order_by(ScanResult.scanned_at.desc())
        .limit(30)
        .all()
    )
    history_list = [
        {
            "status": h.status,
            "scanned_at": h.scanned_at.isoformat() if h.scanned_at else None,
            "session_id": h.session_id,
        }
        for h in reversed(history)
    ]

    current_status = "NEVER_SCANNED"
    if exemption:
        current_status = "EXEMPT"
    elif latest:
        current_status = latest["status"]
    elif not rule.get("scan_script"):
        current_status = "MDM_REQUIRED"

    return {
        **rule,
        "current_status": current_status,
        "last_scan": latest,
        "exemption": exemption,
        "scan_history": history_list,
        "has_scan": bool(rule.get("scan_script")),
        "has_fix": bool(rule.get("fix_script")),
        "severity": compute_severity(rule),
        "impact": compute_impact(rule),
    }
