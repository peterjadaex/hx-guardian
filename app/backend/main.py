"""
HX-Guardian Dashboard — FastAPI backend entry point.
Runs on 127.0.0.1:8000 (localhost only).

Start: python3 -m uvicorn main:app --host 127.0.0.1 --port 8000
"""
import logging
import os
import sys
from contextlib import asynccontextmanager
from pathlib import Path

from fastapi import FastAPI, Request, Response
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import JSONResponse
from fastapi.staticfiles import StaticFiles

# Ensure backend package root is on path
sys.path.insert(0, str(Path(__file__).parent))

from core.auth import generate_token, get_token
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
    stream,
)

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s [%(name)s] %(levelname)s %(message)s",
)
logger = logging.getLogger(__name__)


@asynccontextmanager
async def lifespan(app: FastAPI):
    # Startup
    logger.info("Starting HX-Guardian dashboard...")
    init_db()
    generate_token()
    start_scheduler()
    yield
    # Shutdown
    stop_scheduler()
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
app.include_router(stream.router)


@app.get("/api/health")
async def health():
    """Health check — also verifies runner connection."""
    from core.runner_client import ping
    runner_ok = await ping()
    return {
        "status": "ok",
        "runner_connected": runner_ok,
        "version": "1.0.0",
    }


@app.get("/api/token/verify")
async def verify_session(request: Request):
    """Check if the provided token is valid (used by frontend on load)."""
    token = request.headers.get("Authorization", "").removeprefix("Bearer ").strip()
    return {"valid": token == get_token() and bool(token)}


# Serve React frontend static files
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
