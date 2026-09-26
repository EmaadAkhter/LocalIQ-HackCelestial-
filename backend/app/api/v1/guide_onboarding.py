"""Fast guide onboarding endpoints.

    GET  /guides/onboarding/options            -> areas, niches, document kinds
    POST /guides/onboarding/start              -> create the draft application
    POST /guides/onboarding/documents          -> upload a licence (multipart)
    POST /guides/onboarding/apply              -> areas + niches; state -> pending
    GET  /guides/onboarding/me                 -> application status
    POST /admin/guides/{guide_id}/verify       -> admin approve / reject

Documents go straight to object storage; only their keys and metadata are
persisted. Approval raises the guide's trust tier and publishes the profile.
"""

from __future__ import annotations

import logging

from fastapi import (
    APIRouter,
    Depends,
    File,
    Form,
    HTTPException,
    Request,
    Response,
    UploadFile,
)
from sqlmodel import Session

from app.api.v1.admin import require_admin
from app.database import get_session
from app.models import User
from app.rate_limit import PUBLIC_LIMIT, limiter
from app.schemas import (
    GuideDocumentResponse,
    GuideOnboardingApplyRequest,
    GuideOnboardingStartRequest,
    GuideOnboardingStatus,
    GuideOptionsResponse,
    GuideVerifyRequest,
)
from app.services import guide_onboarding
from app.services.auth import get_current_user

logger = logging.getLogger(__name__)
router = APIRouter()


@router.get(
    "/guides/onboarding/options",
    response_model=GuideOptionsResponse,
    summary="Areas, niches and required documents",
)
@limiter.limit(PUBLIC_LIMIT)
def onboarding_options(request: Request, response: Response):
    return GuideOptionsResponse(
        areas=guide_onboarding.area_options(),
        niches=list(guide_onboarding.NICHE_OPTIONS),
        document_kinds=list(guide_onboarding.DOCUMENT_KINDS),
    )


@router.post(
    "/guides/onboarding/start",
    response_model=GuideOnboardingStatus,
    summary="Start (or resume) a guide application",
)
@limiter.limit(PUBLIC_LIMIT)
def start_guide_onboarding(
    request: Request,
    response: Response,
    payload: GuideOnboardingStartRequest,
    session: Session = Depends(get_session),
    current_user: User = Depends(get_current_user),
):
    profile = guide_onboarding.start(
        session,
        current_user,
        name=payload.name,
        languages=payload.languages,
        city=payload.city,
        bio=payload.bio,
    )
    return GuideOnboardingStatus(**guide_onboarding.status(session, current_user))


@router.post(
    "/guides/onboarding/documents",
    response_model=GuideDocumentResponse,
    summary="Upload a licence document",
)
@limiter.limit(PUBLIC_LIMIT)
async def upload_guide_document(
    request: Request,
    response: Response,
    kind: str = Form(..., description="driver_license | guide_license"),
    file: UploadFile = File(...),
    session: Session = Depends(get_session),
    current_user: User = Depends(get_current_user),
):
    data = await file.read()
    try:
        result = guide_onboarding.upload_document(
            session,
            current_user,
            kind=kind.strip().lower(),
            filename=file.filename or kind,
            content_type=file.content_type,
            data=data,
        )
    except ValueError as exc:
        raise HTTPException(status_code=422, detail=str(exc))
    except LookupError as exc:
        raise HTTPException(status_code=409, detail=str(exc))
    return GuideDocumentResponse(**result)


@router.post(
    "/guides/onboarding/apply",
    response_model=GuideOnboardingStatus,
    summary="Submit the application (areas + niches)",
)
@limiter.limit(PUBLIC_LIMIT)
def apply_guide_onboarding(
    request: Request,
    response: Response,
    payload: GuideOnboardingApplyRequest,
    session: Session = Depends(get_session),
    current_user: User = Depends(get_current_user),
):
    try:
        profile = guide_onboarding.apply(
            session,
            current_user,
            areas=payload.areas,
            niches=payload.niches,
            rate_per_hour=payload.rate_per_hour,
            bio=payload.bio,
            languages=payload.languages,
        )
    except ValueError as exc:
        raise HTTPException(status_code=422, detail=str(exc))
    except LookupError as exc:
        raise HTTPException(status_code=409, detail=str(exc))
    return GuideOnboardingStatus(**guide_onboarding.status(session, current_user))


@router.get(
    "/guides/onboarding/me",
    response_model=GuideOnboardingStatus,
    summary="My guide application status",
)
@limiter.limit(PUBLIC_LIMIT)
def my_guide_onboarding(
    request: Request,
    response: Response,
    session: Session = Depends(get_session),
    current_user: User = Depends(get_current_user),
):
    return GuideOnboardingStatus(**guide_onboarding.status(session, current_user))


@router.post(
    "/admin/guides/{guide_id}/verify",
    response_model=GuideOnboardingStatus,
    summary="Approve or reject a guide application",
    dependencies=[Depends(require_admin)],
)
@limiter.limit(PUBLIC_LIMIT)
def verify_guide(
    request: Request,
    response: Response,
    guide_id: int,
    payload: GuideVerifyRequest,
    session: Session = Depends(get_session),
):
    try:
        guide_onboarding.verify(
            session,
            guide_id,
            approve=payload.approve,
            notes=payload.notes,
            tier=payload.tier,
        )
    except LookupError as exc:
        raise HTTPException(status_code=404, detail=str(exc))
    # The applicant's user id is the profile owner; report through their status.
    from sqlmodel import select

    from app.models_prd import GuideProfile

    profile = session.exec(
        select(GuideProfile).where(GuideProfile.guide_id == guide_id)
    ).first()
    user = session.get(User, profile.user_id) if profile and profile.user_id else None
    if user is None:
        raise HTTPException(status_code=404, detail="guide applicant not found")
    return GuideOnboardingStatus(**guide_onboarding.status(session, user))
