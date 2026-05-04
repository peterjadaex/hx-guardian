"""
Unix socket client — sends requests to hxg_runner and reads results.
Used by FastAPI route handlers (running as admin) to communicate with
the privileged runner daemon (running as root).
"""
import asyncio
import json
import logging
import socket
import uuid
from typing import AsyncGenerator, Optional

HXG_SOCKET_PATH = "/var/run/hxg/runner.sock"
logger = logging.getLogger(__name__)

# Loopback Unix socket connect is sub-millisecond on a healthy system. The
# previous 5s ceiling was 5,000× too generous and masked real wedges as slow
# requests. With launchd socket activation, the socket is bound from t=0;
# transient ECONNREFUSED only happens during a runner respawn, where a few
# hundred ms of bounded retry covers the gap without re-executing requests.
HXG_CONNECT_TIMEOUT = 0.25
HXG_RECONNECT_TRIES = 3
HXG_RECONNECT_BACKOFF = 0.1


class RunnerError(Exception):
    pass


def _new_req_id() -> str:
    return uuid.uuid4().hex[:12]


async def _open_connection():
    """Open a Unix-socket connection with bounded reconnect.

    Reconnects only on connect-time failures (runner respawning, socket
    file not yet ready, ECONNREFUSED). NEVER retries mid-stream — that
    could re-execute a privileged operation.
    """
    last_exc: Exception | None = None
    delay = HXG_RECONNECT_BACKOFF
    for attempt in range(HXG_RECONNECT_TRIES):
        try:
            return await asyncio.wait_for(
                asyncio.open_unix_connection(HXG_SOCKET_PATH),
                timeout=HXG_CONNECT_TIMEOUT,
            )
        except (ConnectionRefusedError, FileNotFoundError, asyncio.TimeoutError) as e:
            last_exc = e
            if attempt < HXG_RECONNECT_TRIES - 1:
                await asyncio.sleep(delay)
                delay *= 2
    raise RunnerError(
        f"Cannot connect to hxg_runner at {HXG_SOCKET_PATH} after "
        f"{HXG_RECONNECT_TRIES} attempts: {last_exc}"
    )


async def _send_recv_lines(req: dict, timeout: float = 10.0) -> list[dict]:
    """Send one request, collect all response lines until 'done' or connection close."""
    req_id = _new_req_id()
    req["req_id"] = req_id
    payload = (json.dumps(req) + "\n").encode()

    try:
        reader, writer = await _open_connection()
        writer.write(payload)
        await writer.drain()

        results = []
        while True:
            try:
                line = await asyncio.wait_for(reader.readline(), timeout=timeout)
            except asyncio.TimeoutError:
                break
            if not line:
                break
            try:
                data = json.loads(line.decode().strip())
                results.append(data)
                if data.get("done"):
                    break
            except json.JSONDecodeError:
                continue

        writer.close()
        try:
            await writer.wait_closed()
        except Exception:
            pass

        return results
    except RunnerError:
        raise
    except Exception as e:
        raise RunnerError(f"Runner communication error: {e}")


async def scan_rule(rule_name: str) -> dict:
    """Run a single scan script and return the result dict."""
    results = await _send_recv_lines({"action": "scan", "rule": rule_name}, timeout=70.0)
    if not results:
        return {"rule": rule_name, "status": "ERROR", "message": "No response from runner"}
    return results[0]


async def fix_rule(rule_name: str) -> dict:
    """Run a single fix script and return the result dict."""
    results = await _send_recv_lines({"action": "fix", "rule": rule_name}, timeout=70.0)
    if not results:
        return {"rule": rule_name, "action": "ERROR", "message": "No response from runner"}
    return results[0]


async def undo_fix_rule(rule_name: str) -> dict:
    """Run a single undo-fix script and return the result dict."""
    results = await _send_recv_lines({"action": "undo_fix", "rule": rule_name}, timeout=70.0)
    if not results:
        return {"rule": rule_name, "action": "ERROR", "message": "No response from runner"}
    return results[0]


async def scan_batch_stream(rules: Optional[list[str]] = None) -> AsyncGenerator[dict, None]:
    """
    Stream scan results one at a time as the runner processes them.
    Yields individual result dicts (not the final 'done' sentinel).
    """
    req_id = _new_req_id()
    req = {"action": "scan_batch", "req_id": req_id}
    if rules:
        req["rules"] = rules
    payload = (json.dumps(req) + "\n").encode()

    try:
        reader, writer = await _open_connection()
        writer.write(payload)
        await writer.drain()

        while True:
            try:
                # 120s per line — enough for any single script (executor cap is 60s)
                # plus some headroom. With streaming, each line arrives as soon as
                # one script finishes, so this timeout is per-script not per-batch.
                line = await asyncio.wait_for(reader.readline(), timeout=120.0)
            except asyncio.TimeoutError:
                break
            if not line:
                break
            try:
                data = json.loads(line.decode().strip())
                if data.get("done"):
                    break
                yield data
            except json.JSONDecodeError:
                continue

        writer.close()
        try:
            await writer.wait_closed()
        except Exception:
            pass

    except RunnerError:
        raise
    except Exception as e:
        raise RunnerError(f"Runner stream error: {e}")


async def list_profiles() -> set[str]:
    """List installed MDM profile identifiers via the runner (runs as root)."""
    results = await _send_recv_lines({"action": "list_profiles"}, timeout=15.0)
    if not results:
        return set()
    return set(results[0].get("profile_ids", []))


async def install_profile(profile_path: str) -> dict:
    """Install a single MDM profile via the runner."""
    results = await _send_recv_lines(
        {"action": "install_profile", "profile_path": profile_path},
        timeout=35.0,
    )
    if not results:
        return {"profile_path": profile_path, "status": "ERROR",
                "message": "No response from runner"}
    return results[0]


async def install_profiles_batch(profile_paths: list[str]) -> AsyncGenerator[dict, None]:
    """Install multiple profiles, streaming results one at a time."""
    req_id = _new_req_id()
    req = {"action": "install_profiles_batch", "req_id": req_id,
           "profile_paths": profile_paths}
    payload = (json.dumps(req) + "\n").encode()

    try:
        reader, writer = await _open_connection()
        writer.write(payload)
        await writer.drain()

        while True:
            try:
                line = await asyncio.wait_for(reader.readline(), timeout=60.0)
            except asyncio.TimeoutError:
                break
            if not line:
                break
            try:
                data = json.loads(line.decode().strip())
                if data.get("done"):
                    yield data
                    break
                yield data
            except json.JSONDecodeError:
                continue

        writer.close()
        try:
            await writer.wait_closed()
        except Exception:
            pass

    except RunnerError:
        raise
    except Exception as e:
        raise RunnerError(f"Runner stream error: {e}")


async def ping() -> bool:
    """Check if runner is alive. Bounded by HXG_CONNECT_TIMEOUT × tries + 1s read."""
    try:
        results = await _send_recv_lines({"action": "ping"}, timeout=1.0)
        return bool(results and results[0].get("pong"))
    except RunnerError:
        return False
