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
import re
import os
import socket
import subprocess
import sys
import threading
import time
from typing import Optional
from pathlib import Path

# Allow imports from backend package
sys.path.insert(0, str(Path(__file__).parent))

from runner.executor import run_script

HXG_SOCKET_PATH = "/var/run/hxg/runner.sock"
if getattr(sys, 'frozen', False):
    STANDARDS_BASE = Path("/Library/Application Support/hxguardian")
else:
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

def handle_request(req: dict):
    """
    Process a single request dict and yield result dicts one at a time.
    Streaming one result per yield lets the client read progress without waiting
    for the entire batch to finish (avoids socket timeout on large scans).
    """
    action = req.get("action")
    req_id = req.get("req_id", "")

    if action == "ping":
        yield {"req_id": req_id, "pong": True, "done": True}

    elif action == "scan":
        result = _exec_scan(req_id, req.get("rule", ""))
        result["done"] = True
        yield result

    elif action == "fix":
        result = _exec_fix(req_id, req.get("rule", ""))
        result["done"] = True
        yield result

    elif action == "scan_batch":
        rules = req.get("rules") or list(_manifest.keys())
        count = 0
        for rule_name in rules:
            yield _exec_scan(req_id, rule_name)
            count += 1
        yield {"req_id": req_id, "done": True, "total": count}

    elif action == "list_profiles":
        result = _exec_list_profiles(req_id)
        result["done"] = True
        yield result

    elif action == "install_profile":
        result = _exec_install_profile(req_id, req.get("profile_path", ""))
        result["done"] = True
        yield result

    elif action == "install_profiles_batch":
        paths = req.get("profile_paths") or []
        installed = 0
        for p in paths:
            result = _exec_install_profile(req_id, p)
            if result.get("status") == "INSTALLED":
                installed += 1
            yield result
        yield {"req_id": req_id, "done": True, "total": len(paths), "installed": installed}

    else:
        yield {"req_id": req_id, "status": "ERROR", "message": f"Unknown action: {action}"}


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
# MDM profile installation
# ---------------------------------------------------------------------------

def _validate_profile_path(path_str: str) -> tuple[bool, str]:
    """Validate that a profile path is safe to install."""
    try:
        path = Path(path_str)
        if not path.is_absolute():
            return False, "Path must be absolute"
        if not path.is_file():
            return False, "File not found"
        if path.suffix != ".mobileconfig":
            return False, "Not a .mobileconfig file"
        try:
            path.resolve().relative_to(STANDARDS_BASE.resolve())
        except ValueError:
            return False, "Path is not within the standards directory"
        if "/mobileconfigs/unsigned/" not in str(path):
            return False, "Path is not in a mobileconfigs/unsigned directory"
        return True, ""
    except Exception as e:
        return False, str(e)


def _exec_list_profiles(req_id: str) -> dict:
    """Run 'profiles list' as root and return installed profile identifiers."""
    try:
        result = subprocess.run(
            ["/usr/bin/profiles", "list"],
            capture_output=True, text=True, timeout=10,
        )
        output = result.stdout
        profile_ids = re.findall(r"profileIdentifier: ([^\s]+)", output)
        # Fallback to XML format if text parsing found nothing
        if not profile_ids:
            try:
                result2 = subprocess.run(
                    ["/usr/bin/profiles", "list", "-output", "stdout-xml"],
                    capture_output=True, text=True, timeout=10,
                )
                profile_ids = re.findall(
                    r"<key>ProfileIdentifier</key>\s*<string>([^<]+)</string>",
                    result2.stdout,
                )
            except Exception:
                pass
        return {"req_id": req_id, "profile_ids": profile_ids}
    except Exception as e:
        logger.warning("profiles list failed: %s", e)
        return {"req_id": req_id, "profile_ids": []}


def _exec_install_profile(req_id: str, profile_path: str) -> dict:
    valid, err = _validate_profile_path(profile_path)
    if not valid:
        return {"req_id": req_id, "profile_path": profile_path,
                "status": "ERROR", "message": err}

    try:
        result = subprocess.run(
            ["/usr/bin/profiles", "install", "-path", profile_path],
            capture_output=True, text=True, timeout=30,
        )
        stderr = result.stderr.strip()
        stdout = result.stdout.strip()
        logger.info("profiles install exit=%d path=%s stderr=%r stdout=%r",
                    result.returncode, profile_path, stderr[:300], stdout[:300])
        if result.returncode == 0:
            logger.info("Profile installed: %s", profile_path)
            return {"req_id": req_id, "profile_path": profile_path,
                    "status": "INSTALLED", "message": "Profile installed successfully"}
        else:
            # Exit 71 (EX_PROTOCOL) and 73 (EX_CANTCREAT) both indicate user-approval required
            # on macOS Ventura+ / Sequoia. Also check stderr text as a fallback.
            approval_keywords = ("requires user approval", "user approval", "user must approve",
                                 "system settings", "must be approved")
            needs_approval = (
                result.returncode in (71, 73)
                or any(kw in stderr.lower() for kw in approval_keywords)
                or any(kw in stdout.lower() for kw in approval_keywords)
            )
            if needs_approval:
                return {"req_id": req_id, "profile_path": profile_path,
                        "status": "USER_APPROVAL_REQUIRED",
                        "message": f"Profile requires user approval in System Settings > Privacy & Security > Profiles. {stderr}"}
            return {"req_id": req_id, "profile_path": profile_path,
                    "status": "ERROR",
                    "message": f"profiles install failed (exit {result.returncode}): {stderr or stdout}"}
    except subprocess.TimeoutExpired:
        return {"req_id": req_id, "profile_path": profile_path,
                "status": "ERROR", "message": "Profile installation timed out"}
    except Exception as e:
        return {"req_id": req_id, "profile_path": profile_path,
                "status": "ERROR", "message": str(e)}


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
