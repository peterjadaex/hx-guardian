"""
Shell-exec log router — read-only access to device-action captures.

GET /api/shell-log                → paginated rows from shell_exec_log
GET /api/shell-log/export/jsonl   → all matching rows as NDJSON for audit export
"""
import json
from datetime import datetime
from typing import Optional

from fastapi import APIRouter, Depends, Query
from fastapi.responses import Response
from sqlalchemy import or_
from sqlalchemy.orm import Session

from core.database import get_db
from core.models import ShellExecLog

router = APIRouter(prefix="/api/shell-log", tags=["audit"])


def _parse_date(s: Optional[str]) -> Optional[datetime]:
    if not s:
        return None
    try:
        # Accept both "2026-04-23" and full ISO 8601
        return datetime.fromisoformat(s.replace("Z", "+00:00"))
    except Exception:
        return None


def _apply_filters(q, source, user, pid, process_path, q_text, from_date, to_date):
    if source:
        q = q.filter(ShellExecLog.source == source)
    if user:
        q = q.filter(ShellExecLog.user == user)
    if pid is not None:
        q = q.filter(ShellExecLog.pid == pid)
    if process_path:
        q = q.filter(ShellExecLog.process_path.like(f"%{process_path}%"))
    if q_text:
        like = f"%{q_text}%"
        q = q.filter(or_(
            ShellExecLog.command.like(like),
            ShellExecLog.event_message.like(like),
        ))
    fd = _parse_date(from_date)
    td = _parse_date(to_date)
    if fd:
        q = q.filter(ShellExecLog.ts >= fd)
    if td:
        q = q.filter(ShellExecLog.ts <= td)
    return q


def _row_dict(e: ShellExecLog) -> dict:
    return {
        "id": e.id,
        "ts": e.ts.isoformat() if e.ts else None,
        "source": e.source,
        "pid": e.pid,
        "ppid": e.ppid,
        "user": e.user,
        "process_path": e.process_path,
        "command": e.command,
        "event_message": e.event_message,
        "subsystem": e.subsystem,
    }


@router.get("")
def list_shell_log(
    limit: int = Query(100, ge=1, le=500),
    offset: int = Query(0, ge=0),
    source: Optional[str] = Query(None, description="'log_stream' | 'history'"),
    user: Optional[str] = Query(None),
    pid: Optional[int] = Query(None),
    process_path: Optional[str] = Query(None),
    q: Optional[str] = Query(None, description="Free-text LIKE match over command + event_message"),
    from_date: Optional[str] = Query(None, alias="from"),
    to_date: Optional[str] = Query(None, alias="to"),
    db: Session = Depends(get_db),
):
    query = db.query(ShellExecLog)
    query = _apply_filters(query, source, user, pid, process_path, q, from_date, to_date)
    total = query.count()
    entries = query.order_by(ShellExecLog.ts.desc()).offset(offset).limit(limit).all()
    return {
        "total": total,
        "offset": offset,
        "entries": [_row_dict(e) for e in entries],
    }


@router.get("/export/jsonl")
def export_shell_jsonl(
    source: Optional[str] = Query(None),
    user: Optional[str] = Query(None),
    pid: Optional[int] = Query(None),
    process_path: Optional[str] = Query(None),
    q: Optional[str] = Query(None),
    from_date: Optional[str] = Query(None, alias="from"),
    to_date: Optional[str] = Query(None, alias="to"),
    db: Session = Depends(get_db),
):
    query = db.query(ShellExecLog)
    query = _apply_filters(query, source, user, pid, process_path, q, from_date, to_date)
    entries = query.order_by(ShellExecLog.ts.asc()).all()
    body = "\n".join(json.dumps(_row_dict(e)) for e in entries)
    return Response(
        content=body,
        media_type="application/x-ndjson",
        headers={"Content-Disposition": "attachment; filename=hxguardian_shell_log.jsonl"},
    )
