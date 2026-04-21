"""
Logs router — system log access.
GET /api/logs/system  → last N lines of /var/log/system.log (?lines, ?filter)
"""
import asyncio
import logging
import os
from typing import Optional

from fastapi import APIRouter, Query

logger = logging.getLogger(__name__)
router = APIRouter(prefix="/api/logs", tags=["logs"])

SYSTEM_LOG = "/var/log/system.log"
INSTALL_LOG = "/var/log/install.log"


@router.get("/system")
async def get_system_log(
    lines: int = Query(200, ge=1, le=2000),
    filter: Optional[str] = Query(None),
    log_file: str = Query("system", pattern="^(system|install)$"),
):
    """Return last N lines of a system log file, optionally filtered."""
    path = SYSTEM_LOG if log_file == "system" else INSTALL_LOG

    if not os.path.exists(path):
        # Fall back to unified log
        return await _get_unified_log(lines, filter)

    try:
        proc = await asyncio.create_subprocess_exec(
            "/usr/bin/tail", "-n", str(lines), path,
            stdout=asyncio.subprocess.PIPE,
            stderr=asyncio.subprocess.DEVNULL,
        )
        stdout, _ = await asyncio.wait_for(proc.communicate(), timeout=10.0)
        all_lines = stdout.decode("utf-8", errors="replace").splitlines()

        if filter:
            fl = filter.lower()
            all_lines = [l for l in all_lines if fl in l.lower()]

        return {"log_file": path, "lines": all_lines, "total": len(all_lines)}
    except Exception as e:
        logger.error("Log read error: %s", e)
        return {"log_file": path, "lines": [], "error": str(e), "total": 0}


async def _get_unified_log(lines: int, filter: Optional[str]) -> dict:
    """Fallback: use 'log show' for unified log."""
    try:
        cmd = ["/usr/bin/log", "show", "--last", "1h",
               "--style", "compact", "--level", "error"]
        proc = await asyncio.create_subprocess_exec(
            *cmd,
            stdout=asyncio.subprocess.PIPE,
            stderr=asyncio.subprocess.DEVNULL,
        )
        stdout, _ = await asyncio.wait_for(proc.communicate(), timeout=15.0)
        all_lines = stdout.decode("utf-8", errors="replace").splitlines()[-lines:]

        if filter:
            fl = filter.lower()
            all_lines = [l for l in all_lines if fl in l.lower()]

        return {"log_file": "unified_log", "lines": all_lines, "total": len(all_lines)}
    except Exception as e:
        return {"log_file": "unified_log", "lines": [], "error": str(e), "total": 0}
