"""Tag taxonomy API endpoints."""

from fastapi import APIRouter, Depends, Request, Response
from sqlmodel import Session, select

from app.database import get_session
from app.models import CompositeTag, Experience, ExperienceTag, Tag
from app.rate_limit import PUBLIC_LIMIT, limiter
from app.schemas import ExperienceResponse

router = APIRouter()


@router.get("/tags", summary="List all tags")
@limiter.limit(PUBLIC_LIMIT)
def list_tags(
    request: Request,
    response: Response,
    session: Session = Depends(get_session),
):
    """Return the full master tag taxonomy."""
    tags = session.exec(select(Tag).order_by(Tag.category, Tag.name)).all()
    return [
        {
            "id": t.id,
            "name": t.name,
            "category": t.category,
            "facet_type": t.facet_type,
            "description": t.description,
            "weight": t.weight,
        }
        for t in tags
    ]


@router.get("/tags/categories", summary="List tag categories")
@limiter.limit(PUBLIC_LIMIT)
def list_categories(
    request: Request,
    response: Response,
    session: Session = Depends(get_session),
):
    """Return distinct tag categories."""
    rows = session.exec(select(Tag.category).distinct()).all()
    return sorted(rows)


@router.get("/tags/{category}", summary="Tags by category")
@limiter.limit(PUBLIC_LIMIT)
def tags_by_category(
    request: Request,
    response: Response,
    category: str,
    session: Session = Depends(get_session),
):
    """Return tags for a specific category."""
    tags = session.exec(
        select(Tag).where(Tag.category == category).order_by(Tag.name)
    ).all()
    return [{"id": t.id, "name": t.name, "description": t.description} for t in tags]


@router.get("/composite-tags", summary="List composite tags")
@limiter.limit(PUBLIC_LIMIT)
def list_composite_tags(
    request: Request,
    response: Response,
    session: Session = Depends(get_session),
):
    """Return smart filter combinations."""
    tags = session.exec(select(CompositeTag).order_by(CompositeTag.name)).all()
    return [
        {
            "id": t.id,
            "name": t.name,
            "description": t.description,
            "required_tags": t.required_tags,
            "optional_tags": t.optional_tags,
        }
        for t in tags
    ]


@router.get("/experiences/{experience_id}/tags", summary="Tags for an experience")
@limiter.limit(PUBLIC_LIMIT)
def experience_tags(
    request: Request,
    response: Response,
    experience_id: int,
    session: Session = Depends(get_session),
):
    """Return normalized tags linked to an experience."""
    experience = session.get(Experience, experience_id)
    if experience is None:
        return []
    tag_rows = session.exec(
        select(Tag, ExperienceTag.confidence)
        .join(ExperienceTag)
        .where(ExperienceTag.experience_id == experience_id)
        .order_by(Tag.category, Tag.name)
    ).all()
    return [
        {
            "name": t.name,
            "category": t.category,
            "confidence": confidence,
        }
        for t, confidence in tag_rows
    ]


@router.get("/experiences/by-tag/{tag_name}", summary="Experiences with a tag")
@limiter.limit(PUBLIC_LIMIT)
def experiences_by_tag(
    request: Request,
    response: Response,
    tag_name: str,
    session: Session = Depends(get_session),
):
    """Return experiences linked to a specific tag."""
    tag = session.exec(select(Tag).where(Tag.name == tag_name)).first()
    if tag is None:
        return []
    rows = session.exec(
        select(Experience)
        .join(ExperienceTag)
        .where(ExperienceTag.tag_id == tag.id)
        .order_by(Experience.rating.desc())
    ).all()
    return [ExperienceResponse.model_validate(e) for e in rows]
