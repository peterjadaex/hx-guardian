"""
Audit log router — read-only access to the audit trail.
GET /api/audit-log  → paginated audit entries
"""
import json
from typing import Optional

from fastapi import APIRouter, Depends, Query
from fastapi.responses import Response
from sqlalchemy.orm import Session

from core.auth import verify_token
from core.database import get_db
from core.models import AuditLog

router = APIRouter(prefix="/api/audit-log", tags=["audit"])


@router.get("")
def list_audit_log(
    limit: int = Query(100, ge=1, le=500),
    offset: int = Query(0, ge=0),
    action: Optional[str] = Query(None),
    db: Session = Depends(get_db),
    _: str = Depends(verify_token),
):
    q = db.query(AuditLog)
    if action:
        q = q.filter(AuditLog.action == action)
    total = q.count()
    entries = q.order_by(AuditLog.ts.desc()).offset(offset).limit(limit).all()
    return {
        "total": total,
        "offset": offset,
        "entries": [
            {
                "id": e.id,
                "ts": e.ts.isoformat() if e.ts else None,
                "action": e.action,
                "target": e.target,
                "detail": json.loads(e.detail_json) if e.detail_json else None,
                "operator": e.operator,
                "source_ip": e.source_ip,
            }
            for e in entries
        ],
    }


@router.get("/export/csv")
def export_audit_csv(
    db: Session = Depends(get_db),
    _: str = Depends(verify_token),
):
    """Export entire audit log as CSV."""
    entries = db.query(AuditLog).order_by(AuditLog.ts.asc()).all()
    lines = ["id,timestamp,action,target,detail,operator,source_ip"]
    for e in entries:
        detail = e.detail_json.replace(",", ";") if e.detail_json else ""
        lines.append(
            f'{e.id},{e.ts.isoformat() if e.ts else ""},'
            f'{e.action},{e.target or ""},'
            f'"{detail}",'
            f'{e.operator or ""},{e.source_ip or ""}'
        )
    csv_content = "\n".join(lines)
    return Response(
        content=csv_content,
        media_type="text/csv",
        headers={"Content-Disposition": "attachment; filename=hxguardian_audit_log.csv"},
    )
