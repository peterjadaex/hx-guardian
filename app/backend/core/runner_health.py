"""
Runner capability verdict — one place that decides whether the privileged runner
can actually assess compliance, so the scan path, the status endpoint and the
pre-flight check all agree.

A successful ping is not enough: the runner answers ping from a constant, and it
keeps serving after load_manifest() has failed, leaving it with zero rules. In
that state every scan used to return 217 ERROR results plus 217 false
SUSPICIOUS_ACTION audit rows. This module exists to catch that before a scan
starts and report it honestly instead.
"""
import asyncio
import logging
from dataclasses import dataclass
from datetime import datetime
from typing import Optional

from core.manifest import get_all_rules
from core.runner_client import RunnerError, capabilities

logger = logging.getLogger(__name__)

RESTART_HINT = "sudo zsh app/update.sh runner"


@dataclass(frozen=True)
class RunnerCapability:
    connected: bool          # something answered on the socket
    available: bool          # safe to run scans / fixes
    reason: Optional[str]    # machine-readable key, None when healthy
    detail: str              # one actionable sentence for the operator
    uid: Optional[int]
    manifest_rules: Optional[int]
    server_manifest_rules: int
    stale_manifest: bool
    legacy: bool             # runner predates the capabilities action
    checked_at: datetime


def _verdict(**kw) -> RunnerCapability:
    kw.setdefault("uid", None)
    kw.setdefault("manifest_rules", None)
    kw.setdefault("stale_manifest", False)
    kw.setdefault("legacy", False)
    return RunnerCapability(checked_at=datetime.utcnow(), **kw)


async def probe_runner(timeout: float = 2.0) -> RunnerCapability:
    """Ask the runner what it can do and reduce that to a single verdict.

    Never raises and never blocks longer than roughly `timeout`, so no caller
    can be wedged by an unresponsive runner.
    """
    try:
        server_rules = len(get_all_rules())
    except Exception:
        server_rules = 0

    def fail(reason: str, detail: str, **kw) -> RunnerCapability:
        return _verdict(connected=kw.pop("connected", False), available=False,
                        reason=reason, detail=detail,
                        server_manifest_rules=server_rules, **kw)

    try:
        results = await asyncio.wait_for(capabilities(timeout=timeout), timeout=timeout + 0.5)
    except RunnerError as e:
        return fail("unreachable",
                    f"Privileged runner is not reachable on its socket ({e}). "
                    f"Start or redeploy it with: {RESTART_HINT}")
    except asyncio.TimeoutError:
        return fail("no_response",
                    "Privileged runner accepted the connection but did not reply. "
                    f"Restart it with: {RESTART_HINT}", connected=True)
    except Exception as e:                                  # never wedge a caller
        logger.warning("Runner capability probe failed unexpectedly: %s", e)
        return fail("probe_failed", f"Could not determine runner state: {e}")

    if not results:
        return fail("no_response",
                    "Privileged runner accepted the connection but did not reply. "
                    f"Restart it with: {RESTART_HINT}", connected=True)

    caps = results[0]
    if not isinstance(caps, dict):
        # This function is on the scan path and on pre-flight; it must not raise.
        # A reply we cannot read is a runner we cannot vouch for.
        logger.warning("Runner capability reply was not an object: %r", caps)
        return fail("bad_reply",
                    "Privileged runner sent an unreadable capability reply. "
                    f"Redeploy it with: {RESTART_HINT}", connected=True)

    # A runner built before this action exists still scans correctly, so treat it
    # as usable rather than bricking a working install on a server-only upgrade.
    if "Unknown action" in str(caps.get("message", "")):
        return _verdict(connected=True, available=True, reason="legacy_runner",
                        detail="Runner predates capability reporting; its health "
                               f"cannot be verified. Redeploy with: {RESTART_HINT}",
                        server_manifest_rules=server_rules, legacy=True)

    uid = caps.get("uid")
    runner_rules = caps.get("manifest_rules")

    if uid is not None and uid != 0:
        return fail("not_root",
                    f"Runner is running as uid {uid}, not root, so it cannot "
                    "assess or remediate anything.", connected=True, uid=uid,
                    manifest_rules=runner_rules)

    if not runner_rules:
        return fail("manifest_empty",
                    f"Runner loaded 0 rules from {caps.get('manifest_path')}. "
                    f"Restore the manifest and restart it with: {RESTART_HINT}",
                    connected=True, uid=uid, manifest_rules=runner_rules)

    if not caps.get("standards_base_ok") or not caps.get("scan_dir_count"):
        return fail("standards_missing",
                    f"Runner cannot find scan scripts under {caps.get('standards_base')}. "
                    f"Redeploy the standards tree, then: {RESTART_HINT}",
                    connected=True, uid=uid, manifest_rules=runner_rules)

    # The runner reads the manifest once at startup, so an edited manifest is
    # invisible until it restarts. It can still assess the rules it knows about,
    # so this is a warning rather than a blocker.
    if server_rules and runner_rules != server_rules:
        return _verdict(connected=True, available=True, reason="manifest_stale",
                        detail=f"Runner has {runner_rules} rules loaded but the manifest "
                               f"now holds {server_rules}. Restart to pick up changes: "
                               f"{RESTART_HINT}",
                        server_manifest_rules=server_rules, uid=uid,
                        manifest_rules=runner_rules, stale_manifest=True)

    return _verdict(connected=True, available=True, reason=None,
                    detail="Runner is available.", server_manifest_rules=server_rules,
                    uid=uid, manifest_rules=runner_rules)
