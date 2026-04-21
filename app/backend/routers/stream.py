"""
SSE streaming endpoints.
GET /api/stream/scan/{session_id}  → rule-by-rule scan results
GET /api/stream/logs               → live system log lines
GET /api/stream/device             → device state change events
"""
import asyncio
import json
import logging
import subprocess
from datetime import datetime
from typing import AsyncGenerator

from fastapi import APIRouter, HTTPException
from fastapi.responses import StreamingResponse

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
