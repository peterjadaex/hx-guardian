"""
SSE streaming endpoints.
GET /api/stream/scan/{session_id}  → rule-by-rule scan results
GET /api/stream/logs               → live system log lines
GET /api/stream/device             → device state change events
GET /api/stream/audit-log          → tail of audit_log table
GET /api/stream/shell-log          → tail of shell_exec_log table
GET /api/stream/biometric-log      → tail of biometric_events table
"""
import asyncio
import json
import logging
import subprocess
from datetime import datetime
from typing import AsyncGenerator, Callable, Optional

from fastapi import APIRouter, HTTPException, Query
from fastapi.responses import StreamingResponse
from sqlalchemy import func
from sqlalchemy.orm import Session

from core.database import SessionLocal
from core.models import AuditLog, BiometricEvent, ShellExecLog
from routers.audit_log import _apply_filters as _apply_audit_filters, _row_dict as _audit_row
from routers.biometric_log import _apply_filters as _apply_bio_filters, _row_dict as _bio_row
from routers.shell_log import _apply_filters as _apply_shell_filters, _row_dict as _shell_row

logger = logging.getLogger(__name__)
router = APIRouter(prefix="/api/stream", tags=["stream"])

# Shared queue map (populated by scans.py)
from routers.scans import _active_sessions


async def _sse_generator(queue: asyncio.Queue, timeout: float = 300.0) -> AsyncGenerator[str, None]:
    """Convert an asyncio.Queue into SSE text/event-stream chunks."""
    deadline = asyncio.get_event_loop().time() + timeout
    while True:
        remaining = deadline - asyncio.get_event_loop().time()
        if remaining <= 0:
            yield "event: timeout\ndata: {}\n\n"
            break
        try:
            msg = await asyncio.wait_for(queue.get(), timeout=min(remaining, 30.0))
            event_type = msg.pop("type", "message")
            yield f"event: {event_type}\ndata: {json.dumps(msg)}\n\n"
            if event_type in ("complete", "error", "timeout"):
                break
        except asyncio.TimeoutError:
            yield ": heartbeat\n\n"  # SSE comment keeps connection alive


@router.get("/scan/{session_id}")
async def stream_scan(
    session_id: int,
):
    """Stream rule results as a scan session runs."""
    # Wait up to 5s for the session to start
    for _ in range(10):
        if session_id in _active_sessions:
            break
        await asyncio.sleep(0.5)

    if session_id not in _active_sessions:
        raise HTTPException(status_code=404, detail="Scan session not found or already finished")

    queue = _active_sessions[session_id]
    # Tee the queue so multiple SSE consumers can read it
    tee_queue: asyncio.Queue = asyncio.Queue()

    async def forwarder():
        while True:
            item = await queue.get()
            await tee_queue.put(item)
            await queue.put(item)  # put back for other consumers
            if item.get("type") in ("complete", "error"):
                await tee_queue.put(item)
                break

    asyncio.create_task(forwarder())

    return StreamingResponse(
        _sse_generator(tee_queue, timeout=600.0),
        media_type="text/event-stream",
        headers={
            "Cache-Control": "no-cache",
            "X-Accel-Buffering": "no",
            "Connection": "keep-alive",
        },
    )


async def _log_line_generator() -> AsyncGenerator[str, None]:
    """Stream lines from 'log stream' command."""
    proc = await asyncio.create_subprocess_exec(
        "/usr/bin/log", "stream", "--style", "compact",
        "--level", "error",
        stdout=asyncio.subprocess.PIPE,
        stderr=asyncio.subprocess.DEVNULL,
    )
    try:
        while True:
            line = await asyncio.wait_for(proc.stdout.readline(), timeout=60.0)
            if not line:
                break
            text = line.decode("utf-8", errors="replace").strip()
            if text:
                data = {"ts": datetime.utcnow().isoformat(), "message": text}
                yield f"event: log_line\ndata: {json.dumps(data)}\n\n"
    except asyncio.TimeoutError:
        yield ": heartbeat\n\n"
    except asyncio.CancelledError:
        pass
    finally:
        try:
            proc.terminate()
        except Exception:
            pass


@router.get("/logs")
async def stream_logs():
    """Stream live system log lines via SSE."""
    return StreamingResponse(
        _log_line_generator(),
        media_type="text/event-stream",
        headers={
            "Cache-Control": "no-cache",
            "X-Accel-Buffering": "no",
            "Connection": "keep-alive",
        },
    )


_last_device_state: dict = {}


async def _device_stream_generator() -> AsyncGenerator[str, None]:
    """Poll device status every 30s and emit changes."""
    from routers.device import collect_device_status
    global _last_device_state
    while True:
        try:
            status = await collect_device_status()
            if status != _last_device_state:
                _last_device_state = status
                yield f"event: device_update\ndata: {json.dumps(status)}\n\n"
            else:
                yield ": heartbeat\n\n"
        except Exception as e:
            yield f"event: error\ndata: {json.dumps({'message': str(e)})}\n\n"
        await asyncio.sleep(30)


@router.get("/device")
async def stream_device():
    """Stream device state changes every 30s."""
    return StreamingResponse(
        _device_stream_generator(),
        media_type="text/event-stream",
        headers={
            "Cache-Control": "no-cache",
            "X-Accel-Buffering": "no",
            "Connection": "keep-alive",
        },
    )


# ─── Table tailer (DB cursor-based SSE) ───────────────────────────────────────

_TAIL_POLL_INTERVAL = 2.0
_TAIL_BATCH_CAP = 200
_TAIL_IDLE_HEARTBEAT = 15.0
_SSE_HEADERS = {
    "Cache-Control": "no-cache",
    "X-Accel-Buffering": "no",
    "Connection": "keep-alive",
}


def _fetch_since(session_factory, model, apply_filters, row_dict, since_id, filter_args):
    """Run one fresh query for rows with id > since_id. Returns (rows, new_cursor)."""
    db: Session = session_factory()
    try:
        q = apply_filters(db.query(model), *filter_args)
        q = q.filter(model.id > since_id).order_by(model.id.asc()).limit(_TAIL_BATCH_CAP)
        rows = q.all()
        return [row_dict(r) for r in rows], (rows[-1].id if rows else since_id)
    finally:
        db.close()


def _current_max_id(session_factory, model) -> int:
    db: Session = session_factory()
    try:
        return db.query(func.coalesce(func.max(model.id), 0)).scalar() or 0
    finally:
        db.close()


async def _tail_table_generator(
    model,
    apply_filters: Callable,
    row_dict: Callable,
    filter_args: tuple,
) -> AsyncGenerator[str, None]:
    """Poll a table for new rows (id > cursor) and stream them as SSE `row` events."""
    loop = asyncio.get_event_loop()
    cursor = await loop.run_in_executor(None, _current_max_id, SessionLocal, model)
    yield f"event: ready\ndata: {json.dumps({'since_id': cursor})}\n\n"

    idle_elapsed = 0.0
    try:
        while True:
            await asyncio.sleep(_TAIL_POLL_INTERVAL)
            try:
                rows, new_cursor = await loop.run_in_executor(
                    None, _fetch_since, SessionLocal, model, apply_filters, row_dict, cursor, filter_args,
                )
            except Exception as e:
                logger.exception("tail query failed for %s", model.__name__)
                yield f"event: error\ndata: {json.dumps({'message': str(e)})}\n\n"
                await asyncio.sleep(5.0)
                continue

            if rows:
                for r in rows:
                    yield f"event: row\ndata: {json.dumps(r, default=str)}\n\n"
                cursor = new_cursor
                idle_elapsed = 0.0
            else:
                idle_elapsed += _TAIL_POLL_INTERVAL
                if idle_elapsed >= _TAIL_IDLE_HEARTBEAT:
                    yield ": heartbeat\n\n"
                    idle_elapsed = 0.0
    except asyncio.CancelledError:
        pass


@router.get("/audit-log")
async def stream_audit_log(
    action: Optional[str] = Query(None),
):
    """Stream new audit_log rows as they land."""
    # audit _apply_filters signature: (q, action, from_date, to_date)
    filter_args = (action, None, None)
    return StreamingResponse(
        _tail_table_generator(AuditLog, _apply_audit_filters, _audit_row, filter_args),
        media_type="text/event-stream",
        headers=_SSE_HEADERS,
    )


@router.get("/shell-log")
async def stream_shell_log(
    source: Optional[str] = Query(None, description="'log_stream' | 'history'"),
    user: Optional[str] = Query(None),
    pid: Optional[int] = Query(None),
    process_path: Optional[str] = Query(None),
    q: Optional[str] = Query(None),
):
    """Stream new shell_exec_log rows as they land."""
    # shell _apply_filters signature: (q, source, user, pid, process_path, q_text, from_date, to_date)
    filter_args = (source, user, pid, process_path, q, None, None)
    return StreamingResponse(
        _tail_table_generator(ShellExecLog, _apply_shell_filters, _shell_row, filter_args),
        media_type="text/event-stream",
        headers=_SSE_HEADERS,
    )


@router.get("/biometric-log")
async def stream_biometric_log(
    event_class: Optional[str] = Query(None),
    user: Optional[str] = Query(None),
    requesting_process: Optional[str] = Query(None),
    q: Optional[str] = Query(None),
    include_teardown: bool = Query(False),
):
    """Stream new biometric_events rows as they land."""
    # bio _apply_filters signature: (q, event_class, user, requesting_process, q_text, from_date, to_date)
    filter_args = (event_class, user, requesting_process, q, None, None)

    # Match the REST endpoint's default: hide TEARDOWN noise unless caller opts in or filters for it
    if not include_teardown and not event_class:
        base_apply = _apply_bio_filters

        def apply_with_teardown_filter(query, *args):
            query = base_apply(query, *args)
            return query.filter(BiometricEvent.event_class != "TEARDOWN")

        apply_fn = apply_with_teardown_filter
    else:
        apply_fn = _apply_bio_filters

    return StreamingResponse(
        _tail_table_generator(BiometricEvent, apply_fn, _bio_row, filter_args),
        media_type="text/event-stream",
        headers=_SSE_HEADERS,
    )
