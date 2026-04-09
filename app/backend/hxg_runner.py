#!/usr/bin/env python3
"""
hxg_runner — Privileged runner daemon (must run as root via LaunchDaemon).

Listens on a Unix domain socket at HXG_SOCKET_PATH.
Accepts newline-delimited JSON requests, executes scan/fix scripts,
streams results back as newline-delimited JSON.

Security model:
- All rule names are validated against manifest allowlist before execution.
- Script paths are resolved from manifest (no user-supplied paths).
- No shell=True, no string interpolation into commands.
"""
import json
import logging
import os
import socket
import sys
import threading
import time
from typing import Optional
from pathlib import Path

# Allow imports from backend package
sys.path.insert(0, str(Path(__file__).parent))

from runner.executor import run_script

HXG_SOCKET_PATH = "/var/run/hxg/runner.sock"
STANDARDS_BASE = Path(__file__).parent.parent.parent / "standards"
MANIFEST_PATH = STANDARDS_BASE / "scripts" / "manifest.json"

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s [runner] %(levelname)s %(message)s",
)
logger = logging.getLogger(__name__)

# ---------------------------------------------------------------------------
# Manifest allowlist
# ---------------------------------------------------------------------------

_manifest: dict = {}
_manifest_lock = threading.Lock()


def load_manifest() -> None:
    global _manifest
    if not MANIFEST_PATH.exists():
        logger.error("Manifest not found at %s", MANIFEST_PATH)
        return
    with open(MANIFEST_PATH) as f:
        data = json.load(f)
    with _manifest_lock:
        _manifest = data
    logger.info("Manifest loaded: %d rules", len(_manifest))


def get_rule(name: str) -> Optional[dict]:
    with _manifest_lock:
        return _manifest.get(name)


def resolve_script(relative_path: Optional[str]) -> Optional[str]:
    if not relative_path:
        return None
    return str(STANDARDS_BASE / relative_path)


# ---------------------------------------------------------------------------
# Request handler
# ---------------------------------------------------------------------------

def handle_request(req: dict) -> list[dict]:
    """
    Process a single request dict and return list of result dicts to send.
    """
    action = req.get("action")
    req_id = req.get("req_id", "")

    if action == "ping":
        return [{"req_id": req_id, "pong": True}]

    if action == "scan":
        return [_exec_scan(req_id, req.get("rule", ""))]

    if action == "fix":
        return [_exec_fix(req_id, req.get("rule", ""))]

    if action == "scan_batch":
        rules = req.get("rules") or list(_manifest.keys())
        results = []
        for rule_name in rules:
            results.append(_exec_scan(req_id, rule_name))
        results.append({"req_id": req_id, "done": True, "total": len(rules)})
        return results

    return [{"req_id": req_id, "status": "ERROR", "message": f"Unknown action: {action}"}]


def _exec_scan(req_id: str, rule_name: str) -> dict:
    rule = get_rule(rule_name)
    if not rule:
        return {"req_id": req_id, "rule": rule_name, "status": "ERROR",
                "message": "Unknown rule — not in manifest allowlist"}

    script_path = resolve_script(rule.get("scan_script"))
    if not script_path:
        return {"req_id": req_id, "rule": rule_name, "status": "MDM_REQUIRED",
                "message": "No scan script — requires MDM configuration profile"}

    data, exit_code, duration_ms = run_script(script_path)
    return {
        "req_id": req_id,
        "rule": rule_name,
        "status": data.get("status", "ERROR"),
        "result": data.get("result"),
        "expected": data.get("expected"),
        "message": data.get("message"),
        "exit_code": exit_code,
        "duration_ms": duration_ms,
    }


def _exec_fix(req_id: str, rule_name: str) -> dict:
    rule = get_rule(rule_name)
    if not rule:
        return {"req_id": req_id, "rule": rule_name, "action": "ERROR",
                "message": "Unknown rule — not in manifest allowlist"}

    script_path = resolve_script(rule.get("fix_script"))
    if not script_path:
        return {"req_id": req_id, "rule": rule_name, "action": "NOT_APPLICABLE",
                "message": "No fix script available"}

    data, exit_code, duration_ms = run_script(script_path)
    return {
        "req_id": req_id,
        "rule": rule_name,
        "action": data.get("action", "ERROR"),
        "message": data.get("message"),
        "exit_code": exit_code,
        "duration_ms": duration_ms,
    }


# ---------------------------------------------------------------------------
# Socket server
# ---------------------------------------------------------------------------

def handle_client(conn: socket.socket, addr) -> None:
    logger.info("Client connected")
    try:
        buffer = b""
        while True:
            chunk = conn.recv(4096)
            if not chunk:
                break
            buffer += chunk
            while b"\n" in buffer:
                line, buffer = buffer.split(b"\n", 1)
                line = line.strip()
                if not line:
                    continue
                try:
                    req = json.loads(line)
                except json.JSONDecodeError as e:
                    error = json.dumps({"status": "ERROR", "message": f"Invalid JSON: {e}"}) + "\n"
                    conn.sendall(error.encode())
                    continue

                results = handle_request(req)
                for result in results:
                    conn.sendall((json.dumps(result) + "\n").encode())
    except Exception as exc:
        logger.error("Client handler error: %s", exc)
    finally:
        conn.close()
        logger.info("Client disconnected")


def run_server() -> None:
    socket_path = Path(HXG_SOCKET_PATH)
    socket_path.parent.mkdir(parents=True, exist_ok=True)

    if socket_path.exists():
        socket_path.unlink()

    server = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
    server.bind(str(socket_path))

    # Owner: root, group: admin (gid 80 on macOS), mode 0660
    os.chmod(str(socket_path), 0o660)
    try:
        import grp
        gid = grp.getgrnam("admin").gr_gid
        os.chown(str(socket_path), 0, gid)
    except Exception:
        pass  # best-effort

    server.listen(5)
    logger.info("hxg_runner listening on %s (uid=%d)", HXG_SOCKET_PATH, os.getuid())

    try:
        while True:
            conn, addr = server.accept()
            t = threading.Thread(target=handle_client, args=(conn, addr), daemon=True)
            t.start()
    except KeyboardInterrupt:
        logger.info("hxg_runner shutting down")
    finally:
        server.close()
        if socket_path.exists():
            socket_path.unlink()


if __name__ == "__main__":
    if os.getuid() != 0:
        print("ERROR: hxg_runner must run as root", file=sys.stderr)
        sys.exit(1)
    load_manifest()
    run_server()
