"""Trust tier for travellers (PRD v2 journey 2, safety gate).

Phase 1 only: verification is *simulated*. There is no KYC provider, no document
upload and no third-party call. The endpoint exists so the meetup/group gates
have a legitimate server-side way to be satisfied during a demo, and so the
client can render why an action is blocked.
"""

from __future__ import annotations

import logging

from fastapi import APIRouter, Depends, HTTPException
from sqlmodel import Session

from app.api.v1.journey_deps import current_user
from app.database import get_session
from app.models import User
from app.schemas_prd import TrustStateResponse, TrustVerifyRequest
from app.services import journey_rules as rules
from app.timeutil import utcnow

logger = logging.getLogger(__name__)
router = APIRouter()

#: What each tier unlocks, derived from the gates table so the two never drift.
TIER_SUMMARY = {
    "unverified": ["browse", "solo_explore"],
    "basic": ["browse", "solo_explore", "create_group", "join_group", "book_guide", "start_quest"],
    "standard": ["create_meetup_request", "be_matched", "leave_review"],
    "trusted": ["create_meetup_request", "be_matched", "leave_review", "priority_matching"],
}


def _state(user: User) -> TrustStateResponse:
    tier = user.trust_tier or "basic"
    return TrustStateResponse(
        user_id=user.id or 0,
        tier=tier,
        verified_at=user.trust_verified_at,
        unlocked=TIER_SUMMARY.get(tier, []),
        next_tier=(
            rules.TRUST_TIERS[rules.tier_rank(tier) + 1]
            if rules.tier_rank(tier) + 1 < len(rules.TRUST_TIERS)
            else None
        ),
        gates=rules.TRUST_GATES,
    )


@router.get("/me/trust", response_model=TrustStateResponse, summary="My trust tier")
def my_trust(user: User = Depends(current_user)) -> TrustStateResponse:
    """Report the caller's tier and what it unlocks. No sensitive data."""
    return _state(user)


@router.post(
    "/me/trust/verify",
    response_model=TrustStateResponse,
    summary="Simulated trust verification (Phase 1)",
)
def verify_trust(
    payload: TrustVerifyRequest,
    user: User = Depends(current_user),
    session: Session = Depends(get_session),
) -> TrustStateResponse:
    """Move the caller up one simulated tier.

    Deliberately dumb and server-decided: a request may only *advance* the tier
    by one step, never jump, and never downgrade. Real KYC would replace this.
    """
    target = payload.target_tier
    if target not in rules.TRUST_TIERS:
        raise HTTPException(status_code=422, detail=f"unknown tier '{target}'")
    current = user.trust_tier or "basic"
    if rules.tier_rank(target) > rules.tier_rank(current) + 1:
        raise HTTPException(
            status_code=409,
            detail=(
                f"cannot jump from '{current}' to '{target}'; complete each "
                "verification step in order"
            ),
        )
    if rules.tier_rank(target) < rules.tier_rank(current):
        raise HTTPException(
            status_code=409, detail=f"cannot downgrade from '{current}' to '{target}'"
        )

    user.trust_tier = target
    user.trust_verified_at = utcnow()
    session.add(user)
    session.commit()
    session.refresh(user)
    logger.info("User %s trust tier set to %s (simulated)", user.id, target)
    return _state(user)
