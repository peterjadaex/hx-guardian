"""
Script executor — runs scan/fix zsh scripts as root, parses JSON output.
Used exclusively by hxg_runner.py (which already runs as root).
"""
import json
import subprocess
import time
import os
import logging
from typing import Tuple

logger = logging.getLogger(__name__)

SCRIPT_TIMEOUT = 60  # seconds per script


def run_script(script_path: str) -> Tuple[dict, int, int]:
    """
    Execute a scan or fix script.
    Returns (parsed_json_output, exit_code, duration_ms).
    """
    if not os.path.isfile(script_path):
        return {"status": "ERROR", "message": f"Script not found: {script_path}"}, 3, 0

    start = time.monotonic()
    try:
        result = subprocess.run(
            ["/bin/zsh", "--no-rcs", script_path],
            capture_output=True,
            text=True,
            timeout=SCRIPT_TIMEOUT,
        )
        duration_ms = int((time.monotonic() - start) * 1000)
        exit_code = result.returncode

        stdout = result.stdout.strip()
        if stdout:
            try:
                data = json.loads(stdout)
            except json.JSONDecodeError:
                data = {"status": "ERROR", "message": f"Non-JSON output: {stdout[:200]}"}
        else:
            stderr = result.stderr.strip()
            data = {"status": "ERROR", "message": f"No output. stderr: {stderr[:200]}"}

        # Normalise exit code to status if script didn't set it
        if "status" not in data:
            status_map = {0: "PASS", 1: "FAIL", 2: "NOT_APPLICABLE", 3: "ERROR"}
            data["status"] = status_map.get(exit_code, "ERROR")

        return data, exit_code, duration_ms

    except subprocess.TimeoutExpired:
        duration_ms = int((time.monotonic() - start) * 1000)
        logger.warning("Script timed out: %s", script_path)
        return {"status": "ERROR", "message": "Script execution timed out"}, 3, duration_ms
    except Exception as exc:
        duration_ms = int((time.monotonic() - start) * 1000)
        logger.error("Script execution error %s: %s", script_path, exc)
        return {"status": "ERROR", "message": str(exc)}, 3, duration_ms
