"""
Scans router — start scan sessions, track progress, retrieve results.
POST /api/scans              → start scan session, returns {session_id}
GET  /api/scans/{id}         → session status summary
GET  /api/scans/{id}/results → paginated results
POST /api/rules/{rule}/scan  → single rule scan (immediate)
"""
import asyncio
import json
import logging
from datetime import datetime
from typing import Optional

from fastapi import APIRouter, BackgroundTasks, Depends, HTTPException, Query
from pydantic import BaseModel
from sqlalchemy.orm import Session

import core.audit as audit
from core.database import get_db, SessionLocal
from core.manifest import get_all_rules, get_rules_by_category, get_rules_by_standard, get_rule
from core.models import ScanSession, ScanResult, Exemption
from core.runner_client import scan_rule, scan_batch_stream, RunnerError

logger = logging.getLogger(__name__)
router = APIRouter(tags=["scans"])

# In-memory set of active session IDs (for SSE streaming)
_active_sessions: dict[int, asyncio.Queue] = {}


class ScanRequest(BaseModel):
    filter: Optional[dict] = None   # {"category": "Auditing"} or {"standard": "cisv8"}


def _get_rule_list(filter_dict: Optional[dict]) -> Optional[list[str]]:
    if not filter_dict:
        return None  # all scannable rules
    if filter_dict.get("category"):
        return [r["rule"] for r in get_rules_by_category(filter_dict["category"])
                if r.get("scan_script")]
    if filter_dict.get("standard"):
        return [r["rule"] for r in get_rules_by_standard(filter_dict["standard"])
                if r.get("scan_script")]
    return None


def _active_exemptions(db: Session) -> set[str]:
    from datetime import datetime
    exemptions = db.query(Exemption).filter(
        Exemption.is_active == True,
    ).all()
    return {
        ex.rule for ex in exemptions
        if not ex.expires_at or ex.expires_at > datetime.utcnow()
    }


async def execute_scan_session(session_id: int, rules: Optional[list[str]] = None):
    """Background task: run all scans and stream results to SSE queue."""
    db = SessionLocal()
    queue = asyncio.Queue()
    _active_sessions[session_id] = queue

    try:
        session = db.query(ScanSession).filter(ScanSession.id == session_id).first()
        if not session:
            return

        exempt_rules = _active_exemptions(db)
        all_rules = get_all_rules()
        manifest_map = {r["rule"]: r for r in all_rules}

        if rules is None:
            scan_rules = [r["rule"] for r in all_rules if r.get("scan_script")]
            mdm_rules = [r["rule"] for r in all_rules if not r.get("scan_script")]
        else:
            scan_rules = [r for r in rules if manifest_map.get(r, {}).get("scan_script")]
            mdm_rules = [r for r in rules if not manifest_map.get(r, {}).get("scan_script")]

        # Pre-insert exempt and MDM results
        now = datetime.utcnow()
        for rule_name in exempt_rules & (set(scan_rules) | set(mdm_rules)):
            rule_meta = manifest_map.get(rule_name, {})
            result = ScanResult(
                session_id=session_id,
                scanned_at=now,
                rule=rule_name,
                category=rule_meta.get("category", ""),
                status="EXEMPT",
                message="Rule is currently exempt",
            )
            db.add(result)

        for rule_name in mdm_rules:
            if rule_name not in exempt_rules:
                rule_meta = manifest_map.get(rule_name, {})
                result = ScanResult(
                    session_id=session_id,
                    scanned_at=now,
                    rule=rule_name,
                    category=rule_meta.get("category", ""),
                    status="MDM_REQUIRED",
                    message="Requires MDM configuration profile",
                )
                db.add(result)
        db.commit()

        pass_count = fail_count = na_count = error_count = mdm_count = exempt_count = 0
        exempt_count = len(exempt_rules & (set(scan_rules) | set(mdm_rules)))
        mdm_count = len([r for r in mdm_rules if r not in exempt_rules])

        # Stream scan results
        scan_target = [r for r in scan_rules if r not in exempt_rules]
        async for res in scan_batch_stream(scan_target):
            rule_name = res.get("rule", "")
            status = res.get("status", "ERROR")
            rule_meta = manifest_map.get(rule_name, {})

            scan_result = ScanResult(
                session_id=session_id,
                scanned_at=datetime.utcnow(),
                rule=rule_name,
                category=rule_meta.get("category", ""),
                status=status,
                result_value=res.get("result"),
                expected_value=res.get("expected"),
                message=res.get("message"),
                exit_code=res.get("exit_code"),
                duration_ms=res.get("duration_ms"),
            )
            db.add(scan_result)
            db.commit()

            if status == "PASS":
                pass_count += 1
            elif status == "FAIL":
                fail_count += 1
            elif status == "NOT_APPLICABLE":
                na_count += 1
            else:
                error_count += 1

            await queue.put({"type": "result", **res, "session_id": session_id})

        # Update session totals
        total = pass_count + fail_count + na_count + error_count + mdm_count + exempt_count
        score = round(pass_count / max(pass_count + fail_count + error_count, 1) * 100, 1)

        session.finished_at = datetime.utcnow()
        session.total_rules = total
        session.pass_count = pass_count
        session.fail_count = fail_count
        session.na_count = na_count
        session.error_count = error_count
        session.mdm_count = mdm_count
        session.exempt_count = exempt_count
        session.score_pct = score
        db.commit()

        audit.log_action(db, audit.SCAN_COMPLETE, f"session:{session_id}", {
            "total": total, "pass": pass_count, "fail": fail_count, "score": score,
        })

        await queue.put({"type": "complete", "session_id": session_id,
                         "score_pct": score, "pass": pass_count, "fail": fail_count,
                         "na": na_count, "error": error_count, "total": total})

    except RunnerError as e:
        logger.error("Runner error during scan session %d: %s", session_id, e)
        await queue.put({"type": "error", "session_id": session_id, "message": str(e)})
    except Exception as e:
        logger.error("Scan session %d error: %s", session_id, e)
        await queue.put({"type": "error", "session_id": session_id, "message": str(e)})
    finally:
        db.close()
        await asyncio.sleep(30)  # keep queue alive for late SSE consumers
        _active_sessions.pop(session_id, None)


@router.post("/api/scans")
async def start_scan(
    body: ScanRequest,
    background_tasks: BackgroundTasks,
    db: Session = Depends(get_db),
):
    rules = _get_rule_list(body.filter)
    session = ScanSession(
        started_at=datetime.utcnow(),
        triggered_by="manual",
        filter_json=json.dumps(body.filter) if body.filter else None,
    )
    db.add(session)
    db.commit()
    db.refresh(session)

    audit.log_action(db, audit.SCAN_RUN, f"session:{session.id}",
                     {"filter": body.filter})

    background_tasks.add_task(execute_scan_session, session.id, rules)
    return {"session_id": session.id, "status": "running"}


@router.get("/api/scans/{session_id}")
def get_session(
    session_id: int,
    db: Session = Depends(get_db),
):
    session = db.query(ScanSession).filter(ScanSession.id == session_id).first()
    if not session:
        raise HTTPException(status_code=404, detail="Session not found")
    return {
        "id": session.id,
        "started_at": session.started_at.isoformat() if session.started_at else None,
        "finished_at": session.finished_at.isoformat() if session.finished_at else None,
        "triggered_by": session.triggered_by,
        "total_rules": session.total_rules,
        "pass_count": session.pass_count,
        "fail_count": session.fail_count,
        "na_count": session.na_count,
        "error_count": session.error_count,
        "mdm_count": session.mdm_count,
        "exempt_count": session.exempt_count,
        "score_pct": session.score_pct,
        "is_running": session.finished_at is None,
    }


@router.get("/api/scans/{session_id}/results")
def get_session_results(
    session_id: int,
    limit: int = Query(100, ge=1, le=500),
    offset: int = Query(0, ge=0),
    status: Optional[str] = Query(None),
    category: Optional[str] = Query(None),
    db: Session = Depends(get_db),
):
    q = db.query(ScanResult).filter(ScanResult.session_id == session_id)
    if status:
        q = q.filter(ScanResult.status == status)
    if category:
        q = q.filter(ScanResult.category == category)
    total = q.count()
    results = q.order_by(ScanResult.rule).offset(offset).limit(limit).all()
    return {
        "session_id": session_id,
        "total": total,
        "offset": offset,
        "results": [
            {
                "rule": r.rule,
                "category": r.category,
                "status": r.status,
                "result_value": r.result_value,
                "expected_value": r.expected_value,
                "message": r.message,
                "scanned_at": r.scanned_at.isoformat() if r.scanned_at else None,
                "duration_ms": r.duration_ms,
            }
            for r in results
        ],
    }


@router.post("/api/rules/{rule_name}/scan")
async def scan_single_rule(
    rule_name: str,
    db: Session = Depends(get_db),
):
    rule = get_rule(rule_name)
    if not rule:
        raise HTTPException(status_code=404, detail=f"Rule not found: {rule_name}")
    if not rule.get("scan_script"):
        return {"rule": rule_name, "status": "MDM_REQUIRED",
                "message": "No scan script — requires MDM configuration profile"}

    try:
        res = await scan_rule(rule_name)
    except RunnerError as e:
        raise HTTPException(status_code=503, detail=str(e))

    # Store result in a new single-rule session
    session = ScanSession(
        started_at=datetime.utcnow(),
        finished_at=datetime.utcnow(),
        triggered_by="manual",
        filter_json=json.dumps({"rule": rule_name}),
        total_rules=1,
        pass_count=1 if res.get("status") == "PASS" else 0,
        fail_count=1 if res.get("status") == "FAIL" else 0,
        na_count=1 if res.get("status") == "NOT_APPLICABLE" else 0,
        error_count=1 if res.get("status") == "ERROR" else 0,
        score_pct=100.0 if res.get("status") == "PASS" else 0.0,
    )
    db.add(session)
    db.commit()
    db.refresh(session)

    scan_result = ScanResult(
        session_id=session.id,
        scanned_at=datetime.utcnow(),
        rule=rule_name,
        category=rule.get("category", ""),
        status=res.get("status", "ERROR"),
        result_value=res.get("result"),
        expected_value=res.get("expected"),
        message=res.get("message"),
        exit_code=res.get("exit_code"),
        duration_ms=res.get("duration_ms"),
    )
    db.add(scan_result)
    db.commit()

    return res
