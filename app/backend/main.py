"""
HX-Guardian Dashboard — FastAPI backend entry point.
Runs on 127.0.0.1:8000 (localhost only).

Start: python3 -m uvicorn main:app --host 127.0.0.1 --port 8000
"""
import asyncio
import logging
import os
import sys
import time
from contextlib import asynccontextmanager
from pathlib import Path

from fastapi import FastAPI, Request, Response
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import JSONResponse
from fastapi.staticfiles import StaticFiles

# Ensure backend package root is on path
sys.path.insert(0, str(Path(__file__).parent))

from core.database import init_db
from core.scheduler import start_scheduler, stop_scheduler

from routers import (
    rules,
    scans,
    fixes,
    history,
    exemptions,
    device,
    logs,
    mdm,
    schedule,
    reports,
    audit_log,
    shell_log,
    biometric_log,
    stream,
    settings,
)

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s [%(name)s] %(levelname)s %(message)s",
)
logger = logging.getLogger(__name__)


# Startup readiness state. Lifespan yields immediately so uvicorn starts
# accepting connections; the blocking init_db() runs in a background task.
# Routes can read these to report startup health to the operator.
_ready: "asyncio.Future | None" = None
_startup_error: "str | None" = None
_startup_started_at: "float | None" = None
_startup_finished_at: "float | None" = None


async def _startup_background():
    """Run blocking init off the request-handling loop.

    init_db() is offloaded to a thread (sync sqlite WAL recovery may take
    several seconds on cold boot). start_scheduler() stays on the loop —
    AsyncIOScheduler.start() requires the running asyncio loop.

    On failure we log + record the error but stay alive: the dashboard
    serves /api/health with {ready: false, startup_error: "..."} so the
    cause is diagnosable from the browser without log access.
    """
    global _startup_error, _startup_finished_at
    loop = asyncio.get_running_loop()
    try:
        logger.info("Startup: init_db()")
        await asyncio.wait_for(loop.run_in_executor(None, init_db), timeout=30.0)
        logger.info("Startup: start_scheduler()")
        start_scheduler()
        _ready.set_result(True)
        logger.info("Startup: complete")
    except Exception as exc:
        logger.exception("Startup failed")
        _startup_error = f"{type(exc).__name__}: {exc}"
        if not _ready.done():
            _ready.set_exception(exc)
    finally:
        _startup_finished_at = time.monotonic()


@asynccontextmanager
async def lifespan(app: FastAPI):
    global _ready, _startup_started_at
    logger.info("Starting HX-Guardian dashboard...")
    _ready = asyncio.get_running_loop().create_future()
    _startup_started_at = time.monotonic()
    task = asyncio.create_task(_startup_background())
    yield  # uvicorn starts accepting connections here, immediately
    task.cancel()
    try:
        await asyncio.wait_for(asyncio.to_thread(stop_scheduler), timeout=5.0)
    except Exception:
        pass
    logger.info("HX-Guardian dashboard stopped")


app = FastAPI(
    title="HX-Guardian Security Dashboard",
    description="Airgap device security compliance monitor",
    version="1.0.0",
    lifespan=lifespan,
    docs_url="/api/docs",
    redoc_url=None,
)

# Localhost-only CORS (browser → same origin, so CORS is minimal)
app.add_middleware(
    CORSMiddleware,
    allow_origins=["http://127.0.0.1:8000", "http://localhost:8000"],
    allow_credentials=True,
    allow_methods=["GET", "POST", "PUT", "DELETE", "OPTIONS"],
    allow_headers=["Authorization", "Content-Type", "X-HXG-Token"],
)

# Include all routers
app.include_router(rules.router)
app.include_router(scans.router)
app.include_router(fixes.router)
app.include_router(history.router)
app.include_router(exemptions.router)
app.include_router(device.router)
app.include_router(logs.router)
app.include_router(mdm.router)
app.include_router(schedule.router)
app.include_router(reports.router)
app.include_router(audit_log.router)
app.include_router(shell_log.router)
app.include_router(biometric_log.router)
app.include_router(stream.router)
app.include_router(settings.router)


@app.get("/api/health")
async def health():
    """Trivial liveness — does not depend on DB or runner.

    A liveness check that hits a downstream RPC collapses the dashboard
    when the runner is slow. Runner status is reported separately at
    /api/runner/status; startup state is at /api/internal/startup.
    """
    ready = (
        _ready is not None
        and _ready.done()
        and not _ready.cancelled()
        and _ready.exception() is None
    )
    body = {"status": "ok", "ready": ready, "version": "1.0.0"}
    if _startup_error is not None:
        body["startup_error"] = _startup_error
    return body


@app.get("/api/runner/status")
async def runner_status():
    """Runner liveness — bounded, never wedges the response."""
    from core.runner_client import ping
    try:
        ok = await asyncio.wait_for(ping(), timeout=1.5)
    except asyncio.TimeoutError:
        ok = False
    return {"runner_connected": ok}


@app.get("/api/internal/startup")
async def startup_diag():
    """Operator-visible startup state. Cheap diagnostic without log access."""
    elapsed = None
    if _startup_started_at is not None:
        end = _startup_finished_at if _startup_finished_at is not None else time.monotonic()
        elapsed = round(end - _startup_started_at, 3)
    ready = (
        _ready is not None
        and _ready.done()
        and not _ready.cancelled()
        and _ready.exception() is None
    )
    return {
        "started_at": _startup_started_at,
        "finished_at": _startup_finished_at,
        "elapsed_seconds": elapsed,
        "ready": ready,
        "error": _startup_error,
    }


# Serve React frontend static files
if getattr(sys, 'frozen', False):
    FRONTEND_DIST = Path(sys._MEIPASS) / "frontend" / "dist"
else:
    FRONTEND_DIST = Path(__file__).parent.parent / "frontend" / "dist"
if FRONTEND_DIST.exists():
    app.mount("/assets", StaticFiles(directory=str(FRONTEND_DIST / "assets")), name="assets")

    @app.get("/{full_path:path}", include_in_schema=False)
    async def serve_spa(full_path: str, request: Request):
        """Serve the React SPA — all non-API routes return index.html."""
        if full_path.startswith("api/"):
            return JSONResponse({"detail": "Not found"}, status_code=404)
        index = FRONTEND_DIST / "index.html"
        if index.exists():
            return Response(
                content=index.read_bytes(),
                media_type="text/html",
                headers={"Cache-Control": "no-cache"},
            )
        return JSONResponse({"detail": "Frontend not built yet. Run: cd app/frontend && npm run build"}, status_code=503)
else:
    @app.get("/", include_in_schema=False)
    async def frontend_not_built():
        return JSONResponse({
            "message": "Frontend not built. Run: cd app/frontend && npm install && npm run build",
            "api_docs": "http://127.0.0.1:8000/api/docs",
        })


if __name__ == "__main__":
    import uvicorn
    uvicorn.run(app, host="127.0.0.1", port=8000, log_level="info")
