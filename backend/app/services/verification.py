"""Email verification tokens.

The rules live here rather than in the router so they are testable without HTTP:
a token is single-use, expires after ``email_verification_ttl_hours``, and only
the newest one is valid (issuing invalidates the rest). Resends are throttled by
``email_resend_cooldown_seconds``.
"""

from __future__ import annotations

import logging
import secrets
from datetime import datetime, timedelta

from sqlmodel import Session, select

from app.config import get_settings
from app.models import EmailVerificationToken, User
from app.services.auth import hash_token, utcnow

logger = logging.getLogger(__name__)

TOKEN_BYTES = 32


def issue(session: Session, user: User) -> str:
    """Create a fresh verification token and invalidate any earlier one.

    Returns the raw token (only its hash is persisted).
    """
    if user.id is None:  # pragma: no cover - users are always persisted first
        raise ValueError("user must be persisted before issuing a token")

    outstanding = session.exec(
        select(EmailVerificationToken).where(
            EmailVerificationToken.user_id == user.id
        )
    ).all()
    for row in outstanding:
        session.delete(row)

    now = utcnow()
    token = secrets.token_urlsafe(TOKEN_BYTES)
    session.add(
        EmailVerificationToken(
            user_id=user.id,
            token_hash=hash_token(token),
            expires_at=now + timedelta(hours=get_settings().email_verification_ttl_hours),
        )
    )
    user.email_verification_sent_at = now
    session.add(user)
    session.commit()
    return token


def consume(session: Session, token: str) -> User | None:
    """Redeem ``token`` and mark the user verified, or return None."""
    if not token:
        return None

    row = session.exec(
        select(EmailVerificationToken).where(
            EmailVerificationToken.token_hash == hash_token(token)
        )
    ).first()
    if row is None or row.consumed_at is not None:
        return None

    now = utcnow()
    if row.expires_at < now:
        session.delete(row)
        session.commit()
        return None

    user = session.get(User, row.user_id)
    if user is None:
        session.delete(row)
        session.commit()
        return None

    row.consumed_at = now
    user.email_verified = True
    user.email_verified_at = now
    session.add(row)
    session.add(user)
    session.commit()
    session.refresh(user)
    logger.info("Email verified for user id=%s", user.id)
    return user


def mark_verified(session: Session, user: User) -> User:
    """Mark an address verified without a token.

    Used for providers (Google) that already guarantee the address, and called
    when a user signs in with a provider after registering with a password.
    """
    if user.email_verified:
        return user
    user.email_verified = True
    user.email_verified_at = utcnow()
    session.add(user)
    session.commit()
    session.refresh(user)
    return user


def seconds_until_resend(user: User, *, now: datetime | None = None) -> int:
    """Non-zero while the resend cooldown is still active."""
    sent_at = user.email_verification_sent_at
    if sent_at is None:
        return 0
    ready_at = sent_at + timedelta(seconds=get_settings().email_resend_cooldown_seconds)
    remaining = (ready_at - (now or utcnow())).total_seconds()
    return max(0, int(remaining))


def can_resend(user: User, *, now: datetime | None = None) -> bool:
    return seconds_until_resend(user, now=now) == 0
