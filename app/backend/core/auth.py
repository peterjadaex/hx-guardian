"""
Session token authentication for the dashboard.
A random 32-byte token is generated at startup, printed to the terminal once,
and required as a Bearer token on all /api/* routes.
"""
import secrets
import logging
from fastapi import HTTPException, Security, status
from fastapi.security import HTTPBearer, HTTPAuthorizationCredentials

logger = logging.getLogger(__name__)

_token: str = ""
_bearer = HTTPBearer(auto_error=False)


def generate_token() -> str:
    global _token
    _token = secrets.token_hex(32)
    logger.info("=" * 60)
    logger.info("Dashboard session token (copy this):")
    logger.info("  %s", _token)
    logger.info("Open: http://127.0.0.1:8000")
    logger.info("=" * 60)
    return _token


def get_token() -> str:
    return _token


def verify_token(credentials: HTTPAuthorizationCredentials = Security(_bearer)) -> str:
    """FastAPI dependency — raises 401 if token missing or wrong."""
    if not credentials or credentials.credentials != _token:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Invalid or missing session token",
            headers={"WWW-Authenticate": "Bearer"},
        )
    return credentials.credentials
