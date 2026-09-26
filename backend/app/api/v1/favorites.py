"""Saved experiences for the current user."""

from __future__ import annotations

import logging

from fastapi import APIRouter, Depends, HTTPException, Request, Response
from fastapi import status as http_status
from sqlmodel import Session, select

from app.database import get_session
from app.models import Experience, Favorite, User
from app.rate_limit import PUBLIC_LIMIT, limiter
from app.schemas import ExperienceResponse
from app.services.auth import get_current_user

logger = logging.getLogger(__name__)
router = APIRouter()


@router.get("/me/favorites", response_model=list[ExperienceResponse], summary="List my favorites")
@limiter.limit(PUBLIC_LIMIT)
def list_favorites(
    request: Request,
    response: Response,
    session: Session = Depends(get_session),
    current_user: User = Depends(get_current_user),
):
    rows = session.exec(
        select(Favorite)
        .where(Favorite.user_id == current_user.id)
        .order_by(Favorite.created_at.desc())
    ).all()
    ids = [row.experience_id for row in rows]
    if not ids:
        return []
    experiences = session.exec(select(Experience).where(Experience.id.in_(ids))).all()
    by_id = {e.id: e for e in experiences}
    return [ExperienceResponse.model_validate(by_id[i]) for i in ids if i in by_id]


@router.post(
    "/me/favorites/{experience_id}",
    response_model=ExperienceResponse,
    status_code=http_status.HTTP_201_CREATED,
    summary="Save an experience (idempotent)",
)
@limiter.limit(PUBLIC_LIMIT)
def add_favorite(
    request: Request,
    response: Response,
    experience_id: int,
    session: Session = Depends(get_session),
    current_user: User = Depends(get_current_user),
):
    experience = session.get(Experience, experience_id)
    if experience is None:
        raise HTTPException(status_code=404, detail="Experience not found")

    existing = session.exec(
        select(Favorite).where(
            Favorite.user_id == current_user.id,
            Favorite.experience_id == experience_id,
        )
    ).first()
    if existing is None:
        session.add(Favorite(user_id=current_user.id, experience_id=experience_id))
        session.commit()
    return ExperienceResponse.model_validate(experience)


@router.delete(
    "/me/favorites/{experience_id}",
    status_code=http_status.HTTP_204_NO_CONTENT,
    summary="Remove a saved experience",
)
@limiter.limit(PUBLIC_LIMIT)
def remove_favorite(
    request: Request,
    response: Response,
    experience_id: int,
    session: Session = Depends(get_session),
    current_user: User = Depends(get_current_user),
):
    row = session.exec(
        select(Favorite).where(
            Favorite.user_id == current_user.id,
            Favorite.experience_id == experience_id,
        )
    ).first()
    if row is not None:
        session.delete(row)
        session.commit()
    return Response(status_code=http_status.HTTP_204_NO_CONTENT)
