"""
Fix router — run remediation scripts.
POST /api/rules/{rule}/fix  → apply fix + auto-rescan, return result
"""
import logging
from datetime import datetime

from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy.orm import Session

import core.audit as audit
from core.auth import verify_token
from core.database import get_db
from core.manifest import get_rule
from core.models import FixResult, ScanResult, ScanSession
from core.runner_client import fix_rule, scan_rule, RunnerError

logger = logging.getLogger(__name__)
router = APIRouter(tags=["fixes"])


@router.post("/api/rules/{rule_name}/fix")
async def apply_fix(
    rule_name: str,
    db: Session = Depends(get_db),
    _: str = Depends(verify_token),
):
    rule = get_rule(rule_name)
    if not rule:
        raise HTTPException(status_code=404, detail=f"Rule not found: {rule_name}")
    if not rule.get("fix_script"):
        raise HTTPException(status_code=422, detail="No fix script available for this rule")

    # Get current scan status before fix
    last_scan = (
        db.query(ScanResult)
        .filter(ScanResult.rule == rule_name)
        .order_by(ScanResult.scanned_at.desc())
        .first()
    )
    scan_before = last_scan.status if last_scan else "UNKNOWN"

    try:
        fix_res = await fix_rule(rule_name)
    except RunnerError as e:
        raise HTTPException(status_code=503, detail=str(e))

    # Auto-rescan after fix (best effort)
    scan_after = None
    scan_res = None
    if rule.get("scan_script"):
        try:
            scan_res = await scan_rule(rule_name)
            scan_after = scan_res.get("status")

            # Store the rescan result
            session = ScanSession(
                started_at=datetime.utcnow(),
                finished_at=datetime.utcnow(),
                triggered_by="fix_rescan",
                filter_json=f'{{"rule":"{rule_name}"}}',
                total_rules=1,
                pass_count=1 if scan_after == "PASS" else 0,
                fail_count=1 if scan_after == "FAIL" else 0,
                score_pct=100.0 if scan_after == "PASS" else 0.0,
            )
            db.add(session)
            db.commit()
            db.refresh(session)

            db.add(ScanResult(
                session_id=session.id,
                scanned_at=datetime.utcnow(),
                rule=rule_name,
                category=rule.get("category", ""),
                status=scan_after,
                result_value=scan_res.get("result"),
                expected_value=scan_res.get("expected"),
            ))
            db.commit()
        except Exception as e:
            logger.warning("Auto-rescan after fix failed for %s: %s", rule_name, e)

    fix_record = FixResult(
        executed_at=datetime.utcnow(),
        rule=rule_name,
        action=fix_res.get("action"),
        message=fix_res.get("message"),
        exit_code=fix_res.get("exit_code"),
        duration_ms=fix_res.get("duration_ms"),
        scan_before=scan_before,
        scan_after=scan_after,
    )
    db.add(fix_record)
    db.commit()

    audit.log_action(db, audit.FIX_APPLIED, rule_name, {
        "action": fix_res.get("action"),
        "scan_before": scan_before,
        "scan_after": scan_after,
    })

    return {
        "rule": rule_name,
        "fix": fix_res,
        "scan_before": scan_before,
        "scan_after": scan_after,
        "scan_result": scan_res,
        "changed": scan_before != scan_after,
    }


@router.get("/api/rules/{rule_name}/fix-history")
def get_fix_history(
    rule_name: str,
    db: Session = Depends(get_db),
    _: str = Depends(verify_token),
):
    results = (
        db.query(FixResult)
        .filter(FixResult.rule == rule_name)
        .order_by(FixResult.executed_at.desc())
        .limit(20)
        .all()
    )
    return {
        "rule": rule_name,
        "history": [
            {
                "id": r.id,
                "executed_at": r.executed_at.isoformat() if r.executed_at else None,
                "action": r.action,
                "message": r.message,
                "scan_before": r.scan_before,
                "scan_after": r.scan_after,
                "exit_code": r.exit_code,
            }
            for r in results
        ],
    }
