"""Limited hidden-gem pipeline (PRD v2, Phase 1).

Crowd-sourced candidates with provenance, votes and promotion into the curated
``experiences`` table. Deliberately small: a candidate is a *record*, and
promotion re-uses the existing feasibility data rather than introducing a new
discovery system.
"""

from __future__ import annotations

import logging

from fastapi import APIRouter, Depends, Header, HTTPException, Query, status
from sqlmodel import Session, select

from app.database import get_session
from app.models import Experience, User
from app.models_prd import HiddenGemCandidate, Source
from app.schemas_prd import HiddenGemCreate, HiddenGemResponse, HiddenGemVote
from app.timeutil import utcnow

logger = logging.getLogger(__name__)
router = APIRouter()

#: Votes needed before a candidate can be promoted.
PROMOTION_VOTES = 3


def _payload(candidate: HiddenGemCandidate, source: Source | None) -> HiddenGemResponse:
    return HiddenGemResponse(
        id=candidate.id or 0,
        name=candidate.name,
        lat=candidate.lat,
        lng=candidate.lng,
        area=candidate.area,
        category=candidate.category,
        status=candidate.status,
        votes=candidate.votes,
        promoted_experience_id=candidate.promoted_experience_id,
        submitted_by=candidate.submitted_by,
        source=(
            {"id": source.id, "name": source.name, "kind": source.kind, "url": source.url}
            if source
            else None
        ),
    )


@router.post(
    "/gems",
    response_model=HiddenGemResponse,
    status_code=status.HTTP_201_CREATED,
    summary="Submit a hidden-gem candidate",
)
def submit_gem(
    payload: HiddenGemCreate,
    session: Session = Depends(get_session),
    x_user_id: int | None = Header(default=None, alias="X-User-Id"),
):
    """Phase 1 pipeline: record a candidate with its source for review."""
    if x_user_id is not None and session.get(User, x_user_id) is None:
        raise HTTPException(status_code=401, detail="Unknown user")
    if payload.source_id is not None and session.get(Source, payload.source_id) is None:
        raise HTTPException(status_code=404, detail="Source not found")

    candidate = HiddenGemCandidate(
        name=payload.name,
        lat=payload.lat,
        lng=payload.lng,
        area=payload.area,
        category=payload.category.lower(),
        submitted_by=x_user_id,
        source_id=payload.source_id,
        note=payload.note,
    )
    session.add(candidate)
    session.commit()
    session.refresh(candidate)
    source = session.get(Source, candidate.source_id) if candidate.source_id else None
    logger.info("Hidden gem candidate %s submitted: %s", candidate.id, candidate.name)
    return _payload(candidate, source)


@router.get("/gems", response_model=list[HiddenGemResponse], summary="Hidden-gem candidates")
def list_gems(
    session: Session = Depends(get_session),
    gem_status: str | None = Query(default=None, alias="status"),
):
    stmt = select(HiddenGemCandidate).order_by(HiddenGemCandidate.votes.desc())
    if gem_status:
        stmt = stmt.where(HiddenGemCandidate.status == gem_status)
    rows = session.exec(stmt).all()
    return [
        _payload(c, session.get(Source, c.source_id) if c.source_id else None) for c in rows
    ]


@router.post("/gems/{candidate_id}/vote", response_model=HiddenGemResponse, summary="Vote a gem")
def vote_gem(
    candidate_id: int,
    payload: HiddenGemVote,
    session: Session = Depends(get_session),
):
    candidate = session.get(HiddenGemCandidate, candidate_id)
    if candidate is None:
        raise HTTPException(status_code=404, detail="Candidate not found")
    if candidate.status != "pending":
        raise HTTPException(status_code=409, detail=f"candidate is '{candidate.status}'")
    candidate.votes += 1 if payload.approve else -1
    if candidate.votes >= PROMOTION_VOTES:
        candidate.status = "approved"
    session.add(candidate)
    session.commit()
    session.refresh(candidate)
    source = session.get(Source, candidate.source_id) if candidate.source_id else None
    return _payload(candidate, source)


@router.post(
    "/gems/{candidate_id}/promote",
    response_model=dict,
    status_code=status.HTTP_201_CREATED,
    summary="Promote an approved gem into the curated dataset",
)
def promote_gem(
    candidate_id: int,
    session: Session = Depends(get_session),
    x_user_id: int = Header(..., alias="X-User-Id"),
):
    """Turn an approved candidate into a real, rankable experience."""
    from app.api.v1.journey_deps import enforce_trust

    enforce_trust(session, x_user_id, "promote_gem")  # curation is standard+ only
    candidate = session.get(HiddenGemCandidate, candidate_id)
    if candidate is None:
        raise HTTPException(status_code=404, detail="Candidate not found")
    if candidate.status != "approved":
        raise HTTPException(
            status_code=409, detail=f"candidate is '{candidate.status}', needs approval first"
        )
    if candidate.promoted_experience_id:
        raise HTTPException(status_code=409, detail="candidate already promoted")

    experience = Experience(
        name=candidate.name,
        category=candidate.category,
        lat=candidate.lat,
        lng=candidate.lng,
        avg_cost=0,
        duration_min=90,
        open_time="09:00",
        close_time="21:00",
        rating=0.0,
        description=candidate.note or f"Community gem in {candidate.area or 'Mumbai'}.",
        tags=["hidden-gem", "community"],
        accessibility_flags=[],
        indoor_outdoor="outdoor",
        local_gem_score=0.8,
    )
    session.add(experience)
    session.commit()
    session.refresh(experience)

    candidate.promoted_experience_id = experience.id
    candidate.status = "promoted"
    session.add(candidate)
    session.commit()
    logger.info("Hidden gem %s promoted to experience %s", candidate_id, experience.id)
    return {
        "candidate_id": candidate_id,
        "experience_id": experience.id,
        "status": candidate.status,
    }


@router.post(
    "/sources",
    response_model=dict,
    status_code=status.HTTP_201_CREATED,
    summary="Register a candidate source",
)
def create_source(
    payload: dict,
    session: Session = Depends(get_session),
    x_user_id: int = Header(..., alias="X-User-Id"),
):
    """Record where gem candidates come from (PRD v2 ``Source`` entity)."""
    from app.api.v1.journey_deps import enforce_trust

    enforce_trust(session, x_user_id, "promote_gem")
    name = str(payload.get("name") or "").strip()
    if not name:
        raise HTTPException(status_code=422, detail="name is required")
    source = Source(
        name=name,
        kind=str(payload.get("kind", "manual")),
        url=str(payload.get("url", "")),
    )
    session.add(source)
    session.commit()
    session.refresh(source)
    return {"id": source.id, "name": source.name, "kind": source.kind, "url": source.url}
