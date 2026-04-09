"""
SQLAlchemy ORM models for hxguardian.db
"""
from datetime import datetime
from typing import Optional
from sqlalchemy import (
    Boolean, Column, Float, ForeignKey, Integer, String, Text, DateTime
)
from sqlalchemy.orm import relationship

from core.database import Base


class ScanSession(Base):
    __tablename__ = "scan_sessions"

    id = Column(Integer, primary_key=True, autoincrement=True)
    started_at = Column(DateTime, nullable=False, default=datetime.utcnow)
    finished_at = Column(DateTime, nullable=True)
    triggered_by = Column(String(32), nullable=False, default="manual")  # manual|scheduled|preflight
    filter_json = Column(Text, nullable=True)   # JSON filter criteria
    total_rules = Column(Integer, default=0)
    pass_count = Column(Integer, default=0)
    fail_count = Column(Integer, default=0)
    na_count = Column(Integer, default=0)
    error_count = Column(Integer, default=0)
    mdm_count = Column(Integer, default=0)
    exempt_count = Column(Integer, default=0)
    score_pct = Column(Float, nullable=True)    # pass / (pass+fail) * 100

    results = relationship("ScanResult", back_populates="session", cascade="all, delete-orphan")


class ScanResult(Base):
    __tablename__ = "scan_results"

    id = Column(Integer, primary_key=True, autoincrement=True)
    session_id = Column(Integer, ForeignKey("scan_sessions.id"), nullable=False, index=True)
    scanned_at = Column(DateTime, nullable=False, default=datetime.utcnow)
    rule = Column(String(128), nullable=False, index=True)
    category = Column(String(64), nullable=False, default="")
    status = Column(String(32), nullable=False)  # PASS|FAIL|NOT_APPLICABLE|ERROR|EXEMPT|MDM_REQUIRED
    result_value = Column(Text, nullable=True)
    expected_value = Column(Text, nullable=True)
    message = Column(Text, nullable=True)
    raw_output = Column(Text, nullable=True)
    exit_code = Column(Integer, nullable=True)
    duration_ms = Column(Integer, nullable=True)

    session = relationship("ScanSession", back_populates="results")


class FixResult(Base):
    __tablename__ = "fix_results"

    id = Column(Integer, primary_key=True, autoincrement=True)
    executed_at = Column(DateTime, nullable=False, default=datetime.utcnow)
    rule = Column(String(128), nullable=False, index=True)
    action = Column(String(32), nullable=True)   # EXECUTED|NOT_APPLICABLE|ERROR
    message = Column(Text, nullable=True)
    raw_output = Column(Text, nullable=True)
    exit_code = Column(Integer, nullable=True)
    duration_ms = Column(Integer, nullable=True)
    operator = Column(String(64), default="admin")
    scan_before = Column(String(32), nullable=True)
    scan_after = Column(String(32), nullable=True)


class Exemption(Base):
    __tablename__ = "exemptions"

    id = Column(Integer, primary_key=True, autoincrement=True)
    rule = Column(String(128), nullable=False, unique=True, index=True)
    reason = Column(Text, nullable=False)
    expires_at = Column(DateTime, nullable=True)
    granted_by = Column(String(64), nullable=False, default="admin")
    granted_at = Column(DateTime, nullable=False, default=datetime.utcnow)
    is_active = Column(Boolean, nullable=False, default=True)
    revoked_at = Column(DateTime, nullable=True)


class AuditLog(Base):
    __tablename__ = "audit_log"

    id = Column(Integer, primary_key=True, autoincrement=True)
    ts = Column(DateTime, nullable=False, default=datetime.utcnow, index=True)
    action = Column(String(64), nullable=False)   # SCAN_RUN|FIX_APPLIED|EXEMPTION_GRANTED|...
    target = Column(String(256), nullable=True)   # rule name or session id
    detail_json = Column(Text, nullable=True)
    operator = Column(String(64), default="admin")
    source_ip = Column(String(64), default="127.0.0.1")


class Schedule(Base):
    __tablename__ = "schedules"

    id = Column(Integer, primary_key=True, autoincrement=True)
    name = Column(String(128), nullable=False)
    cron_expr = Column(String(64), nullable=False)   # e.g. "0 6 * * *"
    filter_json = Column(Text, nullable=True)        # null = all rules
    enabled = Column(Boolean, nullable=False, default=True)
    last_run = Column(DateTime, nullable=True)
    next_run = Column(DateTime, nullable=True)
    created_at = Column(DateTime, nullable=False, default=datetime.utcnow)


class DeviceSnapshot(Base):
    __tablename__ = "device_snapshots"

    id = Column(Integer, primary_key=True, autoincrement=True)
    captured_at = Column(DateTime, nullable=False, default=datetime.utcnow, index=True)
    os_version = Column(String(32), nullable=True)
    build_version = Column(String(32), nullable=True)
    sip_enabled = Column(Boolean, nullable=True)
    filevault_on = Column(Boolean, nullable=True)
    gatekeeper_on = Column(Boolean, nullable=True)
    firewall_on = Column(Boolean, nullable=True)
    secure_boot = Column(String(32), nullable=True)
    hardware_model = Column(String(64), nullable=True)
    serial_number = Column(String(32), nullable=True)
    uptime_secs = Column(Integer, nullable=True)
    raw_json = Column(Text, nullable=True)


class MdmProfile(Base):
    __tablename__ = "mdm_profiles"

    id = Column(Integer, primary_key=True, autoincrement=True)
    profile_id = Column(String(128), nullable=False, unique=True)
    display_name = Column(String(256), nullable=True)
    standard = Column(String(32), nullable=True)
    is_installed = Column(Boolean, nullable=True)
    last_checked = Column(DateTime, nullable=True)
    mobileconfig_path = Column(Text, nullable=True)
    rules_json = Column(Text, nullable=True)   # JSON list of rule names this profile covers
