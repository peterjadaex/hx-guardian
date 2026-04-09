"""
Schedule router — manage automated scan schedules.
GET    /api/schedule       → list schedules
POST   /api/schedule       → create schedule
PUT    /api/schedule/{id}  → update schedule
DELETE /api/schedule/{id}  → delete schedule
"""
import json
from datetime import datetime
from typing import Optional

from fastapi import APIRouter, Depends, HTTPException
from pydantic import BaseModel
from sqlalchemy.orm import Session

import core.audit as audit
from core.auth import verify_token
from core.database import get_db
from core.models import Schedule

router = APIRouter(prefix="/api/schedule", tags=["schedule"])


class ScheduleCreate(BaseModel):
    name: str
    cron_expr: str   # e.g. "0 6 * * *"
    filter: Optional[dict] = None
    enabled: bool = True


class ScheduleUpdate(BaseModel):
    name: Optional[str] = None
    cron_expr: Optional[str] = None
    filter: Optional[dict] = None
    enabled: Optional[bool] = None


def _validate_cron(expr: str) -> bool:
    parts = expr.strip().split()
    return len(parts) == 5


def _serialize(s: Schedule) -> dict:
    return {
        "id": s.id,
        "name": s.name,
        "cron_expr": s.cron_expr,
        "filter": json.loads(s.filter_json) if s.filter_json else None,
        "enabled": s.enabled,
        "last_run": s.last_run.isoformat() if s.last_run else None,
        "next_run": s.next_run.isoformat() if s.next_run else None,
        "created_at": s.created_at.isoformat() if s.created_at else None,
    }


@router.get("")
def list_schedules(
    db: Session = Depends(get_db),
    _: str = Depends(verify_token),
):
    schedules = db.query(Schedule).order_by(Schedule.created_at.desc()).all()
    return {"schedules": [_serialize(s) for s in schedules]}


@router.post("")
def create_schedule(
    body: ScheduleCreate,
    db: Session = Depends(get_db),
    _: str = Depends(verify_token),
):
    if not _validate_cron(body.cron_expr):
        raise HTTPException(status_code=422, detail="Invalid cron expression — must have 5 fields")

    sched = Schedule(
        name=body.name,
        cron_expr=body.cron_expr,
        filter_json=json.dumps(body.filter) if body.filter else None,
        enabled=body.enabled,
        created_at=datetime.utcnow(),
    )
    db.add(sched)
    db.commit()
    db.refresh(sched)

    from core.scheduler import reload_schedule
    reload_schedule(sched.id)

    audit.log_action(db, audit.SCHEDULE_CREATED, f"schedule:{sched.id}", {"name": body.name, "cron": body.cron_expr})
    return _serialize(sched)


@router.put("/{schedule_id}")
def update_schedule(
    schedule_id: int,
    body: ScheduleUpdate,
    db: Session = Depends(get_db),
    _: str = Depends(verify_token),
):
    sched = db.query(Schedule).filter(Schedule.id == schedule_id).first()
    if not sched:
        raise HTTPException(status_code=404, detail="Schedule not found")

    if body.name is not None:
        sched.name = body.name
    if body.cron_expr is not None:
        if not _validate_cron(body.cron_expr):
            raise HTTPException(status_code=422, detail="Invalid cron expression")
        sched.cron_expr = body.cron_expr
    if body.filter is not None:
        sched.filter_json = json.dumps(body.filter)
    if body.enabled is not None:
        sched.enabled = body.enabled

    db.commit()

    from core.scheduler import reload_schedule
    reload_schedule(schedule_id)

    return _serialize(sched)


@router.delete("/{schedule_id}")
def delete_schedule(
    schedule_id: int,
    db: Session = Depends(get_db),
    _: str = Depends(verify_token),
):
    sched = db.query(Schedule).filter(Schedule.id == schedule_id).first()
    if not sched:
        raise HTTPException(status_code=404, detail="Schedule not found")

    from core.scheduler import remove_schedule
    remove_schedule(schedule_id)

    db.delete(sched)
    db.commit()

    audit.log_action(db, audit.SCHEDULE_DELETED, f"schedule:{schedule_id}")
    return {"deleted": True, "id": schedule_id}


@router.post("/{schedule_id}/run")
async def run_schedule_now(
    schedule_id: int,
    db: Session = Depends(get_db),
    _: str = Depends(verify_token),
):
    """Trigger a scheduled scan immediately."""
    sched = db.query(Schedule).filter(Schedule.id == schedule_id).first()
    if not sched:
        raise HTTPException(status_code=404, detail="Schedule not found")

    from core.scheduler import _run_scheduled_scan
    import asyncio
    asyncio.create_task(_run_scheduled_scan(schedule_id, sched.filter_json))
    return {"triggered": True, "schedule_id": schedule_id}
