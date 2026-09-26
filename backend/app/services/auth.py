"""Local authentication for LocalIQ (SQLite-backed, no external IdP).

Design constraints for a self-hosted hackathon demo:
  * Passwords are never stored in plain text: PBKDF2-HMAC-SHA256, per-user salt.
  * Sessions are opaque random tokens; only a SHA-256 hash of the token is
    persisted, so a leaked database cannot be replayed.
  * No new third-party dependency: stdlib ``hashlib``/``secrets``/``hmac`` only.
"""

from __future__ import annotations

import base64
import hashlib
import hmac
import secrets
from datetime import datetime, timedelta

from fastapi import Depends, HTTPException, status
from fastapi.security import HTTPAuthorizationCredentials, HTTPBearer
from sqlmodel import Session, select

from app.config import get_settings
from app.database import get_session
from app.models import User
from app.timeutil import utcnow

__all__ = [
    "utcnow",
    "hash_password",
    "verify_password",
    "create_session",
    "revoke_session",
    "resolve_user",
    "get_current_user",
    "get_current_user_optional",
]

PBKDF2_ITERATIONS = 200_000
SALT_BYTES = 16
TOKEN_BYTES = 32

_bearer = HTTPBearer(auto_error=False)


# ---------------------------------------------------------------------------
# Password hashing
# ---------------------------------------------------------------------------


def hash_password(password: str) -> str:
    """Return ``pbkdf2_sha256$iterations$salt$hash`` for storage."""
    salt = secrets.token_bytes(SALT_BYTES)
    digest = hashlib.pbkdf2_hmac("sha256", password.encode("utf-8"), salt, PBKDF2_ITERATIONS)
    return "$".join(
        [
            "pbkdf2_sha256",
            str(PBKDF2_ITERATIONS),
            base64.b64encode(salt).decode("ascii"),
            base64.b64encode(digest).decode("ascii"),
        ]
    )


def verify_password(password: str, stored: str) -> bool:
    """Constant-time password check. Returns False for malformed records."""
    try:
        algorithm, iterations, salt_b64, hash_b64 = stored.split("$")
        if algorithm != "pbkdf2_sha256":
            return False
        salt = base64.b64decode(salt_b64)
        expected = base64.b64decode(hash_b64)
        candidate = hashlib.pbkdf2_hmac("sha256", password.encode("utf-8"), salt, int(iterations))
    except (ValueError, TypeError):
        return False
    return hmac.compare_digest(candidate, expected)


# ---------------------------------------------------------------------------
# Session tokens
# ---------------------------------------------------------------------------


def _token_hash(token: str) -> str:
    """Hash a session token for storage (salted with the app secret)."""
    settings = get_settings()
    return hmac.new(
        settings.auth_secret_key.encode("utf-8"), token.encode("utf-8"), hashlib.sha256
    ).hexdigest()


def create_session(user_id: int, session: Session) -> tuple[str, datetime, datetime]:
    """Create a persisted session. Returns (token, expires_at, created_at)."""
    now = utcnow()
    expires_at = now + timedelta(minutes=get_settings().auth_token_ttl_minutes)
    token = secrets.token_urlsafe(TOKEN_BYTES)

    from app.models import UserSession  # local import to avoid cycles

    session.add(
        UserSession(
            user_id=user_id,
            token_hash=_token_hash(token),
            created_at=now,
            expires_at=expires_at,
        )
    )
    session.commit()
    return token, expires_at, now


def revoke_session(token: str, session: Session) -> None:
    """Delete a session row if it exists."""
    from app.models import UserSession

    row = session.exec(
        select(UserSession).where(UserSession.token_hash == _token_hash(token))
    ).first()
    if row:
        session.delete(row)
        session.commit()


def resolve_user(token: str, session: Session) -> User | None:
    """Look up the active user for a bearer token, or None."""
    from app.models import UserSession

    row = session.exec(
        select(UserSession).where(UserSession.token_hash == _token_hash(token))
    ).first()
    if not row:
        return None
    if row.expires_at < utcnow():
        session.delete(row)
        session.commit()
        return None
    return session.get(User, row.user_id)


# ---------------------------------------------------------------------------
# FastAPI dependencies
# ---------------------------------------------------------------------------


def get_current_user_optional(
    credentials: HTTPAuthorizationCredentials | None = Depends(_bearer),
    session: Session = Depends(get_session),
) -> User | None:
    """Return the authenticated user, or None for anonymous requests."""
    if credentials is None or not credentials.credentials:
        return None
    return resolve_user(credentials.credentials, session)


def get_current_user(
    user: User | None = Depends(get_current_user_optional),
) -> User:
    """Require a valid session token (HTTP 401 otherwise)."""
    if user is None:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Not authenticated. Login via POST /api/v1/auth/login.",
            headers={"WWW-Authenticate": "Bearer"},
        )
    return user
