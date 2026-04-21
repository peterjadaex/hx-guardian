"""
Settings router — 2FA management endpoints.

GET  /api/settings/2fa/status      → current 2FA state
POST /api/settings/2fa/setup/init  → begin setup (returns provisioning URI)
POST /api/settings/2fa/setup/confirm → finalize setup with OTP
POST /api/settings/2fa/view-qr     → re-display QR for current key (requires OTP)
POST /api/settings/2fa/verify      → verify OTP, issue session token
POST /api/settings/2fa/disable     → disable 2FA (requires OTP)
"""
from datetime import datetime
from typing import Optional

from fastapi import APIRouter, Depends, HTTPException
from pydantic import BaseModel
from sqlalchemy.orm import Session

import core.audit as audit
from core.database import get_db
from core.models import TwoFactorConfig
from core.two_factor import (
    check_2fa_session,
    create_2fa_session,
    decrypt_secret,
    encrypt_secret,
    generate_secret,
    make_provisioning_uri,
    verify_otp,
)

router = APIRouter(prefix="/api/settings", tags=["settings"])


# ─── Pydantic models ──────────────────────────────────────────────────────────

class OtpBody(BaseModel):
    otp: Optional[str] = None


# ─── Helper ───────────────────────────────────────────────────────────────────

def _get_or_create_config(db: Session) -> TwoFactorConfig:
    """Return the singleton TwoFactorConfig row, creating it if absent."""
    cfg = db.query(TwoFactorConfig).first()
    if not cfg:
        cfg = TwoFactorConfig()
        db.add(cfg)
        db.commit()
        db.refresh(cfg)
    return cfg


# ─── Endpoints ────────────────────────────────────────────────────────────────

@router.get("/2fa/status")
def get_2fa_status(db: Session = Depends(get_db)):
    """Return current 2FA configuration state — never exposes secret material."""
    cfg = _get_or_create_config(db)
    return {
        "enabled": cfg.is_enabled,
        "has_pending": cfg.pending_encrypted_secret is not None,
        "last_verified_at": cfg.last_verified_at.isoformat() if cfg.last_verified_at else None,
        "enabled_at": cfg.enabled_at.isoformat() if cfg.enabled_at else None,
    }


@router.post("/2fa/setup/init")
def setup_init(body: OtpBody, db: Session = Depends(get_db)):
    """
    Begin the 2FA setup flow.

    First-time setup: no OTP required — returns provisioning URI immediately.
    Re-keying (2FA already enabled): caller must supply a valid current OTP.
    The raw secret is NEVER returned; only the otpauth:// URI for QR rendering.
    """
    cfg = _get_or_create_config(db)

    if cfg.is_enabled:
        # Changing the key requires proof of the current key
        if not body.otp:
            raise HTTPException(status_code=403, detail="Current OTP required to change the 2FA key")
        try:
            current_secret = decrypt_secret(cfg.encrypted_secret)
        except Exception:
            raise HTTPException(status_code=500, detail="Failed to read current secret")
        if not verify_otp(current_secret, body.otp):
            raise HTTPException(status_code=403, detail="Invalid OTP")

    new_secret = generate_secret()
    cfg.pending_encrypted_secret = encrypt_secret(new_secret)
    db.commit()

    action = audit.TWO_FA_REKEYED if cfg.is_enabled else audit.TWO_FA_SETUP_INITIATED
    audit.log_action(db, action, "2fa")

    return {"provisioning_uri": make_provisioning_uri(new_secret)}


@router.post("/2fa/setup/confirm")
def setup_confirm(body: OtpBody, db: Session = Depends(get_db)):
    """
    Finalize 2FA setup by verifying the OTP from the authenticator app.
    Promotes the pending secret to the active secret.
    """
    if not body.otp:
        raise HTTPException(status_code=422, detail="OTP is required")

    cfg = _get_or_create_config(db)
    if not cfg.pending_encrypted_secret:
        raise HTTPException(status_code=400, detail="No pending setup found. Call /setup/init first.")

    try:
        pending_secret = decrypt_secret(cfg.pending_encrypted_secret)
    except Exception:
        raise HTTPException(status_code=500, detail="Failed to read pending secret")

    if not verify_otp(pending_secret, body.otp):
        raise HTTPException(status_code=403, detail="Invalid OTP — check your authenticator app clock sync")

    cfg.encrypted_secret = cfg.pending_encrypted_secret
    cfg.pending_encrypted_secret = None
    cfg.is_enabled = True
    cfg.enabled_at = datetime.utcnow()
    db.commit()

    audit.log_action(db, audit.TWO_FA_ENABLED, "2fa")
    return {"success": True}


@router.post("/2fa/view-qr")
def view_qr(body: OtpBody, db: Session = Depends(get_db)):
    """
    Re-display the QR code for the current active key.
    Requires a valid OTP — allows adding to a new device without changing the key.
    """
    if not body.otp:
        raise HTTPException(status_code=422, detail="OTP is required")

    cfg = _get_or_create_config(db)
    if not cfg.is_enabled or not cfg.encrypted_secret:
        raise HTTPException(status_code=400, detail="2FA is not enabled")

    try:
        current_secret = decrypt_secret(cfg.encrypted_secret)
    except Exception:
        raise HTTPException(status_code=500, detail="Failed to read secret")

    if not verify_otp(current_secret, body.otp):
        raise HTTPException(status_code=403, detail="Invalid OTP")

    cfg.last_verified_at = datetime.utcnow()
    db.commit()

    audit.log_action(db, audit.TWO_FA_VERIFIED, "2fa", {"action": "view_qr"})
    return {"provisioning_uri": make_provisioning_uri(current_secret)}


@router.post("/2fa/verify")
def verify(body: OtpBody, db: Session = Depends(get_db)):
    """
    Verify a TOTP code against the active secret.
    On success, issues a short-lived (10 min) session token for 2FA-gated endpoints.
    """
    if not body.otp:
        raise HTTPException(status_code=422, detail="OTP is required")

    cfg = _get_or_create_config(db)
    if not cfg.is_enabled or not cfg.encrypted_secret:
        raise HTTPException(status_code=400, detail="2FA is not enabled")

    try:
        current_secret = decrypt_secret(cfg.encrypted_secret)
    except Exception:
        raise HTTPException(status_code=500, detail="Failed to read secret")

    if not verify_otp(current_secret, body.otp):
        return {"valid": False, "session_token": None}

    cfg.last_verified_at = datetime.utcnow()
    db.commit()

    session_token = create_2fa_session()
    audit.log_action(db, audit.TWO_FA_VERIFIED, "2fa")
    return {"valid": True, "session_token": session_token}


@router.post("/2fa/disable")
def disable_2fa(body: OtpBody, db: Session = Depends(get_db)):
    """Disable 2FA after verifying the current OTP."""
    if not body.otp:
        raise HTTPException(status_code=422, detail="OTP is required")

    cfg = _get_or_create_config(db)
    if not cfg.is_enabled or not cfg.encrypted_secret:
        raise HTTPException(status_code=400, detail="2FA is not enabled")

    try:
        current_secret = decrypt_secret(cfg.encrypted_secret)
    except Exception:
        raise HTTPException(status_code=500, detail="Failed to read secret")

    if not verify_otp(current_secret, body.otp):
        raise HTTPException(status_code=403, detail="Invalid OTP")

    cfg.encrypted_secret = None
    cfg.pending_encrypted_secret = None
    cfg.is_enabled = False
    cfg.enabled_at = None
    db.commit()

    audit.log_action(db, audit.TWO_FA_DISABLED, "2fa")
    return {"success": True}
