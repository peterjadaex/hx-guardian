"""
SQLAlchemy ORM models for hxguardian.db
"""
from datetime import datetime
from typing import Optional
from sqlalchemy import (
    Boolean, Column, Float, ForeignKey, Index, Integer, String, Text, DateTime
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


class ShellExecLog(Base):
    __tablename__ = "shell_exec_log"

    id = Column(Integer, primary_key=True, autoincrement=True)
    ts = Column(DateTime, nullable=False, default=datetime.utcnow, index=True)
    source = Column(String(16), nullable=False, index=True)   # 'log_stream' | 'history'
    pid = Column(Integer, nullable=True)
    ppid = Column(Integer, nullable=True)
    user = Column(String(64), nullable=True)
    process_path = Column(String(512), nullable=True)
    command = Column(Text, nullable=True)          # populated by history rows
    event_message = Column(Text, nullable=True)    # populated by log_stream rows
    subsystem = Column(String(128), nullable=True)
    raw_json = Column(Text, nullable=True)         # truncated to 2KB by writer

    __table_args__ = (
        Index("ix_shell_exec_log_source_ts", "source", "ts"),
    )


class ShellHistoryCursor(Base):
    """Per-file ingest cursor for the shell history tailer. Persisting (inode,
    offset) means a restart resumes where we left off, instead of re-seeding at
    EOF and losing the window between daemon stop and next start. First-seen
    files (no row here) are ingested from offset 0 so pre-install history
    becomes visible too."""
    __tablename__ = "shell_history_cursor"

    path = Column(String(512), primary_key=True)
    inode = Column(Integer, nullable=True)
    offset = Column(Integer, nullable=False, default=0)
    format = Column(String(16), nullable=False, default="plain")
    updated_at = Column(DateTime, nullable=False, default=datetime.utcnow)


class BiometricEvent(Base):
    """Touch ID / LocalAuthentication / passkey events captured from the macOS
    unified log. event_class is a best-effort classification from the event
    message; unknown shapes land in OTHER so we never silently drop data."""
    __tablename__ = "biometric_events"

    id = Column(Integer, primary_key=True, autoincrement=True)
    ts = Column(DateTime, nullable=False, default=datetime.utcnow, index=True)
    event_class = Column(String(16), nullable=False, index=True)  # REQUEST|SUCCESS|FAILURE|CANCELLED|TEARDOWN|OTHER
    subsystem = Column(String(128), nullable=True)
    category = Column(String(128), nullable=True)
    requesting_process = Column(String(512), nullable=True)  # processImagePath
    requesting_pid = Column(Integer, nullable=True)
    user_uid = Column(Integer, nullable=True)        # userID from event
    user = Column(String(64), nullable=True)         # resolved from uid
    console_user = Column(String(64), nullable=True) # /dev/console owner at capture time
    event_message = Column(Text, nullable=True)
    raw_json = Column(Text, nullable=True)           # truncated to 2KB

    __table_args__ = (
        Index("ix_biometric_events_class_ts", "event_class", "ts"),
    )


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


class TwoFactorConfig(Base):
    __tablename__ = "two_factor_config"

    id = Column(Integer, primary_key=True, autoincrement=True)
    encrypted_secret = Column(Text, nullable=True)          # active Fernet/XOR-encrypted TOTP secret
    pending_encrypted_secret = Column(Text, nullable=True)  # unconfirmed secret during setup flow
    is_enabled = Column(Boolean, nullable=False, default=False)
    enabled_at = Column(DateTime, nullable=True)
    last_verified_at = Column(DateTime, nullable=True)
    created_at = Column(DateTime, nullable=False, default=datetime.utcnow)


class UsbWhitelist(Base):
    __tablename__ = "usb_whitelist"

    id = Column(Integer, primary_key=True, autoincrement=True)
    name = Column(String(128), nullable=False)       # display label
    vendor = Column(String(128), nullable=True)      # manufacturer string
    product_id = Column(String(32), nullable=True)   # hex product ID (e.g. "0x12ab")
    serial = Column(String(128), nullable=True)      # serial number
    volume_uuid = Column(String(64), nullable=True)  # volume UUID for storage-specific whitelisting
    notes = Column(Text, nullable=True)
    added_by = Column(String(64), default="admin")
    added_at = Column(DateTime, nullable=False, default=datetime.utcnow)
