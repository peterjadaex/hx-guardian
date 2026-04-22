"""
Audit log writer — records every operator action to the audit_log table.
"""
import json
import logging
from datetime import datetime
from typing import Optional

from sqlalchemy.orm import Session

from core.models import AuditLog

logger = logging.getLogger(__name__)

# Action constants
SCAN_RUN = "SCAN_RUN"
SCAN_COMPLETE = "SCAN_COMPLETE"
FIX_APPLIED = "FIX_APPLIED"
FIX_UNDONE = "FIX_UNDONE"
EXEMPTION_GRANTED = "EXEMPTION_GRANTED"
EXEMPTION_REVOKED = "EXEMPTION_REVOKED"
SCHEDULE_CREATED = "SCHEDULE_CREATED"
SCHEDULE_DELETED = "SCHEDULE_DELETED"
SCHEDULE_TRIGGERED = "SCHEDULE_TRIGGERED"
REPORT_GENERATED = "REPORT_GENERATED"
DEVICE_CHECKED = "DEVICE_CHECKED"
PREFLIGHT_RUN = "PREFLIGHT_RUN"
USB_UNAUTHORIZED_DEVICE = "USB_UNAUTHORIZED_DEVICE"
TWO_FA_SETUP_INITIATED = "TWO_FA_SETUP_INITIATED"
TWO_FA_REKEYED = "TWO_FA_REKEYED"
TWO_FA_ENABLED = "TWO_FA_ENABLED"
TWO_FA_DISABLED = "TWO_FA_DISABLED"
TWO_FA_VERIFIED = "TWO_FA_VERIFIED"
PROFILE_INSTALLED = "PROFILE_INSTALLED"
PROFILE_INSTALL_FAILED = "PROFILE_INSTALL_FAILED"


def log_action(
    db: Session,
    action: str,
    target: Optional[str] = None,
    detail: Optional[dict] = None,
    operator: str = "admin",
    source_ip: str = "127.0.0.1",
) -> None:
    """Write an audit log entry. Commits immediately."""
    try:
        entry = AuditLog(
            ts=datetime.utcnow(),
            action=action,
            target=target,
            detail_json=json.dumps(detail) if detail else None,
            operator=operator,
            source_ip=source_ip,
        )
        db.add(entry)
        db.commit()
    except Exception as exc:
        logger.error("Failed to write audit log: %s", exc)
        db.rollback()
