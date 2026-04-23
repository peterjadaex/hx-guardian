#!/usr/bin/env python3
"""
HX Guardian Shell Watcher — device-action audit capture daemon.

Runs as root via launchd. Two independent workers feed the audit DB:

  1. History tailer → shell_exec_log (source='history')
     Tails ~/.zsh_history, ~/.bash_history for every real user (+ /var/root).
     Gives the actual argv each user typed interactively.

  2. Biometric log stream → biometric_events
     Subscribes to the unified log for LocalAuthentication / biometrickitd /
     coreauthd / Touch-ID-adjacent events. Classifies each event into
     REQUEST / SUCCESS / FAILURE / CANCELLED / TEARDOWN / OTHER by the
     event message text. Used by the UI's BIOMETRIC_AUTH filter.

Why history (not unified log) for shell exec: the unified log doesn't
expose per-exec events to unentitled apps, and Endpoint Security needs a
signed entitlement we don't have. For biometrics, however, macOS *does*
emit rich unified-log events, so that pipeline works.

Backpressure: each worker enqueues to its own writer-batched queue. On
overflow, a drop counter is flushed as a *_DROPPED audit_log row every
minute. Neither writer blocks the others.
"""
import json
import logging
import os
import pwd
import queue
import re
import signal
import sqlite3
import subprocess
import sys
import threading
import time
from datetime import datetime
from pathlib import Path
from typing import Optional

# ── Config ────────────────────────────────────────────────────────────────────

if getattr(sys, 'frozen', False):
    DB_PATH = Path("/Library/Application Support/hxguardian/data/hxguardian.db")
else:
    DB_PATH = Path(__file__).resolve().parent.parent / "data" / "hxguardian.db"

LOG_FILE = "/var/log/hxguardian_shell.log"

QUEUE_MAX = 5000
BATCH_SIZE = 50
BATCH_FLUSH_INTERVAL = 2.0     # seconds
DROP_FLUSH_INTERVAL = 60.0     # seconds between SHELL_EXEC_DROPPED rows
HISTORY_POLL_INTERVAL = 1.0
HISTORY_RESCAN_INTERVAL = 30.0
RAW_JSON_MAX = 2048            # truncate raw_json column to 2KB

# ── Logging ───────────────────────────────────────────────────────────────────

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s %(levelname)s %(message)s",
    handlers=[logging.FileHandler(LOG_FILE)],
)
log = logging.getLogger(__name__)


# ── Shared state ──────────────────────────────────────────────────────────────

feed: "queue.Queue[dict]" = queue.Queue(maxsize=QUEUE_MAX)
drop_counter = 0
drop_lock = threading.Lock()
stop_event = threading.Event()


def enqueue(row: dict) -> None:
    """Push a row onto the batched writer queue. Drops on overflow."""
    global drop_counter
    try:
        feed.put_nowait(row)
    except queue.Full:
        with drop_lock:
            drop_counter += 1


def enqueue_blocking(row: dict, timeout: float = 5.0) -> None:
    """Blocking variant for the history path. The initial scan of a user with
    years of shell history can generate 10k+ rows at once — put_nowait would
    drop most of them. Block up to `timeout`s waiting for writer drain, then
    fall back to the drop counter so we never wedge the worker."""
    global drop_counter
    try:
        feed.put(row, timeout=timeout)
    except queue.Full:
        with drop_lock:
            drop_counter += 1


# ── Writer thread ─────────────────────────────────────────────────────────────

def _open_db() -> sqlite3.Connection:
    con = sqlite3.connect(str(DB_PATH), timeout=5.0)
    con.execute("PRAGMA busy_timeout=5000")
    con.execute("PRAGMA journal_mode=WAL")
    return con


def writer_loop() -> None:
    """Drain the feed queue into shell_exec_log in batches.

    On a fresh install the server (which owns schema creation via SQLAlchemy
    init_db) may still be starting when this daemon boots — so the DB file
    might not exist yet. Poll until it appears instead of exiting; the
    history worker keeps filling the queue meanwhile (and the bounded queue
    will start dropping with the normal SHELL_EXEC_DROPPED counter if the
    server takes absurdly long).
    """
    waited_since: Optional[float] = None
    while not stop_event.is_set() and not DB_PATH.exists():
        if waited_since is None:
            waited_since = time.monotonic()
            log.warning("DB not yet at %s — waiting for server to create it", DB_PATH)
        time.sleep(2.0)
        if time.monotonic() - waited_since > 60 and time.monotonic() - waited_since < 62:
            log.warning("Still waiting for DB after 60s — is the server running?")
    if stop_event.is_set():
        return
    log.info("DB is ready at %s — writer entering main loop", DB_PATH)

    last_flush = time.monotonic()
    last_drop_flush = time.monotonic()
    buf: list[dict] = []

    while not stop_event.is_set():
        timeout = max(0.05, BATCH_FLUSH_INTERVAL - (time.monotonic() - last_flush))
        try:
            row = feed.get(timeout=timeout)
            buf.append(row)
        except queue.Empty:
            pass

        now = time.monotonic()
        should_flush = (
            len(buf) >= BATCH_SIZE
            or (buf and now - last_flush >= BATCH_FLUSH_INTERVAL)
        )
        if should_flush:
            try:
                con = _open_db()
                with con:
                    con.executemany(
                        "INSERT INTO shell_exec_log "
                        "(ts, source, pid, ppid, user, process_path, command, event_message, subsystem, raw_json) "
                        "VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)",
                        [
                            (
                                r.get("ts") or datetime.utcnow(),
                                r.get("source"),
                                r.get("pid"),
                                r.get("ppid"),
                                r.get("user"),
                                r.get("process_path"),
                                r.get("command"),
                                r.get("event_message"),
                                r.get("subsystem"),
                                r.get("raw_json"),
                            )
                            for r in buf
                        ],
                    )
                con.close()
                buf.clear()
                last_flush = now
            except Exception as exc:
                log.error("Batch write failed (%d rows kept): %s", len(buf), exc)
                # Keep the buffer; retry on next iteration. Cap to avoid unbounded growth.
                if len(buf) > BATCH_SIZE * 4:
                    dropped = len(buf) - BATCH_SIZE * 2
                    buf = buf[-BATCH_SIZE * 2:]
                    with drop_lock:
                        global drop_counter
                        drop_counter += dropped
                time.sleep(1.0)

        # Flush the drop counter as an audit_log row periodically
        if now - last_drop_flush >= DROP_FLUSH_INTERVAL:
            last_drop_flush = now
            with drop_lock:
                n = drop_counter
                drop_counter = 0
            if n:
                try:
                    con = _open_db()
                    with con:
                        con.execute(
                            "INSERT INTO audit_log (ts, action, target, detail_json, operator, source_ip) "
                            "VALUES (?, ?, ?, ?, ?, ?)",
                            (
                                datetime.utcnow(),
                                "SHELL_EXEC_DROPPED",
                                None,
                                json.dumps({"count": n, "window_secs": DROP_FLUSH_INTERVAL}),
                                "shell_watcher",
                                "system",
                            ),
                        )
                    con.close()
                    log.warning("Dropped %d shell-exec events in last %.0fs", n, DROP_FLUSH_INTERVAL)
                except Exception as exc:
                    log.error("Failed to record drop counter: %s", exc)


# ── History tailer ────────────────────────────────────────────────────────────

HISTORY_FILES = (".zsh_history", ".bash_history")


def _scan_history_targets() -> list[tuple[str, Path]]:
    """Return (username, path) pairs for all history files we can see."""
    targets: list[tuple[str, Path]] = []
    for user_dir in Path("/Users").glob("*"):
        if not user_dir.is_dir():
            continue
        user = user_dir.name
        if user.startswith("."):
            continue
        for fname in HISTORY_FILES:
            p = user_dir / fname
            if p.exists():
                targets.append((user, p))
    for fname in HISTORY_FILES:
        p = Path("/var/root") / fname
        if p.exists():
            targets.append(("root", p))
    return targets


_ZSH_EXT_RE = re.compile(r"^: (\d+):\d+;(.*)$")
_BASH_TS_RE = re.compile(r"^#(\d{9,11})$")


def _sniff_format(first_lines: list[str]) -> str:
    """Return 'zsh_extended' | 'bash_ts' | 'plain' from sampling the file head."""
    for line in first_lines:
        if _ZSH_EXT_RE.match(line):
            return "zsh_extended"
        if _BASH_TS_RE.match(line):
            return "bash_ts"
    return "plain"


class HistoryFileState:
    __slots__ = ("inode", "offset", "format", "pending_ts")

    def __init__(self) -> None:
        self.inode: Optional[int] = None
        self.offset: int = 0
        self.format: str = "plain"
        self.pending_ts: Optional[datetime] = None


def _emit_history_command(user: str, path: Path, cmd_line: str, ts: datetime) -> None:
    cmd_line = cmd_line.rstrip("\n")
    if not cmd_line.strip():
        return
    enqueue_blocking({
        "ts": ts,
        "source": "history",
        "pid": None,
        "ppid": None,
        "user": user,
        "process_path": str(path),
        "command": cmd_line,
        "event_message": None,
        "subsystem": None,
        "raw_json": None,
    })


def _ingest_chunk(state: HistoryFileState, user: str, path: Path, chunk: str) -> None:
    lines = chunk.split("\n")
    # chunk may end mid-line; keep the last fragment for next tick by re-feeding offset
    # Here we process only complete lines (terminated by \n within `chunk`), which is
    # already guaranteed because the caller reads up to EOF and this chunk is what it got.
    for raw_line in lines:
        line = raw_line.rstrip("\r")
        if not line:
            continue
        if state.format == "zsh_extended":
            m = _ZSH_EXT_RE.match(line)
            if m:
                ts = datetime.utcfromtimestamp(int(m.group(1)))
                cmd = m.group(2)
                _emit_history_command(user, path, cmd, ts)
            else:
                # continuation line of a multiline command — append, best effort
                _emit_history_command(user, path, line, datetime.utcnow())
        elif state.format == "bash_ts":
            m = _BASH_TS_RE.match(line)
            if m:
                state.pending_ts = datetime.utcfromtimestamp(int(m.group(1)))
            else:
                ts = state.pending_ts or datetime.utcnow()
                state.pending_ts = None
                _emit_history_command(user, path, line, ts)
        else:
            _emit_history_command(user, path, line, datetime.utcnow())


def _load_history_cursor(path: str) -> Optional[tuple[int, int, str]]:
    """Return (inode, offset, format) if a cursor row exists, else None.
    Silently returns None if the DB/table isn't ready yet — caller then treats
    the file as first-seen and ingests from offset 0."""
    try:
        con = _open_db()
        try:
            cur = con.execute(
                "SELECT inode, offset, format FROM shell_history_cursor WHERE path = ?",
                (path,),
            )
            row = cur.fetchone()
        finally:
            con.close()
        if row is None:
            return None
        inode, offset, fmt = row
        return (int(inode) if inode is not None else 0, int(offset or 0), fmt or "plain")
    except Exception:
        return None


def _save_history_cursor(path: str, inode: Optional[int], offset: int, fmt: str) -> None:
    """Upsert the cursor. Best-effort: errors are logged but don't stop ingest."""
    try:
        con = _open_db()
        try:
            with con:
                con.execute(
                    "INSERT INTO shell_history_cursor (path, inode, offset, format, updated_at) "
                    "VALUES (?, ?, ?, ?, ?) "
                    "ON CONFLICT(path) DO UPDATE SET "
                    "  inode = excluded.inode, "
                    "  offset = excluded.offset, "
                    "  format = excluded.format, "
                    "  updated_at = excluded.updated_at",
                    (path, inode, offset, fmt, datetime.utcnow()),
                )
        finally:
            con.close()
    except Exception as exc:
        log.error("Failed to save history cursor for %s: %s", path, exc)


def history_worker() -> None:
    log.info("Starting history tailer")

    # Wait for the DB (and its schema) before we start — otherwise the first
    # cursor load returns None for every file and we'd ingest from 0 even for
    # files we've seen before.
    waited_since: Optional[float] = None
    while not stop_event.is_set() and not DB_PATH.exists():
        if waited_since is None:
            waited_since = time.monotonic()
            log.warning("DB not yet at %s — history worker waiting", DB_PATH)
        time.sleep(2.0)
    if stop_event.is_set():
        return

    states: dict[str, HistoryFileState] = {}   # keyed by str(path)
    last_rescan = 0.0
    targets: list[tuple[str, Path]] = []

    while not stop_event.is_set():
        now = time.monotonic()
        if now - last_rescan >= HISTORY_RESCAN_INTERVAL:
            targets = _scan_history_targets()
            last_rescan = now

        for user, path in targets:
            key = str(path)
            st = states.get(key)
            try:
                stat = path.stat()
            except OSError:
                continue

            if st is None:
                st = HistoryFileState()
                # Sniff format from the head once up front; used whether we
                # resume from a saved cursor or start fresh.
                try:
                    with open(path, "r", errors="replace") as f:
                        head = [next(f, "") for _ in range(20)]
                    sniffed_fmt = _sniff_format([ln for ln in head if ln])
                except Exception:
                    sniffed_fmt = "plain"

                saved = _load_history_cursor(key)
                if saved is not None:
                    saved_inode, saved_offset, saved_fmt = saved
                    if saved_inode == stat.st_ino and saved_offset <= stat.st_size:
                        # Clean resume. Trust the persisted format so we don't
                        # flip mid-stream if the head was rewritten.
                        st.inode = stat.st_ino
                        st.offset = saved_offset
                        st.format = saved_fmt or sniffed_fmt
                        states[key] = st
                        log.info("Resuming %s at offset %d (size %d)", key, saved_offset, stat.st_size)
                        # Fall through to the normal read path below so we
                        # pick up anything appended while we were down.
                    else:
                        # Inode changed (rotation/reinstall) or file truncated
                        # since last save → treat as fresh.
                        st.inode = stat.st_ino
                        st.offset = 0
                        st.format = sniffed_fmt
                        states[key] = st
                        _save_history_cursor(key, st.inode, st.offset, st.format)
                        log.info("Cursor stale for %s (inode/truncate) — ingesting from 0", key)
                else:
                    # First ever sight of this file → ingest from the top so
                    # pre-install history is visible. Mark the cursor
                    # immediately so a crash mid-ingest doesn't cause a
                    # duplicate full replay on restart.
                    st.inode = stat.st_ino
                    st.offset = 0
                    st.format = sniffed_fmt
                    states[key] = st
                    _save_history_cursor(key, st.inode, st.offset, st.format)
                    log.info("First-seen %s (size %d) — ingesting from offset 0", key, stat.st_size)

            # Rotation or truncation detection mid-run
            if stat.st_ino != st.inode or stat.st_size < st.offset:
                st.inode = stat.st_ino
                st.offset = 0
                try:
                    with open(path, "r", errors="replace") as f:
                        head = [next(f, "") for _ in range(20)]
                    st.format = _sniff_format([ln for ln in head if ln])
                except Exception:
                    st.format = "plain"
                _save_history_cursor(key, st.inode, st.offset, st.format)

            if stat.st_size == st.offset:
                continue

            try:
                with open(path, "r", errors="replace") as f:
                    f.seek(st.offset)
                    chunk = f.read()
                new_offset = stat.st_size
            except OSError:
                continue

            if chunk:
                _ingest_chunk(st, user, path, chunk)
                st.offset = new_offset
                _save_history_cursor(key, st.inode, st.offset, st.format)

        time.sleep(HISTORY_POLL_INTERVAL)


# ── Biometric log stream ──────────────────────────────────────────────────────
#
# macOS emits rich unified-log events for LocalAuthentication / biometrickitd /
# coreauthd. Unlike raw exec events, these ARE available without an ES
# entitlement. The predicate casts a wide net intentionally — we'd rather
# capture noise (TEARDOWN) and classify it than miss a path. When Apple
# changes event shapes on a future macOS, new shapes land in OTHER and we
# refine the classifier; no events are lost.

# NARROW predicate — only capture the handful of event shapes that actually
# carry audit value. Everything else (Context bookkeeping, ACM pool counts,
# "Lid is open", lockout-state queries) is noise for the "who triggered
# Touch ID" question.
#
# What this catches, per auth session:
#   REQUEST:       evaluatePolicy / canEvaluatePolicy  (from the app)
#   FINGER_TOUCH:  fingerTouchTime                     (physical sensor event)
#   SUCCESS/FAIL:  replyHandler / finished with … / LAError in message
#   sudo:          pam_tid-related lines
BIO_PREDICATE = (
    '('
      'eventMessage CONTAINS "evaluatePolicy:" OR '   # real prompt call
      'eventMessage CONTAINS "fingerTouchTime" OR '   # sensor touched
      'eventMessage CONTAINS "matchingFinished" OR '
      'eventMessage CONTAINS "matchResult" OR '
      'eventMessage CONTAINS "replyHandler" OR '
      'eventMessage CONTAINS "finished with result" OR '
      'eventMessage CONTAINS "finished with error" OR '
      'eventMessage CONTAINS "LAError" OR '
      'eventMessage CONTAINS[c] "pam_tid"'
      # NOTE: canEvaluatePolicy intentionally excluded — it's a pre-check
      # ("can I prompt?"), not an actual auth attempt. Ingesting it added
      # ~2 duplicate REQUEST rows per session with no audit value.
    ') AND '
    # HID noise guardrails — kept defensively in case a touch/touchid token
    # ever appears in a trackpad event dump.
    'subsystem != "com.apple.Multitouch" AND '
    'subsystem != "com.apple.HID" AND '
    'NOT senderImagePath CONTAINS[c] "SkyLight"'
)

# Classifier — ordered list, first match wins. Best-effort; unmatched → OTHER.
# Keep TEARDOWN last among positives so "dealloc with error" still classifies
# as FAILURE (error tokens appear before teardown tokens in the ladder).
_BIO_CLASSIFIERS: list[tuple[re.Pattern, str]] = [
    # 1. FINGER_TOUCH — Secure Enclave physically saw a finger. Highest
    #    audit value: guaranteed signal from com.apple.BiometricKit.
    (re.compile(r"fingerTouchTime|FingerOn\b|FingerOff\b", re.I), "FINGER_TOUCH"),

    # 2. REQUEST — auth session started. Captures who initiated.
    #    Excludes canEvaluatePolicy (the pre-check) via negative lookbehind.
    (re.compile(r"(?<!can)evaluatePolicy:", re.I), "REQUEST"),

    # 3. SUCCESS — explicit policy evaluation result. Requires specific
    #    markers to avoid matching generic "returned success" cleanup noise.
    (re.compile(
        r"matchingFinished.*match(ed)?\b"
        r"|finished with result:\s*(1|YES|success)"
        r"|replyHandler:success"
        r"|matchResult:\s*1"
        r"|policy evaluation succeeded",
        re.I), "SUCCESS"),

    # 4. FAILURE — explicit policy evaluation failure. "lockout" is deliberately
    #    NOT in this regex — it appears in benign state-change notifications
    #    ("Environment has changed (biometric lockout state)") which are not
    #    auth failures. Real auth failures always emit LAError… or "finished
    #    with error".
    (re.compile(
        r"\bLAError[A-Za-z]+"
        r"|finished with error"
        r"|replyHandler:.*error"
        r"|matchResult:\s*0"
        r"|\bmismatch\b"
        r"|policy evaluation failed",
        re.I), "FAILURE"),

    # 5. CANCELLED — user dismissed / superseded / timeout.
    (re.compile(r"\binterrupted\b|\bcancel(l?ed)?\b|UserCancel|LAErrorUserCancel", re.I), "CANCELLED"),
]


# Classes the watcher actually INSERTS. Everything else is dropped at ingest —
# no row ever lands in the DB. Keeps the table tiny and the UI readable.
_BIO_KEEP = {"REQUEST", "FINGER_TOUCH", "SUCCESS", "FAILURE", "CANCELLED"}


# ── Session deduplication ────────────────────────────────────────────────────
# One real Touch ID prompt produces the same event on both client and server
# sides of the XPC boundary, plus repeated cleanup/retry events. Dedup by
# (session_context, event_class): one prompt shows up as at most one row per
# class, instead of 4–8 duplicates.
#
# The session identifier we care about is the TRAILING "ctxid:requestId" pair.
# Same session appears as:
#   LAContext[98:209:343]            (client side — Safari)
#   ContextProxy[2549:98:209:343]    (server side — coreauthd, PID prefix)
#   Context[209:343]                 (lower-layer context)
# Capturing just the last two colon-delimited integers yields "209:343" in
# all three cases, so client+server dedup correctly.
_SESSION_RE = re.compile(r"(?:LAContext|ContextProxy|Context)\[(?:\d+:)*(\d+:\d+)\]")
_recent_emit: dict[tuple[str, str], float] = {}
_recent_emit_lock = threading.Lock()
DEDUP_WINDOW = 30.0  # seconds


def _session_key(message: str) -> Optional[str]:
    """Extract the LAContext[X:Y:Z]-style identifier that groups related events."""
    if not message:
        return None
    m = _SESSION_RE.search(message)
    return m.group(1) if m else None


def _should_emit(session: Optional[str], event_class: str,
                 requesting_process: Optional[str] = None) -> bool:
    """Dedup key policy:
      - If we extracted a session id → (session, class). 30s window.
      - No session → (class, requesting_process, 2s bucket) as a fallback, so
        rapid event bursts (BiometricKit emits 5+ finger events within 10ms)
        collapse to one row without losing genuinely separate touches.
    """
    now = time.monotonic()
    if session:
        key = (session, event_class)
        window = DEDUP_WINDOW
    else:
        bucket = int(now // 2)  # 2-second buckets
        key = (event_class, requesting_process or "", bucket)
        window = 2.0
    with _recent_emit_lock:
        if len(_recent_emit) > 512:
            stale = [k for k, t in _recent_emit.items() if now - t > DEDUP_WINDOW]
            for k in stale:
                del _recent_emit[k]
        last = _recent_emit.get(key)
        if last is not None and now - last < window:
            return False
        _recent_emit[key] = now
        return True


def _classify_bio(message: str) -> Optional[str]:
    """Return a class label, or None if the row is low-value noise we should drop.
    Only labels in _BIO_KEEP make it to the database."""
    if not message:
        return None
    for pat, label in _BIO_CLASSIFIERS:
        if pat.search(message):
            return label if label in _BIO_KEEP else None
    return None


def _parse_log_ts(s: Optional[str]) -> datetime:
    """`log stream --style ndjson` emits e.g. '2026-04-23 08:34:11.123456+0800'."""
    if not s:
        return datetime.utcnow()
    try:
        head = s.rsplit(" ", 1)[0] if re.search(r"[+-]\d{4}$", s) else s
        return datetime.strptime(head, "%Y-%m-%d %H:%M:%S.%f")
    except Exception:
        return datetime.utcnow()


def _username_from_uid(uid) -> Optional[str]:
    if uid is None:
        return None
    try:
        return pwd.getpwuid(int(uid)).pw_name
    except Exception:
        return None


def _console_user() -> Optional[str]:
    """Whoever is at the screen right now. Logged alongside each event so
    audit rows always name a human, even if the event lacks userID."""
    try:
        import os as _os
        st = _os.stat("/dev/console")
        return _username_from_uid(st.st_uid)
    except Exception:
        return None


bio_feed: "queue.Queue[dict]" = queue.Queue(maxsize=QUEUE_MAX)
bio_drop_counter = 0
bio_drop_lock = threading.Lock()


def _bio_enqueue(row: dict) -> None:
    global bio_drop_counter
    try:
        bio_feed.put_nowait(row)
    except queue.Full:
        with bio_drop_lock:
            bio_drop_counter += 1


def bio_writer_loop() -> None:
    """Drain bio_feed into biometric_events in batches."""
    waited_since: Optional[float] = None
    while not stop_event.is_set() and not DB_PATH.exists():
        if waited_since is None:
            waited_since = time.monotonic()
            log.warning("DB not yet at %s — bio writer waiting", DB_PATH)
        time.sleep(2.0)
    if stop_event.is_set():
        return
    log.info("bio writer entering main loop")

    last_flush = time.monotonic()
    last_drop_flush = time.monotonic()
    buf: list[dict] = []

    while not stop_event.is_set():
        timeout = max(0.05, BATCH_FLUSH_INTERVAL - (time.monotonic() - last_flush))
        try:
            row = bio_feed.get(timeout=timeout)
            buf.append(row)
        except queue.Empty:
            pass

        now = time.monotonic()
        should_flush = (
            len(buf) >= BATCH_SIZE
            or (buf and now - last_flush >= BATCH_FLUSH_INTERVAL)
        )
        if should_flush:
            try:
                con = _open_db()
                with con:
                    con.executemany(
                        "INSERT INTO biometric_events "
                        "(ts, event_class, subsystem, category, requesting_process, "
                        " requesting_pid, user_uid, user, console_user, event_message, raw_json) "
                        "VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)",
                        [
                            (
                                r.get("ts") or datetime.utcnow(),
                                r.get("event_class"),
                                r.get("subsystem"),
                                r.get("category"),
                                r.get("requesting_process"),
                                r.get("requesting_pid"),
                                r.get("user_uid"),
                                r.get("user"),
                                r.get("console_user"),
                                r.get("event_message"),
                                r.get("raw_json"),
                            )
                            for r in buf
                        ],
                    )
                con.close()
                buf.clear()
                last_flush = now
            except Exception as exc:
                log.error("bio batch write failed (%d rows kept): %s", len(buf), exc)
                if len(buf) > BATCH_SIZE * 4:
                    dropped = len(buf) - BATCH_SIZE * 2
                    buf = buf[-BATCH_SIZE * 2:]
                    with bio_drop_lock:
                        global bio_drop_counter
                        bio_drop_counter += dropped
                time.sleep(1.0)

        if now - last_drop_flush >= DROP_FLUSH_INTERVAL:
            last_drop_flush = now
            with bio_drop_lock:
                n = bio_drop_counter
                bio_drop_counter = 0
            if n:
                try:
                    con = _open_db()
                    with con:
                        con.execute(
                            "INSERT INTO audit_log (ts, action, target, detail_json, operator, source_ip) "
                            "VALUES (?, ?, ?, ?, ?, ?)",
                            (
                                datetime.utcnow(),
                                "BIOMETRIC_EVENT_DROPPED",
                                None,
                                json.dumps({"count": n, "window_secs": DROP_FLUSH_INTERVAL}),
                                "shell_watcher",
                                "system",
                            ),
                        )
                    con.close()
                    log.warning("Dropped %d biometric events in last %.0fs", n, DROP_FLUSH_INTERVAL)
                except Exception as exc:
                    log.error("Failed to record bio drop counter: %s", exc)


def biometric_worker() -> None:
    cmd = ["/usr/bin/log", "stream", "--style", "ndjson", "--info", "--predicate", BIO_PREDICATE]
    log.info("Starting biometric log-stream worker")
    own_pid = os.getpid()

    while not stop_event.is_set():
        try:
            proc = subprocess.Popen(
                cmd,
                stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                bufsize=1, universal_newlines=True,
            )
        except Exception as exc:
            log.error("Could not spawn `log stream` for biometrics: %s — retrying in 5s", exc)
            time.sleep(5.0)
            continue

        try:
            assert proc.stdout is not None
            for line in proc.stdout:
                if stop_event.is_set():
                    break
                line = line.strip()
                if not line or not line.startswith("{"):
                    continue
                try:
                    evt = json.loads(line)
                except Exception:
                    continue

                pid = evt.get("processID")
                if pid == own_pid:
                    continue
                process_path = evt.get("processImagePath") or evt.get("processPath")
                # Filter self — our own /usr/bin/log child
                if isinstance(process_path, str) and process_path.endswith("/log"):
                    continue

                msg = evt.get("eventMessage") or ""
                event_class = _classify_bio(msg)
                if event_class is None:
                    continue  # drop noise — never reaches the DB

                # Dedup: collapse same (session, class) within 30s to one row.
                if not _should_emit(_session_key(msg), event_class, process_path):
                    continue

                raw = line
                if len(raw) > RAW_JSON_MAX:
                    raw = raw[:RAW_JSON_MAX]

                uid = evt.get("userID")
                _bio_enqueue({
                    "ts": _parse_log_ts(evt.get("timestamp")),
                    "event_class": event_class,
                    "subsystem": evt.get("subsystem"),
                    "category": evt.get("category"),
                    "requesting_process": process_path,
                    "requesting_pid": pid if isinstance(pid, int) else None,
                    "user_uid": uid if isinstance(uid, int) else None,
                    "user": _username_from_uid(uid),
                    "console_user": _console_user(),
                    "event_message": msg,
                    "raw_json": raw,
                })
        except Exception as exc:
            log.error("biometric worker read error: %s", exc)
        finally:
            try: proc.terminate()
            except Exception: pass
            try: proc.wait(timeout=5)
            except Exception: pass

        if not stop_event.is_set():
            log.warning("biometric log stream exited; restarting in 5s")
            time.sleep(5.0)


# ── Main ──────────────────────────────────────────────────────────────────────

def _install_signal_handlers() -> None:
    def _stop(_signum, _frame):
        log.info("Signal received; stopping")
        stop_event.set()
    signal.signal(signal.SIGTERM, _stop)
    signal.signal(signal.SIGINT, _stop)


def main() -> None:
    log.info("HX Guardian Shell Watcher starting (DB: %s, pid: %d)", DB_PATH, os.getpid())
    _install_signal_handlers()

    writer = threading.Thread(target=writer_loop, name="writer", daemon=True)
    history = threading.Thread(target=history_worker, name="history", daemon=True)
    bio_writer = threading.Thread(target=bio_writer_loop, name="bio_writer", daemon=True)
    bio = threading.Thread(target=biometric_worker, name="biometric", daemon=True)
    writer.start()
    history.start()
    bio_writer.start()
    bio.start()

    while not stop_event.is_set():
        time.sleep(1.0)

    log.info("Shell Watcher stopped.")


if __name__ == "__main__":
    try:
        main()
    except KeyboardInterrupt:
        log.info("Shell Watcher stopped.")
