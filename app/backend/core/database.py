"""
SQLAlchemy synchronous database setup.
Database file: app/data/hxguardian.db
"""
from pathlib import Path
from sqlalchemy import create_engine
from sqlalchemy.orm import sessionmaker, DeclarativeBase

DB_PATH = Path(__file__).parent.parent.parent / "data" / "hxguardian.db"
DB_URL = f"sqlite:///{DB_PATH}"

engine = create_engine(
    DB_URL,
    connect_args={"check_same_thread": False},
    echo=False,
)

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


def init_db() -> None:
    """Create all tables if they don't exist, and apply incremental migrations."""
    from core import models  # noqa: F401 — ensure models are imported
    from sqlalchemy import inspect, text
    DB_PATH.parent.mkdir(parents=True, exist_ok=True)
    Base.metadata.create_all(bind=engine)
    # Migration: add volume_uuid to usb_whitelist if it was created before this column existed
    inspector = inspect(engine)
    existing_cols = [c["name"] for c in inspector.get_columns("usb_whitelist")]
    if "volume_uuid" not in existing_cols:
        with engine.connect() as conn:
            conn.execute(text("ALTER TABLE usb_whitelist ADD COLUMN volume_uuid VARCHAR(64)"))
            conn.commit()
