"""
Biometric events router — read-only access to Touch ID / LocalAuthentication
events captured by the shell_watcher.

GET /api/biometric-log                → paginated rows from biometric_events
GET /api/biometric-log/export/jsonl   → filtered NDJSON export for audit handoff
"""
import json
from datetime import datetime
from typing import Optional

from fastapi import APIRouter, Depends, Query
from fastapi.responses import Response
from sqlalchemy import or_
from sqlalchemy.orm import Session

from core.database import get_db
from core.models import BiometricEvent

router = APIRouter(prefix="/api/biometric-log", tags=["audit"])


def _parse_date(s: Optional[str]) -> Optional[datetime]:
    if not s:
        return None
    try:
        return datetime.fromisoformat(s.replace("Z", "+00:00"))
    except Exception:
        return None


def _apply_filters(q, event_class, user, requesting_process, q_text, from_date, to_date):
    if event_class:
        q = q.filter(BiometricEvent.event_class == event_class)
    if user:
        q = q.filter(or_(BiometricEvent.user == user, BiometricEvent.console_user == user))
    if requesting_process:
        q = q.filter(BiometricEvent.requesting_process.like(f"%{requesting_process}%"))
    if q_text:
        like = f"%{q_text}%"
        q = q.filter(or_(
            BiometricEvent.event_message.like(like),
            BiometricEvent.subsystem.like(like),
            BiometricEvent.category.like(like),
        ))
    fd = _parse_date(from_date)
    td = _parse_date(to_date)
    if fd:
        q = q.filter(BiometricEvent.ts >= fd)
    if td:
        q = q.filter(BiometricEvent.ts <= td)
    return q


def _row_dict(e: BiometricEvent) -> dict:
    return {
        "id": e.id,
        "ts": e.ts.isoformat() if e.ts else None,
        "event_class": e.event_class,
        "subsystem": e.subsystem,
        "category": e.category,
        "requesting_process": e.requesting_process,
        "requesting_pid": e.requesting_pid,
        "user_uid": e.user_uid,
        "user": e.user,
        "console_user": e.console_user,
        "event_message": e.event_message,
    }


@router.get("")
def list_biometric_log(
    limit: int = Query(100, ge=1, le=500),
    offset: int = Query(0, ge=0),
    event_class: Optional[str] = Query(None, description="REQUEST|SUCCESS|FAILURE|CANCELLED|TEARDOWN|OTHER"),
    user: Optional[str] = Query(None),
    requesting_process: Optional[str] = Query(None),
    q: Optional[str] = Query(None, description="LIKE-match over event_message + subsystem + category"),
    include_teardown: bool = Query(False, description="Default hides TEARDOWN noise events"),
    from_date: Optional[str] = Query(None, alias="from"),
    to_date: Optional[str] = Query(None, alias="to"),
    db: Session = Depends(get_db),
):
    query = db.query(BiometricEvent)
    query = _apply_filters(query, event_class, user, requesting_process, q, from_date, to_date)
    if not include_teardown and not event_class:
        query = query.filter(BiometricEvent.event_class != "TEARDOWN")
    total = query.count()
    entries = query.order_by(BiometricEvent.ts.desc()).offset(offset).limit(limit).all()
    return {
        "total": total,
        "offset": offset,
        "entries": [_row_dict(e) for e in entries],
    }


@router.get("/export/jsonl")
def export_biometric_jsonl(
    event_class: Optional[str] = Query(None),
    user: Optional[str] = Query(None),
    requesting_process: Optional[str] = Query(None),
    q: Optional[str] = Query(None),
    include_teardown: bool = Query(False),
    from_date: Optional[str] = Query(None, alias="from"),
    to_date: Optional[str] = Query(None, alias="to"),
    db: Session = Depends(get_db),
):
    query = db.query(BiometricEvent)
    query = _apply_filters(query, event_class, user, requesting_process, q, from_date, to_date)
    if not include_teardown and not event_class:
        query = query.filter(BiometricEvent.event_class != "TEARDOWN")
    entries = query.order_by(BiometricEvent.ts.asc()).all()
    body = "\n".join(json.dumps(_row_dict(e)) for e in entries)
    return Response(
        content=body,
        media_type="application/x-ndjson",
        headers={"Content-Disposition": "attachment; filename=hxguardian_biometric_log.jsonl"},
    )
