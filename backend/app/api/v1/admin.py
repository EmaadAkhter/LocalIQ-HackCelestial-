"""Admin content management for experiences.

Protected by a shared admin key (``ADMIN_API_KEY``) sent as ``X-Admin-Key``.
When the key is unset the whole surface returns 503, so a default deployment
exposes nothing.
"""

from __future__ import annotations

import asyncio
import hmac
import logging
from datetime import datetime, timezone

from fastapi import APIRouter, Depends, Header, HTTPException, Request, Response
from fastapi import status as http_status
from sqlalchemy import text
from sqlmodel import Session, select

from app.config import get_settings
from app.database import engine, get_session
from app.models import Experience, ScrapedCandidate
from app.rate_limit import PUBLIC_LIMIT, limiter
from app.schemas import ExperienceCreate, ExperienceResponse, ExperienceUpdate
from app.services.embeddings import embed_text
from app.services.recommender import KNOWN_AREAS

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


@router.post(
    "/admin/reindex",
    summary="Regenerate all experience embeddings",
    dependencies=[Depends(require_admin)],
)
@limiter.limit(PUBLIC_LIMIT)
async def reindex_embeddings(
    request: Request,
    response: Response,
):
    """Clear and regenerate semantic embeddings for all experiences.

    Uses the configured Ollama model; falls back to deterministic vectors
    when the model is unavailable. Safe to run while the app is serving
    traffic because each experience is updated independently.
    """
    loop = asyncio.get_running_loop()
    # Run the DB-heavy work in a thread pool to avoid blocking the event loop.
    count = await loop.run_in_executor(None, _regenerate_all_embeddings)
    logger.info("Admin reindexed embeddings for %s experiences", count)
    return {"regenerated": count}


def _regenerate_all_embeddings(batch_size: int = 16) -> int:
    """Synchronous helper: embed every experience, clearing old vectors first."""
    return asyncio.run(_regenerate_async(batch_size=batch_size))


async def _regenerate_async(batch_size: int = 16) -> int:
    """Async helper: one event loop for all embedding calls."""
    count = 0
    with Session(engine) as session:
        session.exec(text("UPDATE experiences SET embedding = NULL"))
        session.commit()
        experiences = list(session.exec(select(Experience)).all())

    # Embed in small batches outside the main transaction to keep locks short.
    for i in range(0, len(experiences), batch_size):
        batch = experiences[i : i + batch_size]
        texts = [
            f"{exp.name}. {exp.category}. {exp.description}. Tags: {', '.join(exp.tags or [])}"
            for exp in batch
        ]
        vectors = await asyncio.gather(*[embed_text(t) for t in texts])
        with Session(engine) as session:
            for exp, vector in zip(batch, vectors):
                db_exp = session.get(Experience, exp.id)
                if db_exp is not None:
                    db_exp.embedding = vector
                    count += 1
            session.commit()
    return count


@router.get(
    "/admin/candidates",
    summary="List discovery candidates",
    dependencies=[Depends(require_admin)],
)
@limiter.limit(PUBLIC_LIMIT)
def list_candidates(
    request: Request,
    response: Response,
    status: str = "pending",
    limit: int = 50,
    session: Session = Depends(get_session),
):
    """List hidden gem candidates by status (pending/approved/rejected)."""
    rows = session.exec(
        select(ScrapedCandidate)
        .where(ScrapedCandidate.status == status)
        .order_by(ScrapedCandidate.mention_count.desc(), ScrapedCandidate.id.desc())
        .limit(max(1, min(limit, 200)))
    ).all()
    return [
        {
            "id": c.id,
            "raw_title": c.raw_title,
            "area": c.area,
            "url": c.url,
            "tags": (c.extracted_data or {}).get("tags", []),
            "mention_count": c.mention_count,
            "status": c.status,
        }
        for c in rows
    ]


@router.post(
    "/admin/candidates/{candidate_id}/approve",
    response_model=ExperienceResponse,
    status_code=http_status.HTTP_201_CREATED,
    summary="Approve a candidate into an experience",
    dependencies=[Depends(require_admin)],
)
@limiter.limit(PUBLIC_LIMIT)
def approve_candidate(
    request: Request,
    response: Response,
    candidate_id: int,
    session: Session = Depends(get_session),
):
    """Promote a discovery candidate to a real experience."""
    candidate = session.get(ScrapedCandidate, candidate_id)
    if candidate is None:
        raise HTTPException(status_code=404, detail="Candidate not found")
    if candidate.experience_id is not None:
        existing = session.get(Experience, candidate.experience_id)
        if existing is not None:
            return ExperienceResponse.model_validate(existing)

    data = candidate.extracted_data or {}
    tags = list(data.get("tags", []) or [])
    area_key = (candidate.area or "").strip().lower()
    coords = KNOWN_AREAS.get(area_key) or KNOWN_AREAS["mumbai"]

    experience = Experience(
        name=candidate.raw_title[:200],
        category=(tags[0] if tags else "culture"),
        lat=coords[0],
        lng=coords[1],
        avg_cost=0,
        duration_min=60,
        open_time="09:00",
        close_time="21:00",
        rating=4.0,
        description=str(data.get("sentence") or data.get("page_title") or candidate.raw_title)[:2000],
        tags=tags,
        indoor_outdoor="outdoor" if "outdoor" in tags else "indoor",
        local_gem_score=0.8,
    )
    session.add(experience)
    session.commit()
    session.refresh(experience)

    candidate.status = "approved"
    candidate.experience_id = experience.id
    candidate.reviewed_at = datetime.now(timezone.utc)
    session.add(candidate)
    session.commit()

    logger.info("Approved candidate %s -> experience %s", candidate_id, experience.id)
    return ExperienceResponse.model_validate(experience)


@router.post(
    "/admin/candidates/{candidate_id}/reject",
    summary="Reject a discovery candidate",
    dependencies=[Depends(require_admin)],
)
@limiter.limit(PUBLIC_LIMIT)
def reject_candidate(
    request: Request,
    response: Response,
    candidate_id: int,
    session: Session = Depends(get_session),
):
    candidate = session.get(ScrapedCandidate, candidate_id)
    if candidate is None:
        raise HTTPException(status_code=404, detail="Candidate not found")
    candidate.status = "rejected"
    candidate.reviewed_at = datetime.now(timezone.utc)
    session.add(candidate)
    session.commit()
    return {"id": candidate.id, "status": candidate.status}
