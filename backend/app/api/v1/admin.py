"""Admin content management for experiences.

Protected by a shared admin key (``ADMIN_API_KEY``) sent as ``X-Admin-Key``.
When the key is unset the whole surface returns 503, so a default deployment
exposes nothing.
"""

from __future__ import annotations

import hmac
import logging

from fastapi import APIRouter, Depends, Header, HTTPException, Request, Response
from fastapi import status as http_status
from sqlmodel import Session

from app.config import get_settings
from app.database import get_session
from app.models import Experience
from app.rate_limit import PUBLIC_LIMIT, limiter
from app.schemas import ExperienceCreate, ExperienceResponse, ExperienceUpdate

logger = logging.getLogger(__name__)
router = APIRouter()


def require_admin(x_admin_key: str | None = Header(default=None)) -> None:
    """Validate the admin key. Disabled entirely when no key is configured."""
    configured = get_settings().admin_api_key
    if not configured:
        raise HTTPException(
            status_code=http_status.HTTP_503_SERVICE_UNAVAILABLE,
            detail="Admin API is disabled (set ADMIN_API_KEY)",
        )
    if not x_admin_key or not hmac.compare_digest(x_admin_key, configured):
        raise HTTPException(
            status_code=http_status.HTTP_401_UNAUTHORIZED,
            detail="Invalid admin key",
        )


@router.post(
    "/admin/experiences",
    response_model=ExperienceResponse,
    status_code=http_status.HTTP_201_CREATED,
    summary="Create an experience",
    dependencies=[Depends(require_admin)],
)
@limiter.limit(PUBLIC_LIMIT)
def create_experience(
    request: Request,
    response: Response,
    payload: ExperienceCreate,
    session: Session = Depends(get_session),
):
    experience = Experience(**payload.model_dump())
    session.add(experience)
    session.commit()
    session.refresh(experience)
    logger.info("Admin created experience id=%s", experience.id)
    return ExperienceResponse.model_validate(experience)


@router.patch(
    "/admin/experiences/{experience_id}",
    response_model=ExperienceResponse,
    summary="Update an experience",
    dependencies=[Depends(require_admin)],
)
@limiter.limit(PUBLIC_LIMIT)
def update_experience(
    request: Request,
    response: Response,
    experience_id: int,
    payload: ExperienceUpdate,
    session: Session = Depends(get_session),
):
    experience = session.get(Experience, experience_id)
    if experience is None:
        raise HTTPException(status_code=404, detail="Experience not found")
    for field, value in payload.model_dump(exclude_unset=True).items():
        setattr(experience, field, value)
    session.add(experience)
    session.commit()
    session.refresh(experience)
    logger.info("Admin updated experience id=%s", experience_id)
    return ExperienceResponse.model_validate(experience)


@router.delete(
    "/admin/experiences/{experience_id}",
    status_code=http_status.HTTP_204_NO_CONTENT,
    summary="Delete an experience",
    dependencies=[Depends(require_admin)],
)
@limiter.limit(PUBLIC_LIMIT)
def delete_experience(
    request: Request,
    response: Response,
    experience_id: int,
    session: Session = Depends(get_session),
):
    experience = session.get(Experience, experience_id)
    if experience is None:
        raise HTTPException(status_code=404, detail="Experience not found")
    session.delete(experience)
    session.commit()
    logger.info("Admin deleted experience id=%s", experience_id)
    return Response(status_code=http_status.HTTP_204_NO_CONTENT)
