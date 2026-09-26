"""Authentication API endpoints (local, SQLite-backed)."""

from __future__ import annotations

import base64
import json
import logging
import secrets
from datetime import timedelta

import httpx
from fastapi import APIRouter, BackgroundTasks, Depends, HTTPException, Request, Response
from fastapi import status as http_status
from sqlmodel import Session, select

from app.config import get_settings
from app.database import get_session
from app.models import User
from app.rate_limit import AUTH_LIMIT, limiter
from app.schemas import (
    ForgotPasswordRequest,
    GoogleAuthRequest,
    LoginRequest,
    RefreshRequest,
    RegisterRequest,
    TokenResponse,
    UserResponse,
    VerifyEmailRequest,
)
from app.services import email as email_service
from app.services import lockout, verification
from app.services.auth import (
    create_session_pair,
    get_current_user,
    hash_password,
    revoke_session,
    rotate_refresh,
    utcnow,
    verify_password,
)
from app.services.llm import get_client

logger = logging.getLogger(__name__)
router = APIRouter()

#: In-memory single-use password-reset tokens (dev/demo only). Maps token ->
#: (user_id, expires_at). A production build would persist these and email a link.
_RESET_TOKENS: dict[str, tuple[int, "object"]] = {}


def _normalize_email(email: str) -> str:
    return email.strip().lower()


def _queue_verification(
    background: BackgroundTasks, session: Session, user: User
) -> None:
    """Issue a verification token and email it without blocking the response.

    The send happens as a background task, so registration is not held up by the
    mail provider and a send failure can never fail the request.
    """
    token = verification.issue(session, user)
    background.add_task(
        email_service.send_verification_email,
        to=user.email,
        name=user.name,
        token=token,
    )


def _token_response(
    user: User, access_token: str, refresh_token: str, expires_at
) -> TokenResponse:
    """Build the flat token payload the Flutter client expects."""
    return TokenResponse(
        access_token=access_token,
        refresh_token=refresh_token,
        expires_in=max(0, int((expires_at - utcnow()).total_seconds())),
        user=UserResponse.model_validate(user),
    )


@router.post("/register", response_model=TokenResponse, status_code=http_status.HTTP_201_CREATED, summary="Register a local account")
@limiter.limit(AUTH_LIMIT)
def register(
    request: Request,
    response: Response,
    payload: RegisterRequest,
    background: BackgroundTasks,
    session: Session = Depends(get_session),
):
    """Create a local user and return a session token."""
    email = _normalize_email(payload.email)
    if "@" not in email or "." not in email.split("@")[-1]:
        raise HTTPException(status_code=400, detail="Enter a valid email address")
    existing = session.exec(select(User).where(User.email == email)).first()
    if existing:
        raise HTTPException(status_code=409, detail="An account with this email already exists")

    user = User(
        name=payload.name.strip(),
        email=email,
        password_hash=hash_password(payload.password),
    )
    session.add(user)
    session.commit()
    session.refresh(user)

    _queue_verification(background, session, user)
    token, refresh, expires_at, _ = create_session_pair(user.id, session)  # type: ignore[arg-type]
    logger.info("Registered user id=%s", user.id)
    return _token_response(user, token, refresh, expires_at)


@router.post("/login", response_model=TokenResponse, summary="Login")
@limiter.limit(AUTH_LIMIT)
def login(
    request: Request,
    response: Response,
    payload: LoginRequest,
    session: Session = Depends(get_session),
):
    """Verify credentials and issue a session token."""
    email = _normalize_email(payload.email)

    remaining = lockout.locked_for(email)
    if remaining > 0:
        minutes = max(1, remaining // 60)
        raise HTTPException(
            status_code=http_status.HTTP_403_FORBIDDEN,
            detail=f"Account temporarily locked. Try again in {minutes} minute(s).",
        )

    user = session.exec(select(User).where(User.email == email)).first()
    if not user or not verify_password(payload.password, user.password_hash):
        # Same message for both cases: do not leak which emails exist.
        lockout.record_failure(email)
        raise HTTPException(status_code=401, detail="Incorrect email or password")

    lockout.clear(email)
    token, refresh, expires_at, _ = create_session_pair(user.id, session)  # type: ignore[arg-type]
    logger.info("Login user id=%s", user.id)
    return _token_response(user, token, refresh, expires_at)


@router.post("/logout", status_code=http_status.HTTP_200_OK, summary="Logout (revoke session)")
def logout(
    request: Request,
    session: Session = Depends(get_session),
    current_user: User = Depends(get_current_user),
):
    """Revoke the caller's session token."""
    header = request.headers.get("Authorization", "")
    token = header[7:].strip() if header.lower().startswith("bearer ") else ""
    if token:
        revoke_session(token, session)
    logger.info("Logout user id=%s", current_user.id)
    return {"status": "logged_out"}


@router.get("/me", response_model=UserResponse, summary="Current user")
def me(current_user: User = Depends(get_current_user)):
    """Return the authenticated user."""
    return UserResponse.model_validate(current_user)


@router.get("/status", summary="Auth + optional AI/weather service status")
async def status(session: Session = Depends(get_session)):
    """Lightweight status for the frontend (never fails)."""
    llm = await get_client().health()
    return {
        "auth": "enabled",
        "local_db": True,
        "ollama": llm,
    }


# ---------------------------------------------------------------------------
# Token refresh
# ---------------------------------------------------------------------------


@router.post("/refresh", response_model=TokenResponse, summary="Exchange a refresh token")
@limiter.limit(AUTH_LIMIT)
def refresh(
    request: Request,
    response: Response,
    payload: RefreshRequest,
    session: Session = Depends(get_session),
):
    """Rotate a refresh token into a fresh access + refresh pair."""
    rotated = rotate_refresh(payload.refresh_token, session)
    if rotated is None:
        raise HTTPException(status_code=401, detail="Invalid or expired refresh token")
    (token, refresh_token, expires_at, _created), user_id = rotated
    user = session.get(User, user_id)
    if user is None:
        raise HTTPException(status_code=401, detail="Invalid or expired refresh token")
    return _token_response(user, token, refresh_token, expires_at)


# ---------------------------------------------------------------------------
# Guest + Google + password reset
# ---------------------------------------------------------------------------


@router.post("/guest", response_model=TokenResponse, summary="Continue as an anonymous guest")
@limiter.limit(AUTH_LIMIT)
def guest(
    request: Request,
    response: Response,
    session: Session = Depends(get_session),
):
    """Create a throwaway anonymous account and sign it in."""
    suffix = secrets.token_hex(4)
    user = User(
        name=f"Guest {suffix[:4].upper()}",
        email=f"guest-{suffix}@guest.localiq",
        password_hash=hash_password(secrets.token_urlsafe(24)),
        provider="guest",
        tier="guest",
        is_anonymous=True,
    )
    session.add(user)
    session.commit()
    session.refresh(user)
    token, refresh_token, expires_at, _ = create_session_pair(user.id, session)  # type: ignore[arg-type]
    logger.info("Guest user id=%s", user.id)
    return _token_response(user, token, refresh_token, expires_at)


def _decode_jwt_payload(token: str) -> dict | None:
    """Decode a JWT payload without verifying the signature (dev fallback)."""
    try:
        parts = token.split(".")
        if len(parts) < 2:
            return None
        padded = parts[1] + "=" * (-len(parts[1]) % 4)
        return json.loads(base64.urlsafe_b64decode(padded))
    except Exception:
        return None


async def _google_claims(id_token: str) -> dict | None:
    """Verify a Google ID token, or decode it unverified in non-production."""
    settings = get_settings()
    if settings.google_oauth_client_id:
        try:
            async with httpx.AsyncClient(timeout=10.0) as client:
                resp = await client.get(
                    "https://oauth2.googleapis.com/tokeninfo",
                    params={"id_token": id_token},
                )
                resp.raise_for_status()
                data = resp.json()
            if data.get("aud") != settings.google_oauth_client_id:
                return None
            return data
        except Exception as exc:
            logger.warning("Google token verification failed: %s", exc)
            return None
    if settings.app_env == "production":
        return None
    return _decode_jwt_payload(id_token)


@router.post("/google", response_model=TokenResponse, summary="Sign in with Google")
@limiter.limit(AUTH_LIMIT)
async def google_sign_in(
    request: Request,
    response: Response,
    payload: GoogleAuthRequest,
    background: BackgroundTasks,
    session: Session = Depends(get_session),
):
    """Verify a Google ID token and find-or-create the matching account."""
    claims = await _google_claims(payload.id_token)
    if not claims:
        raise HTTPException(status_code=401, detail="Invalid Google token")
    subject = str(claims.get("sub") or claims.get("email") or secrets.token_hex(6))
    email = _normalize_email(str(claims.get("email") or f"google-{subject}@google.localiq"))
    # Google states whether it has verified the address; trust that when present.
    provider_verified = str(claims.get("email_verified", "")).lower() == "true"

    user = session.exec(select(User).where(User.email == email)).first()
    if user is None:
        user = User(
            name=str(claims.get("name") or "Google User")[:80],
            email=email,
            password_hash=hash_password(secrets.token_urlsafe(24)),
            provider="google",
        )
        session.add(user)
        session.commit()
        session.refresh(user)
        if provider_verified:
            verification.mark_verified(session, user)
        else:
            _queue_verification(background, session, user)
    elif provider_verified and not user.email_verified:
        verification.mark_verified(session, user)

    token, refresh_token, expires_at, _ = create_session_pair(user.id, session)  # type: ignore[arg-type]
    logger.info("Google sign-in user id=%s", user.id)
    return _token_response(user, token, refresh_token, expires_at)


@router.post("/forgot-password", summary="Request a password reset")
@limiter.limit(AUTH_LIMIT)
def forgot_password(
    request: Request,
    response: Response,
    payload: ForgotPasswordRequest,
    background: BackgroundTasks,
    session: Session = Depends(get_session),
):
    """Always returns 200 so the endpoint cannot enumerate accounts.

    Emails a single-use reset link when the account exists. In non-production a
    ``dev_reset_token`` is also returned so the flow can be finished end to end
    without a mail provider.
    """
    email = _normalize_email(payload.email)
    user = session.exec(select(User).where(User.email == email)).first()
    body: dict[str, object] = {"status": "sent"}
    if user is not None:
        token = secrets.token_urlsafe(24)
        _RESET_TOKENS[token] = (user.id or 0, utcnow() + timedelta(minutes=30))
        background.add_task(
            email_service.send_password_reset_email,
            to=user.email,
            name=user.name,
            token=token,
        )
        if get_settings().app_env != "production":
            body["dev_reset_token"] = token
    return body


@router.post("/reset-password", summary="Complete a password reset")
@limiter.limit(AUTH_LIMIT)
def reset_password(
    request: Request,
    response: Response,
    payload: dict,
    session: Session = Depends(get_session),
):
    """Consume a dev reset token and set a new password."""
    token = str(payload.get("token") or "")
    new_password = str(payload.get("password") or "")
    entry = _RESET_TOKENS.pop(token, None)
    if entry is None:
        raise HTTPException(status_code=400, detail="Invalid or expired reset token")
    user_id, expires_at = entry
    if expires_at < utcnow():  # type: ignore[operator]
        raise HTTPException(status_code=400, detail="Invalid or expired reset token")
    if len(new_password) < 8:
        raise HTTPException(status_code=400, detail="Password must be at least 8 characters")
    user = session.get(User, user_id)
    if user is None:
        raise HTTPException(status_code=400, detail="Invalid or expired reset token")
    user.password_hash = hash_password(new_password)
    session.add(user)
    session.commit()
    return {"status": "password_updated"}


# ---------------------------------------------------------------------------
# Email verification
# ---------------------------------------------------------------------------


@router.post("/verify-email", summary="Confirm an email address")
@limiter.limit(AUTH_LIMIT)
def verify_email(
    request: Request,
    response: Response,
    payload: VerifyEmailRequest,
    session: Session = Depends(get_session),
):
    """Redeem a verification token and mark the account verified."""
    user = verification.consume(session, payload.token)
    if user is None:
        raise HTTPException(
            status_code=400, detail="Invalid or expired verification link"
        )
    return {
        "status": "verified",
        "email_verified": True,
        "user": UserResponse.model_validate(user),
    }


@router.post("/resend-verification", summary="Resend the verification email")
@limiter.limit(AUTH_LIMIT)
def resend_verification(
    request: Request,
    response: Response,
    background: BackgroundTasks,
    session: Session = Depends(get_session),
    current_user: User = Depends(get_current_user),
):
    """Re-send the verification link, subject to a short cooldown."""
    if current_user.email_verified:
        return {"status": "already_verified", "email_verified": True, "retry_after": 0}

    wait = verification.seconds_until_resend(current_user)
    if wait > 0:
        raise HTTPException(
            status_code=http_status.HTTP_429_TOO_MANY_REQUESTS,
            detail=f"Please wait {wait}s before requesting another email",
            headers={"Retry-After": str(wait)},
        )

    _queue_verification(background, session, current_user)
    return {"status": "sent", "email_verified": False, "retry_after": 0}
