"""Guided onboarding endpoints (taste capture).

    POST /onboarding/user/start            -> first prompt (or resume)
    POST /onboarding/user/{id}/answer      -> next prompt, or the finished taste
    GET  /onboarding/user/status           -> progress + current taste snapshot

The conversation is scripted server-side so the client stays a thin renderer.
"""

from __future__ import annotations

import logging

from fastapi import APIRouter, Depends, HTTPException, Request, Response
from sqlmodel import Session

from app.database import get_session
from app.models import User
from app.rate_limit import PUBLIC_LIMIT, limiter
from app.schemas import (
    OnboardingAnswerRequest,
    OnboardingStartRequest,
    OnboardingStep,
)
from app.services import onboarding
from app.services.auth import get_current_user

logger = logging.getLogger(__name__)
router = APIRouter()


@router.post(
    "/onboarding/user/start",
    response_model=OnboardingStep,
    summary="Start (or resume) the taste conversation",
)
@limiter.limit(PUBLIC_LIMIT)
def start_onboarding(
    request: Request,
    response: Response,
    payload: OnboardingStartRequest,
    session: Session = Depends(get_session),
    current_user: User = Depends(get_current_user),
):
    return OnboardingStep(
        **onboarding.start_user_onboarding(
            session,
            current_user,
            language=payload.language,
            restart=payload.restart,
        )
    )


@router.post(
    "/onboarding/user/{session_id}/answer",
    response_model=OnboardingStep,
    summary="Answer the current prompt",
)
@limiter.limit(PUBLIC_LIMIT)
async def answer_onboarding(
    request: Request,
    response: Response,
    session_id: int,
    payload: OnboardingAnswerRequest,
    session: Session = Depends(get_session),
    current_user: User = Depends(get_current_user),
):
    try:
        result = await onboarding.answer_user_onboarding(
            session,
            current_user,
            session_id,
            message=payload.message,
            selections=payload.selections,
        )
    except LookupError:
        raise HTTPException(status_code=404, detail="Onboarding session not found")
    return OnboardingStep(**result)


@router.get(
    "/onboarding/user/status",
    response_model=OnboardingStep,
    summary="Taste-onboarding progress",
)
@limiter.limit(PUBLIC_LIMIT)
def onboarding_status(
    request: Request,
    response: Response,
    session: Session = Depends(get_session),
    current_user: User = Depends(get_current_user),
):
    return OnboardingStep(**onboarding.user_status(session, current_user))
