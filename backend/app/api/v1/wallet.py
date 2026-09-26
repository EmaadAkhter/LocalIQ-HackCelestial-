"""Experience Wallet & Passport endpoints (PRD 4.9).

* ``POST /me/wallet/log`` — mark an experience done; updates stats + badges.
* ``GET  /me/wallet`` — the Passport (stats, badges, timeline, map pins).
* ``GET  /me/wallet/timeline`` — chronological completed experiences.
* ``GET  /me/wallet/badges`` — earned + available badges.
* ``GET  /me/wallet/share`` — a shareable "My [City] Month" summary.
"""

from __future__ import annotations

import logging

from fastapi import APIRouter, Depends, HTTPException, Request, Response
from fastapi import status as http_status
from sqlmodel import Session

from app.database import get_session
from app.models import Experience, ExperienceWallet, User
from app.rate_limit import PUBLIC_LIMIT, limiter
from app.schemas import (
    WalletBadge,
    WalletLogRequest,
    WalletLogResponse,
    WalletPassport,
    WalletShareSummary,
    WalletStats,
    WalletTimelineItem,
)
from app.services import wallet
from app.services.auth import get_current_user

logger = logging.getLogger(__name__)
router = APIRouter()


def _wallet_stats(row: ExperienceWallet) -> WalletStats:
    return WalletStats(
        total_experiences=row.total_experiences,
        hidden_gem_count=row.hidden_gem_count,
        total_spent_inr=row.total_spent_inr,
        total_duration_min=row.total_duration_min,
        categories=dict(row.categories_json or {}),
        cities=dict(row.cities_visited_json or {}),
    )


@router.post(
    "/me/wallet/log",
    response_model=WalletLogResponse,
    status_code=http_status.HTTP_201_CREATED,
    summary="Mark an experience as done",
)
@limiter.limit(PUBLIC_LIMIT)
def log_experience(
    request: Request,
    response: Response,
    payload: WalletLogRequest,
    session: Session = Depends(get_session),
    current_user: User = Depends(get_current_user),
):
    experience = session.get(Experience, payload.experience_id)
    if experience is None:
        raise HTTPException(status_code=404, detail="Experience not found")

    result = wallet.log_experience(
        session,
        current_user,
        experience,
        rating=payload.rating,
        notes=payload.notes,
        context=payload.context,
    )
    log = result["log"]
    return WalletLogResponse(
        experience_id=experience.id or 0,
        completed_at=log.completed_at,
        new_badges=[WalletBadge(**badge) for badge in result["new_badges"]],
        stats=_wallet_stats(result["wallet"]),
    )


@router.get("/me/wallet", response_model=WalletPassport, summary="My experience passport")
@limiter.limit(PUBLIC_LIMIT)
def get_wallet(
    request: Request,
    response: Response,
    session: Session = Depends(get_session),
    current_user: User = Depends(get_current_user),
):
    return WalletPassport(**wallet.get_passport(session, current_user))


@router.get(
    "/me/wallet/timeline",
    response_model=list[WalletTimelineItem],
    summary="My completed experiences, newest first",
)
@limiter.limit(PUBLIC_LIMIT)
def get_timeline(
    request: Request,
    response: Response,
    limit: int = 50,
    session: Session = Depends(get_session),
    current_user: User = Depends(get_current_user),
):
    rows = wallet.timeline(session, current_user, limit=max(1, min(limit, 200)))
    return [WalletTimelineItem(**row) for row in rows]


@router.get(
    "/me/wallet/badges",
    response_model=list[WalletBadge],
    summary="Earned and available badges",
)
@limiter.limit(PUBLIC_LIMIT)
def get_badges(
    request: Request,
    response: Response,
    session: Session = Depends(get_session),
    current_user: User = Depends(get_current_user),
):
    passport = wallet.get_passport(session, current_user, timeline_limit=1)
    return [WalletBadge(**badge) for badge in passport["badges"]]


@router.get(
    "/me/wallet/share",
    response_model=WalletShareSummary,
    summary="Shareable 'My Month' summary",
)
@limiter.limit(PUBLIC_LIMIT)
def share_wallet(
    request: Request,
    response: Response,
    month: str | None = None,
    session: Session = Depends(get_session),
    current_user: User = Depends(get_current_user),
):
    return WalletShareSummary(**wallet.share_summary(session, current_user, month=month))
