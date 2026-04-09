"""
APScheduler-based background scan scheduler.
Loads enabled schedules from DB on startup and re-fires scans via runner.
"""
import asyncio
import json
import logging
from datetime import datetime

from apscheduler.schedulers.asyncio import AsyncIOScheduler
from apscheduler.triggers.cron import CronTrigger

from core.database import SessionLocal
from core.models import Schedule, ScanSession
import core.audit as audit

logger = logging.getLogger(__name__)

_scheduler = AsyncIOScheduler()


async def _run_scheduled_scan(schedule_id: int, filter_json: str | None = None):
    """Execute a scheduled scan batch via runner_client."""
    from core import runner_client  # import here to avoid circular at module level

    db = SessionLocal()
    try:
        schedule = db.query(Schedule).filter(Schedule.id == schedule_id).first()
        if not schedule or not schedule.enabled:
            return

        logger.info("Running scheduled scan: %s (id=%d)", schedule.name, schedule_id)

        rules = None
        if filter_json:
            f = json.loads(filter_json)
            if f.get("category"):
                from core.manifest import get_rules_by_category
                rules = [r["rule"] for r in get_rules_by_category(f["category"])]
            elif f.get("standard"):
                from core.manifest import get_rules_by_standard
                rules = [r["rule"] for r in get_rules_by_standard(f["standard"])]

        session = ScanSession(
            started_at=datetime.utcnow(),
            triggered_by="scheduled",
            filter_json=filter_json,
        )
        db.add(session)
        db.commit()
        db.refresh(session)

        audit.log_action(db, audit.SCHEDULE_TRIGGERED, f"session:{session.id}",
                         {"schedule_id": schedule_id, "schedule_name": schedule.name})

        # Delegate actual scan to scans router helper
        from routers.scans import execute_scan_session
        asyncio.create_task(execute_scan_session(session.id, rules))

        schedule.last_run = datetime.utcnow()
        db.commit()
    except Exception as exc:
        logger.error("Scheduled scan error: %s", exc)
    finally:
        db.close()


def start_scheduler():
    """Load all enabled schedules from DB and start APScheduler."""
    db = SessionLocal()
    try:
        schedules = db.query(Schedule).filter(Schedule.enabled == True).all()
        for sched in schedules:
            _add_job(sched)
        _scheduler.start()
        logger.info("Scheduler started with %d jobs", len(schedules))
    finally:
        db.close()


def stop_scheduler():
    if _scheduler.running:
        _scheduler.shutdown(wait=False)


def _add_job(schedule: Schedule):
    """Register a schedule with APScheduler."""
    try:
        parts = schedule.cron_expr.split()
        if len(parts) == 5:
            minute, hour, day, month, day_of_week = parts
        else:
            logger.warning("Invalid cron expression: %s", schedule.cron_expr)
            return

        _scheduler.add_job(
            _run_scheduled_scan,
            CronTrigger(
                minute=minute, hour=hour, day=day,
                month=month, day_of_week=day_of_week,
            ),
            args=[schedule.id, schedule.filter_json],
            id=f"schedule_{schedule.id}",
            replace_existing=True,
        )
        logger.info("Scheduled job added: %s (%s)", schedule.name, schedule.cron_expr)
    except Exception as exc:
        logger.error("Failed to add schedule job %d: %s", schedule.id, exc)


def reload_schedule(schedule_id: int):
    """Reload a single schedule from DB (call after create/update)."""
    db = SessionLocal()
    try:
        sched = db.query(Schedule).filter(Schedule.id == schedule_id).first()
        if not sched:
            _scheduler.remove_job(f"schedule_{schedule_id}", jobstore=None)
            return
        if sched.enabled:
            _add_job(sched)
        else:
            try:
                _scheduler.remove_job(f"schedule_{schedule_id}")
            except Exception:
                pass
    finally:
        db.close()


def remove_schedule(schedule_id: int):
    """Remove a schedule from APScheduler."""
    try:
        _scheduler.remove_job(f"schedule_{schedule_id}")
    except Exception:
        pass
