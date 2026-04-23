"""
Audit log router — read-only access to the audit trail.

GET /api/audit-log                  → paginated audit entries
GET /api/audit-log/export/csv       → filtered CSV export
GET /api/audit-log/export/jsonl     → filtered NDJSON export
"""
import csv
import io
import json
from datetime import datetime
from typing import Optional

from fastapi import APIRouter, Depends, Query
from fastapi.responses import Response
from sqlalchemy.orm import Session

from core.database import get_db
from core.models import AuditLog

router = APIRouter(prefix="/api/audit-log", tags=["audit"])


def _parse_date(s: Optional[str]) -> Optional[datetime]:
    if not s:
        return None
    try:
        return datetime.fromisoformat(s.replace("Z", "+00:00"))
    except Exception:
        return None


def _apply_filters(q, action, from_date, to_date):
    if action:
        q = q.filter(AuditLog.action == action)
    fd = _parse_date(from_date)
    td = _parse_date(to_date)
    if fd:
        q = q.filter(AuditLog.ts >= fd)
    if td:
        q = q.filter(AuditLog.ts <= td)
    return q


def _row_dict(e: AuditLog) -> dict:
    return {
        "id": e.id,
        "ts": e.ts.isoformat() if e.ts else None,
        "action": e.action,
        "target": e.target,
        "detail": json.loads(e.detail_json) if e.detail_json else None,
        "operator": e.operator,
        "source_ip": e.source_ip,
    }


@router.get("")
def list_audit_log(
    limit: int = Query(100, ge=1, le=500),
    offset: int = Query(0, ge=0),
    action: Optional[str] = Query(None),
    from_date: Optional[str] = Query(None, alias="from"),
    to_date: Optional[str] = Query(None, alias="to"),
    db: Session = Depends(get_db),
):
    q = _apply_filters(db.query(AuditLog), action, from_date, to_date)
    total = q.count()
    entries = q.order_by(AuditLog.ts.desc()).offset(offset).limit(limit).all()
    return {
        "total": total,
        "offset": offset,
        "entries": [_row_dict(e) for e in entries],
    }


@router.get("/export/csv")
def export_audit_csv(
    action: Optional[str] = Query(None),
    from_date: Optional[str] = Query(None, alias="from"),
    to_date: Optional[str] = Query(None, alias="to"),
    db: Session = Depends(get_db),
):
    """Export audit log as CSV, respecting the same filters as the list endpoint."""
    q = _apply_filters(db.query(AuditLog), action, from_date, to_date)
    entries = q.order_by(AuditLog.ts.asc()).all()

    buf = io.StringIO()
    writer = csv.writer(buf)
    writer.writerow(["id", "timestamp", "action", "target", "detail", "operator", "source_ip"])
    for e in entries:
        writer.writerow([
            e.id,
            e.ts.isoformat() if e.ts else "",
            e.action,
            e.target or "",
            e.detail_json or "",
            e.operator or "",
            e.source_ip or "",
        ])
    return Response(
        content=buf.getvalue(),
        media_type="text/csv",
        headers={"Content-Disposition": "attachment; filename=hxguardian_audit_log.csv"},
    )


@router.get("/export/jsonl")
def export_audit_jsonl(
    action: Optional[str] = Query(None),
    from_date: Optional[str] = Query(None, alias="from"),
    to_date: Optional[str] = Query(None, alias="to"),
    db: Session = Depends(get_db),
):
    """Export audit log as NDJSON for SIEM / machine consumption."""
    q = _apply_filters(db.query(AuditLog), action, from_date, to_date)
    entries = q.order_by(AuditLog.ts.asc()).all()
    body = "\n".join(json.dumps(_row_dict(e)) for e in entries)
    return Response(
        content=body,
        media_type="application/x-ndjson",
        headers={"Content-Disposition": "attachment; filename=hxguardian_audit_log.jsonl"},
    )
