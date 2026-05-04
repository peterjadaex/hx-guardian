"""
SQLAlchemy synchronous database setup.
Database file: app/data/hxguardian.db (dev) or
               /Library/Application Support/hxguardian/data/hxguardian.db (frozen binary)
"""
import logging
import sys
import threading
from pathlib import Path
from sqlalchemy import create_engine, event
from sqlalchemy.orm import sessionmaker, DeclarativeBase

logger = logging.getLogger(__name__)

if getattr(sys, 'frozen', False):
    DB_PATH = Path("/Library/Application Support/hxguardian/data/hxguardian.db")
else:
    DB_PATH = Path(__file__).parent.parent.parent / "data" / "hxguardian.db"
DB_URL = f"sqlite:///{DB_PATH}"

# Set by init_db() after running PRAGMA foreign_key_check. If the existing
# database has orphan rows, leave foreign_keys OFF so we don't break a
# previously-working install — log the violations and let the operator clean up.
_enable_foreign_keys = True

engine = create_engine(
    DB_URL,
    connect_args={"check_same_thread": False, "timeout": 10.0},
    pool_pre_ping=True,
    echo=False,
)


@event.listens_for(engine, "connect")
def _sqlite_pragmas(dbapi_conn, _):
    cur = dbapi_conn.cursor()
    cur.execute("PRAGMA journal_mode=WAL")
    cur.execute("PRAGMA busy_timeout=10000")
    cur.execute("PRAGMA synchronous=NORMAL")
    cur.execute("PRAGMA wal_autocheckpoint=1000")
    if _enable_foreign_keys:
        cur.execute("PRAGMA foreign_keys=ON")
    # Force WAL recovery synchronously here, where exceptions surface, rather
    # than silently on the first INSERT. busy_timeout above bounds the wait.
    cur.execute("BEGIN IMMEDIATE")
    cur.execute("COMMIT")
    cur.close()


SessionLocal = sessionmaker(autocommit=False, autoflush=False, bind=engine)


class Base(DeclarativeBase):
    pass


def get_db():
    """FastAPI dependency: yields a DB session."""
    db = SessionLocal()
    try:
        yield db
    finally:
        db.close()


_init_lock = threading.Lock()
_init_done = False


def init_db() -> None:
    """Create all tables if they don't exist, and apply incremental migrations.

    Idempotent and lock-guarded. Bounded by SQLite busy_timeout (10s) — a
    pathological WAL recovery surfaces as OperationalError, not a hang.
    """
    global _init_done, _enable_foreign_keys
    with _init_lock:
        if _init_done:
            return

        from core import models  # noqa: F401 — ensure models are imported
        from sqlalchemy import inspect, text

        DB_PATH.parent.mkdir(parents=True, exist_ok=True)

        # Pre-flight: check for existing FK violations BEFORE any migration runs.
        # If we find any, disable foreign_keys for this process so connections
        # don't start failing in production. Log loudly so an operator can fix.
        try:
            with engine.connect() as conn:
                rows = conn.execute(text("PRAGMA foreign_key_check")).fetchall()
            if rows:
                logger.warning(
                    "PRAGMA foreign_key_check returned %d violation(s); "
                    "running with foreign_keys=OFF to avoid breaking existing data: %s",
                    len(rows), rows[:10],
                )
                _enable_foreign_keys = False
        except Exception as exc:
            logger.warning("foreign_key_check failed (%s); proceeding without FK enforcement", exc)
            _enable_foreign_keys = False

        Base.metadata.create_all(bind=engine)

        # Migration: add volume_uuid to usb_whitelist if it was created before this column existed
        inspector = inspect(engine)
        existing_cols = [c["name"] for c in inspector.get_columns("usb_whitelist")]
        if "volume_uuid" not in existing_cols:
            with engine.connect() as conn:
                conn.execute(text("ALTER TABLE usb_whitelist ADD COLUMN volume_uuid VARCHAR(64)"))
                conn.commit()

        _init_done = True
