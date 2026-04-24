"""
Two-factor authentication helpers — pure Python stdlib, no extra pip packages.

TOTP implementation follows RFC 6238 / RFC 4226 (HOTP).
Secret encryption uses SHA-256 CTR-mode XOR with a random key file (chmod 600).
"""
import base64
import hashlib
import hmac as _hmac
import logging
import os
import secrets
import struct
import sys
import time
from datetime import datetime, timedelta
from pathlib import Path
from typing import Optional
from urllib.parse import quote

from fastapi import Header, HTTPException

logger = logging.getLogger(__name__)

# ─── Key file path (same directory as the SQLite DB) ─────────────────────────

def _key_path() -> Path:
    if getattr(sys, "frozen", False):
        base = Path("/Library/Application Support/hxguardian/data")
    else:
        base = Path(__file__).parent.parent.parent / "data"
    return base / "hxg.key"


def _load_or_create_key() -> bytes:
    path = _key_path()
    path.parent.mkdir(parents=True, exist_ok=True)
    if path.exists():
        raw = path.read_bytes()
        if len(raw) == 32:
            return raw
        logger.warning("hxg.key has unexpected length %d, regenerating", len(raw))
    raw = os.urandom(32)
    path.write_bytes(raw)
    try:
        os.chmod(path, 0o600)
    except OSError as e:
        logger.warning("Could not chmod hxg.key: %s", e)
    logger.info("Created new encryption key at %s", path)
    return raw


# ─── Secret encryption (XOR-CTR with SHA-256 PRF) ────────────────────────────
# Fernet is used if the `cryptography` package happens to be importable
# (it may be installed as a transitive dependency).  Otherwise we fall back
# to our stdlib XOR-CTR implementation.

def _try_fernet():
    try:
        from cryptography.fernet import Fernet  # noqa
        return Fernet
    except ImportError:
        return None


def _xor_ctr(data: bytes, key: bytes, iv: bytes) -> bytes:
    """SHA-256 counter-mode XOR cipher (stream cipher, no auth tag)."""
    result = bytearray()
    for i in range(0, len(data), 32):
        block_key = hashlib.sha256(key + iv + i.to_bytes(4, "big")).digest()
        chunk = data[i : i + 32]
        result.extend(b ^ k for b, k in zip(chunk, block_key))
    return bytes(result)


def encrypt_secret(plain: str) -> str:
    """Encrypt a TOTP secret string; returns a base64-encoded token."""
    Fernet = _try_fernet()
    raw_key = _load_or_create_key()
    if Fernet:
        import base64 as _b64
        fernet_key = _b64.urlsafe_b64encode(raw_key)
        return Fernet(fernet_key).encrypt(plain.encode()).decode()
    iv = os.urandom(16)
    ct = _xor_ctr(plain.encode(), raw_key, iv)
    return base64.b64encode(iv + ct).decode()


def decrypt_secret(token: str) -> str:
    """Decrypt a token produced by encrypt_secret."""
    Fernet = _try_fernet()
    raw_key = _load_or_create_key()
    if Fernet:
        import base64 as _b64
        fernet_key = _b64.urlsafe_b64encode(raw_key)
        return Fernet(fernet_key).decrypt(token.encode()).decode()
    data = base64.b64decode(token)
    iv, ct = data[:16], data[16:]
    return _xor_ctr(ct, raw_key, iv).decode()


# ─── TOTP (RFC 6238 / RFC 4226) ──────────────────────────────────────────────

def generate_secret() -> str:
    """Return a new random base32-encoded TOTP secret (160-bit)."""
    return base64.b32encode(os.urandom(20)).decode()


def _hotp(key: bytes, counter: int) -> str:
    """HOTP value as a zero-padded 6-digit string."""
    msg = struct.pack(">Q", counter)
    h = _hmac.new(key, msg, hashlib.sha1).digest()
    offset = h[-1] & 0x0F
    code = struct.unpack(">I", h[offset : offset + 4])[0] & 0x7FFFFFFF
    return str(code % 1_000_000).zfill(6)


def _decode_secret(secret: str) -> bytes:
    s = secret.upper().strip()
    # Add padding if needed
    pad = (8 - len(s) % 8) % 8
    return base64.b32decode(s + "=" * pad)


def verify_otp(secret: str, otp: str) -> bool:
    """Verify a 6-digit TOTP code with ±1 window tolerance."""
    if not otp or len(otp) != 6 or not otp.isdigit():
        return False
    try:
        key = _decode_secret(secret)
    except Exception:
        return False
    t = int(time.time()) // 30
    return any(_hotp(key, t + i) == otp for i in (-1, 0, 1))


def make_provisioning_uri(secret: str, label: str = "HX-Guardian") -> str:
    """Return an otpauth:// URI suitable for QR code rendering."""
    encoded_label = quote(label, safe="")
    return (
        f"otpauth://totp/{encoded_label}"
        f"?secret={secret}"
        f"&issuer=HX-Guardian"
        f"&algorithm=SHA1"
        f"&digits=6"
        f"&period=30"
    )


# ─── In-memory 2FA session store ─────────────────────────────────────────────
# After a successful OTP verification, a short-lived session token is issued.
# Future endpoints can import `require_2fa` as a FastAPI Depends() to enforce
# that the caller has recently verified their 2FA.

_SESSION_TTL = timedelta(minutes=10)
_sessions: dict[str, datetime] = {}


def _purge_expired() -> None:
    now = datetime.utcnow()
    expired = [k for k, exp in _sessions.items() if exp < now]
    for k in expired:
        del _sessions[k]


def create_2fa_session() -> str:
    """Return a new 10-minute 2FA session token."""
    _purge_expired()
    token = secrets.token_hex(16)
    _sessions[token] = datetime.utcnow() + _SESSION_TTL
    return token


def check_2fa_session(token: Optional[str]) -> bool:
    """Return True if the token exists and has not expired."""
    if not token:
        return False
    _purge_expired()
    return token in _sessions


# ─── FastAPI dependency ───────────────────────────────────────────────────────

def require_2fa(x_2fa_token: Optional[str] = Header(None)) -> None:
    """
    FastAPI Depends()-able guard for 2FA-protected endpoints.

    FastAPI extracts the X-2FA-Token request header automatically
    (underscore→hyphen, case-insensitive).  A valid session token is
    obtained by calling POST /api/settings/2fa/verify with a live OTP.

    Usage:
        from core.two_factor import require_2fa
        from fastapi import Depends

        @router.post("/sensitive")
        def sensitive_action(_: None = Depends(require_2fa)): ...

    If 2FA is not configured, this guard is a no-op — but writes a
    ``GATED_ACTION_UNPROTECTED`` audit entry so the admin can see that a gated
    action ran without TOTP protection. This surfaces the "admin hasn't
    enrolled 2FA yet" state in the dashboard instead of hiding it.
    """
    try:
        from core.database import SessionLocal
        from core.models import TwoFactorConfig
        db = SessionLocal()
        try:
            cfg = db.query(TwoFactorConfig).first()
        finally:
            db.close()
    except Exception:
        return  # DB not ready yet — pass through
    if cfg and cfg.is_enabled:
        if not check_2fa_session(x_2fa_token):
            raise HTTPException(
                status_code=403,
                detail="2FA verification required. POST /api/settings/2fa/verify first.",
            )
        return

    # 2FA not enrolled / disabled. Allow the action (current design is opt-in
    # per §6.3 of the airgap runbook) but record it so the admin knows.
    try:
        from core.database import SessionLocal
        import core.audit as audit
        db = SessionLocal()
        try:
            audit.log_action(
                db,
                audit.GATED_ACTION_UNPROTECTED,
                target=None,
                detail={"reason": "2FA not enrolled — gated action ran without TOTP"},
            )
        finally:
            db.close()
    except Exception:
        logger.exception("Failed to log GATED_ACTION_UNPROTECTED audit entry")
