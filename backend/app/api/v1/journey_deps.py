"""Shared helpers for the PRD v2 journey routers.

Trust tier lives on :class:`app.models_prd.GuideProfile` for guides and is
derived for travellers: a traveller's simulated verification tier is stored on
their profile row when present, otherwise it defaults to ``basic`` so existing
users are not locked out of the whole app.
"""

from __future__ import annotations

from typing import Optional

from fastapi import Depends, Header, HTTPException, status
from sqlmodel import Session, select

from app.database import get_session
from app.models import Experience, Guide, User
from app.models_prd import GuideProfile
from app.services import journey_rules as rules


def user_tier(session: Session, user_id: int) -> str:
    """Simulated trust tier for a traveller.

    Stored on the user row (``users.trust_tier``) and raised only by the
    simulated verification endpoint. A user who also happens to be a verified
    guide inherits the guide's tier, since guide verification is stricter.
    """
    user = session.get(User, user_id)
    if user is not None and getattr(user, "trust_tier", None):
        tier = user.trust_tier
        if tier == "basic":
            profile = session.exec(
                select(GuideProfile).where(GuideProfile.user_id == user_id)
            ).first()
            if profile and profile.verification_status == "verified":
                return profile.verification_tier
        return tier
    return "basic"


def guide_profile(session: Session, guide_id: int) -> GuideProfile:
    profile = session.exec(
        select(GuideProfile).where(GuideProfile.guide_id == guide_id)
    ).first()
    if profile is None:
        raise HTTPException(status_code=404, detail="Guide profile not found")
    return profile


def get_guide_profile_or_404(session: Session, guide_id: int) -> GuideProfile:
    return guide_profile(session, guide_id)


def enforce_trust(session: Session, user_id: int, action: str) -> dict:
    """Server-side trust gate. Raises 403 with the gate detail on failure."""
    tier = user_tier(session, user_id)
    detail = rules.trust_gate_detail(tier, action)
    if not detail["allowed"]:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail={
                "error": "trust_tier_too_low",
                "message": (
                    f"'{action}' requires the '{detail['required_tier']}' tier "
                    f"(you are '{tier}'). Complete simulated verification first."
                ),
                **detail,
            },
        )
    return detail


def current_user(
    session: Session = Depends(get_session),
    x_user_id: Optional[int] = Header(default=None, alias="X-User-Id"),
) -> User:
    """Resolve the acting user.

    Phase 1 has no full auth for these journeys: the caller identifies them with
    ``X-User-Id`` (the id of a registered user). This is deliberately explicit
    so it is obvious where real auth must replace it, and every stranger-facing
    action is still gated by :func:`enforce_trust`.
    """
    if x_user_id is None:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="X-User-Id header required for journey endpoints",
        )
    user = session.get(User, x_user_id)
    if user is None:
        raise HTTPException(status_code=401, detail="Unknown user")
    return user


def get_experience_or_404(session: Session, experience_id: Optional[int]) -> Optional[Experience]:
    if experience_id is None:
        return None
    experience = session.get(Experience, experience_id)
    if experience is None:
        raise HTTPException(status_code=404, detail="Experience not found")
    return experience


def get_guide_or_404(session: Session, guide_id: int) -> Guide:
    guide = session.get(Guide, guide_id)
    if guide is None:
        raise HTTPException(status_code=404, detail="Guide not found")
    return guide
