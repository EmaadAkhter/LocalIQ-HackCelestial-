"""Authentication API endpoints (local, SQLite-backed)."""

from __future__ import annotations

import logging

from fastapi import APIRouter, Depends, HTTPException, Request, Response
from fastapi import status as http_status
from sqlmodel import Session, select

from app.database import get_session
from app.models import User
from app.rate_limit import AUTH_LIMIT, limiter
from app.schemas import LoginRequest, RegisterRequest, TokenResponse, UserResponse
from app.services import lockout
from app.services.auth import (
    create_session,
    utcnow,
    get_current_user,
    hash_password,
    revoke_session,
    verify_password,
)
from app.services.llm import get_client

logger = logging.getLogger(__name__)
router = APIRouter()


def _normalize_email(email: str) -> str:
    return email.strip().lower()


@router.post("/register", response_model=TokenResponse, status_code=http_status.HTTP_201_CREATED, summary="Register a local account")
@limiter.limit(AUTH_LIMIT)
def register(
    request: Request,
    response: Response,
    payload: RegisterRequest,
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

    token, expires_at, _ = create_session(user.id, session)  # type: ignore[arg-type]
    logger.info("Registered user id=%s", user.id)
    return TokenResponse(
        access_token=token,
        expires_in=int((expires_at - utcnow()).total_seconds()),
        user=UserResponse.model_validate(user),
    )


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
    token, expires_at, _ = create_session(user.id, session)  # type: ignore[arg-type]
    logger.info("Login user id=%s", user.id)
    return TokenResponse(
        access_token=token,
        expires_in=int((expires_at - utcnow()).total_seconds()),
        user=UserResponse.model_validate(user),
    )


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
