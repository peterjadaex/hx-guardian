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
from datetime import datetime, timedelta
from typing import Optional

from fastapi import APIRouter, BackgroundTasks, Depends, HTTPException, Query
from pydantic import BaseModel
from sqlalchemy.orm import Session

import core.audit as audit
from core.database import get_db, SessionLocal
from core.manifest import get_all_rules, get_rules_by_category, get_rules_by_standard, get_rule
from core.models import (
    ScanSession, ScanResult, Exemption, VERIFICATION_TRIGGERS, NOT_ASSESSED,
)
from core.runner_client import scan_rule, scan_batch_stream, RunnerError
from core.runner_health import probe_runner

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


def _assessed(session: ScanSession) -> int:
    """Rules this session actually evaluated — the score's denominator."""
    return (session.pass_count or 0) + (session.fail_count or 0) + (session.error_count or 0)


def _bump(counts: dict, status: str, session_id: int) -> None:
    """Tally one result. Unknown statuses stay visible in the error bucket rather
    than silently vanishing, but they are logged so they get noticed."""
    if status == "PASS":
        counts["pass"] += 1
    elif status == "FAIL":
        counts["fail"] += 1
    elif status == "NOT_APPLICABLE":
        counts["na"] += 1
    elif status == NOT_ASSESSED:
        counts["not_assessed"] += 1
    elif status == "MDM_REQUIRED":
        # A stale-manifest runner can return this for a rule the server thinks is
        # scannable. It must not land in the score denominator as an ERROR, and
        # the session counter must agree with the per-row category rollup.
        counts["mdm"] += 1
    else:
        if status != "ERROR":
            logger.warning("session %d: unexpected status %r counted as ERROR",
                           session_id, status)
        counts["error"] += 1


def _reconcile_pending(db: Session, session_id: int, pending: set,
                       manifest_map: dict, counts: dict, degraded_detail: str) -> None:
    """Write a NOT_ASSESSED row for every requested rule that never got a result.

    Lives outside the main try-block so that an unexpected exception mid-stream
    (a failed commit, not just a RunnerError) still leaves every rule accounted
    for. Counters move only after the commit succeeds, so the session row can
    never claim NOT_ASSESSED rows that were rolled back.
    """
    if not pending:
        return
    db.rollback()   # a failed mid-loop commit leaves the session dirty
    now = datetime.utcnow()
    msg = ("Not assessed — "
           + (degraded_detail or "no result returned by the privileged runner"))[:1000]
    added = 0
    for rule_name in sorted(pending):
        db.add(ScanResult(
            session_id=session_id,
            scanned_at=now,
            rule=rule_name,
            category=manifest_map.get(rule_name, {}).get("category", ""),
            status=NOT_ASSESSED,
            message=msg,
            # Deliberately no exit_code: a 3 here would be indistinguishable
            # from a script that really did fail.
        ))
        added += 1
    db.commit()
    counts["not_assessed"] += added
    pending.clear()


def _finalise_session(db: Session, session_id: int, counts: dict,
                      degraded: Optional[str], degraded_detail: str) -> dict:
    """Close out a session on every exit path.

    Previously finished_at was only assigned after the result loop, so a runner
    failure left the session reporting is_running forever and the UI spinner
    never cleared. Called from `finally`, defensive, and idempotent.
    """
    db.rollback()   # the caller may have died mid-transaction
    session = db.query(ScanSession).filter(ScanSession.id == session_id).first()
    if not session:
        return {}

    total = sum(counts.values())
    assessed = counts["pass"] + counts["fail"] + counts["error"]
    # Score rule (operator decision): FAIL and ERROR are the non-compliant
    # outcomes; everything else counts as compliant. NOT_ASSESSED stays out of
    # both sides so a rule we never looked at can neither raise nor lower the
    # score — and with nothing but NOT_ASSESSED there is no percentage to
    # express at all (a 0.0 would read as "totally non-compliant" for a scan
    # that never ran).
    denominator = total - counts["not_assessed"]
    score = (round((denominator - counts["fail"] - counts["error"]) / denominator * 100, 1)
             if denominator else None)

    if session.finished_at is None:
        session.finished_at = datetime.utcnow()
    session.total_rules = total
    session.pass_count = counts["pass"]
    session.fail_count = counts["fail"]
    session.na_count = counts["na"]
    session.error_count = counts["error"]
    session.mdm_count = counts["mdm"]
    session.exempt_count = counts["exempt"]
    session.not_assessed_count = counts["not_assessed"]
    session.degraded_reason = degraded
    session.score_pct = score
    db.commit()

    summary = {
        "total": total, "assessed": assessed,
        "pass": counts["pass"], "fail": counts["fail"], "na": counts["na"],
        "error": counts["error"], "not_assessed": counts["not_assessed"],
        "score": score, "degraded_reason": degraded,
    }
    audit.log_action(db, audit.SCAN_COMPLETE, f"session:{session_id}", summary)
    if degraded:
        audit.log_action(db, audit.SCAN_DEGRADED, f"session:{session_id}",
                         {"reason": degraded, "detail": degraded_detail,
                          "not_assessed": counts["not_assessed"]})
    return summary


async def execute_scan_session(session_id: int, rules: Optional[list[str]] = None):
    """Background task: run all scans and stream results to SSE queue."""
    db = SessionLocal()
    queue = asyncio.Queue()
    _active_sessions[session_id] = queue
    counts = {"pass": 0, "fail": 0, "na": 0, "error": 0,
              "mdm": 0, "exempt": 0, "not_assessed": 0}
    degraded: Optional[str] = None
    degraded_detail = ""
    # Defined before the try so the finally-block reconciliation can always see
    # them, even if the failure happened before the scan target was built.
    pending: set = set()
    manifest_map: dict = {}

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

        counts["exempt"] = len(exempt_rules & (set(scan_rules) | set(mdm_rules)))
        counts["mdm"] = len([r for r in mdm_rules if r not in exempt_rules])

        scan_target = [r for r in scan_rules if r not in exempt_rules]
        # `pending` is the ledger: a rule leaves it only when its row is durable.
        # Counters are derived from what was actually persisted, never from what
        # we hoped the runner would return.
        pending = set(scan_target)

        if not scan_target:
            # Never hand an empty list to the runner: scan_batch_stream omits the
            # "rules" key when it is falsy and the runner then scans everything.
            pass
        else:
            cap = await probe_runner()
            if not cap.available:
                degraded, degraded_detail = cap.reason or "runner_unavailable", cap.detail
                logger.error("session %d: not scanning — %s", session_id, cap.detail)
            else:
                if cap.stale_manifest:
                    logger.warning("session %d: %s", session_id, cap.detail)
                try:
                    async for res in scan_batch_stream(scan_target):
                        rule_name = res.get("rule", "")
                        if rule_name not in pending:
                            logger.warning(
                                "session %d: ignoring unexpected/duplicate result for %r",
                                session_id, rule_name)
                            continue
                        status = res.get("status", "ERROR")
                        rule_meta = manifest_map.get(rule_name, {})

                        db.add(ScanResult(
                            session_id=session_id,
                            scanned_at=datetime.utcnow(),
                            rule=rule_name,
                            category=rule_meta.get("category", ""),
                            status=status,
                            result_value=res.get("result"),
                            expected_value=res.get("expected"),
                            message=res.get("message"),
                            raw_output=res.get("stderr"),
                            exit_code=res.get("exit_code"),
                            duration_ms=res.get("duration_ms"),
                        ))
                        db.commit()
                        # Only now is the row durable — a failed commit must leave
                        # the rule in `pending` so reconciliation records it.
                        pending.discard(rule_name)
                        _bump(counts, status, session_id)
                        await queue.put({"type": "result", **res, "session_id": session_id})
                except RunnerError as e:
                    degraded, degraded_detail = "stream_failed", str(e)
                    logger.error("session %d: scan stream failed: %s", session_id, e)

                if degraded is None and pending:
                    degraded = "incomplete_stream"
                    degraded_detail = (
                        f"Runner returned {len(scan_target) - len(pending)} of "
                        f"{len(scan_target)} requested results")
                    logger.error("session %d: %s", session_id, degraded_detail)

    except Exception as e:
        logger.error("Scan session %d error: %s", session_id, e)
        degraded = degraded or "internal_error"
        degraded_detail = degraded_detail or str(e)
        # Not "error": stream.py terminates the SSE feed on an error event, which
        # would hide the completion event that follows.
        await queue.put({"type": "warning", "session_id": session_id, "message": str(e)})
    finally:
        # Reconciliation lives here, not in the try-block, so a mid-stream commit
        # failure cannot skip it — every requested rule ends up with a row.
        try:
            _reconcile_pending(db, session_id, pending, manifest_map,
                               counts, degraded_detail)
        except Exception:
            logger.exception("session %d: reconciliation failed", session_id)

        summary: dict = {}
        for attempt in (1, 2):
            try:
                summary = _finalise_session(db, session_id, counts,
                                            degraded, degraded_detail)
                break
            except Exception:
                logger.exception("session %d: finalisation attempt %d failed",
                                 session_id, attempt)
                if attempt == 1:
                    # One bounded retry — a transient SQLite lock (the root runner
                    # writes audit rows to the same file) is the realistic cause.
                    await asyncio.sleep(1.0)

        # Terminal SSE events are sent even if finalisation failed, so a consumer
        # is never left waiting out its timeout.
        try:
            if degraded:
                await queue.put({"type": "degraded", "session_id": session_id,
                                 "reason": degraded, "message": degraded_detail})
            await queue.put({"type": "complete", "session_id": session_id,
                             "score_pct": summary.get("score"),
                             "pass": counts["pass"], "fail": counts["fail"],
                             "na": counts["na"], "error": counts["error"],
                             "not_assessed": counts["not_assessed"],
                             "assessed": summary.get("assessed", 0),
                             "degraded_reason": degraded,
                             "total": summary.get("total", 0)})
        except Exception:
            logger.exception("session %d: completion events failed", session_id)

        db.close()
        try:
            await asyncio.sleep(30)  # keep queue alive for late SSE consumers
        finally:
            # Runs even on task cancellation, so no stale registry entry survives.
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


# Declared before /api/scans/{session_id} so "active" is not matched as an int id.
@router.get("/api/scans/active")
def get_active_scan(db: Session = Depends(get_db)):
    """Report the scan session currently running, so the UI can restore its
    progress state after a page change or reload."""
    candidates = (
        db.query(ScanSession)
        .filter(
            ScanSession.finished_at.is_(None),
            ScanSession.triggered_by.notin_(VERIFICATION_TRIGGERS),
        )
        .order_by(ScanSession.started_at.desc())
        .limit(5)
        .all()
    )
    for s in candidates:
        # _active_sessions is authoritative for scans executing in this process.
        # The freshness window covers the gap between POST /api/scans committing
        # the row and the background task registering its queue. Sessions left
        # unfinished by a crash or restart are reported inactive but never altered.
        recently_started = (
            s.started_at is not None
            and datetime.utcnow() - s.started_at < timedelta(minutes=2)
        )
        if s.id in _active_sessions or recently_started:
            return {
                "active": True,
                "session_id": s.id,
                "started_at": s.started_at.isoformat() if s.started_at else None,
                "triggered_by": s.triggered_by,
            }
    return {"active": False, "session_id": None}


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
        "not_assessed_count": session.not_assessed_count or 0,
        "degraded_reason": session.degraded_reason,
        "assessed": _assessed(session),
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


async def scan_and_persist_single_rule(
    rule_name: str,
    db: Session,
    triggered_by: str = "single_rule",
) -> dict:
    """
    Run a single-rule scan via the runner and persist the result as a
    one-row ScanSession + ScanResult. Returns the raw runner response.

    Used by the /rules/{rule}/scan endpoint and by background tasks
    (e.g. after an exemption is revoked) that need the rule's status to
    refresh without a full scan.
    """
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

    session = ScanSession(
        started_at=datetime.utcnow(),
        finished_at=datetime.utcnow(),
        triggered_by=triggered_by,
        filter_json=json.dumps({"rule": rule_name}),
        total_rules=1,
        pass_count=1 if res.get("status") == "PASS" else 0,
        fail_count=1 if res.get("status") == "FAIL" else 0,
        na_count=1 if res.get("status") == "NOT_APPLICABLE" else 0,
        error_count=1 if res.get("status") == "ERROR" else 0,
        # FAIL and ERROR are the non-compliant outcomes (see models.py score rule).
        score_pct=(0.0 if res.get("status") in ("FAIL", "ERROR") else 100.0),
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
        raw_output=res.get("stderr"),
        exit_code=res.get("exit_code"),
        duration_ms=res.get("duration_ms"),
    )
    db.add(scan_result)
    db.commit()

    return res


async def rescan_rule_background(rule_name: str) -> None:
    """Background-task wrapper: open a fresh DB session and rescan one rule."""
    db = SessionLocal()
    try:
        await scan_and_persist_single_rule(rule_name, db, triggered_by="post_exemption")
    except (HTTPException, RunnerError):
        # Rule not found or runner down — swallow; the audit log already
        # reflects the exemption change. RunnerError must be caught here too, or
        # a missing runner becomes an unhandled background-task exception.
        pass
    finally:
        db.close()


@router.post("/api/rules/{rule_name}/scan")
async def scan_single_rule(
    rule_name: str,
    db: Session = Depends(get_db),
):
    return await scan_and_persist_single_rule(rule_name, db)
