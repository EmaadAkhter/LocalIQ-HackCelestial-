"""The three recommendation graphs (PRD 4.1).

- **Location → Person (U2A):** taste-aware, feasibility-first ranking.
- **Location → Location (A2A):** similar experiences by embedding, thematic
  overlap and proximity — used for "people also liked" and route building.
- **Person → Person (U2U):** taste-vector compatibility between users for
  meetups and group quests.

Works on both pgvector and SQLite: embeddings are read from the model and
compared in Python when the database cannot do it natively.
"""

from __future__ import annotations

import logging
import math
from typing import Any

from sqlmodel import Session, select

from app.models import Experience, User
from app.services import recommender, taste
from app.services.reranker import RerankContext, Reranked, rerank

logger = logging.getLogger(__name__)


def _cosine(a: list[float] | None, b: list[float] | None) -> float:
    if not a or not b or len(a) != len(b):
        return 0.0
    dot = sum(x * y for x, y in zip(a, b))
    na = math.sqrt(sum(x * x for x in a))
    nb = math.sqrt(sum(y * y for y in b))
    if na == 0 or nb == 0:
        return 0.0
    return dot / (na * nb)


def _tag_overlap(a: Experience, b: Experience) -> float:
    ta = {taste.normalize_tag(t) for t in (a.tags or [])}
    tb = {taste.normalize_tag(t) for t in (b.tags or [])}
    if not ta or not tb:
        return 0.0
    inter = len(ta & tb)
    union = len(ta | tb)
    return inter / union if union else 0.0


# ---------------------------------------------------------------------------
# Location -> Location (A2A)
# ---------------------------------------------------------------------------


def similar_experiences(
    session: Session,
    experience_id: int,
    *,
    top_k: int = 6,
    same_area_only: bool = False,
) -> list[dict[str, Any]]:
    """Experiences most similar to ``experience_id``.

    Blends embedding cosine (semantic), tag overlap (thematic) and proximity
    (nearby), so a fresh DB with no embeddings still returns sensible results.
    """
    target = session.get(Experience, experience_id)
    if target is None:
        return []

    others = list(
        session.exec(select(Experience).where(Experience.id != experience_id)).all()
    )
    scored: list[tuple[float, Experience, dict[str, float]]] = []
    for exp in others:
        if same_area_only and (exp.tags or []) and (target.tags or []):
            pass  # area is not a tag; kept for API symmetry
        emb = _cosine(target.embedding, exp.embedding)
        thematic = _tag_overlap(target, exp)
        dist = recommender.haversine_km(target.lat, target.lng, exp.lat, exp.lng)
        proximity = math.exp(-dist / 5.0)
        category_bonus = 1.0 if exp.category == target.category else 0.0
        score = 0.45 * emb + 0.30 * thematic + 0.15 * proximity + 0.10 * category_bonus
        parts = {
            "embedding": round(emb, 4),
            "tags": round(thematic, 4),
            "proximity": round(proximity, 4),
            "category": category_bonus,
        }
        scored.append((score, exp, parts))

    scored.sort(key=lambda x: x[0], reverse=True)
    return [
        {
            "experience": exp,
            "score": round(score, 4),
            "parts": parts,
            "distance_km": round(
                recommender.haversine_km(target.lat, target.lng, exp.lat, exp.lng), 2
            ),
        }
        for score, exp, parts in scored[:top_k]
    ]


# ---------------------------------------------------------------------------
# Person -> Person (U2U)
# ---------------------------------------------------------------------------


def match_users(
    session: Session,
    user: User,
    *,
    top_k: int = 5,
    min_score: float = 0.05,
) -> list[dict[str, Any]]:
    """Users whose taste profile is compatible with ``user``'s.

    Compatibility is the cosine of the two taste vectors. Users with no learned
    taste yet are skipped. Trust-tier gating happens in the API layer.
    """
    mine = dict(user.taste_profile_vector or {})
    if not mine:
        return []
    others = list(session.exec(select(User).where(User.id != user.id)).all())
    matches: list[dict[str, Any]] = []
    for other in others:
        theirs = dict(other.taste_profile_vector or {})
        if not theirs:
            continue
        score = taste.vector_cosine(mine, theirs)
        if score < min_score:
            continue
        shared = sorted(
            set(mine) & set(theirs),
            key=lambda k: abs(mine[k]) + abs(theirs[k]),
            reverse=True,
        )[:4]
        matches.append(
            {
                "user_id": other.id,
                "name": other.name,
                "taste_tier": getattr(other, "trust_tier", "basic"),
                "score": round(score, 4),
                "shared_interests": [s.replace("_", " ") for s in shared],
                "their_taste": other.taste_profile_text,
            }
        )
    matches.sort(key=lambda m: m["score"], reverse=True)
    return matches[:top_k]


# ---------------------------------------------------------------------------
# Location -> Person (U2A)
# ---------------------------------------------------------------------------


def taste_aware_recommend(
    session: Session,
    user: User | None,
    *,
    lat: float | None = None,
    lng: float | None = None,
    time_hours: float | None = None,
    budget_inr: int | None = None,
    start_time: str | None = None,
    weather: dict[str, Any] | None = None,
    limit: int = 10,
    candidate_ids: list[int] | None = None,
) -> list[Reranked]:
    """Feasibility-filtered, taste-re-ranked experiences for a user.

    ``candidate_ids`` lets a caller (e.g. the companion agent) restrict the pool
    to a semantic search result; otherwise the whole catalogue is considered.
    """
    stmt = select(Experience)
    if budget_inr is not None:
        stmt = stmt.where(Experience.avg_cost <= budget_inr)
    if candidate_ids:
        stmt = stmt.where(Experience.id.in_(candidate_ids))
    candidates = list(session.exec(stmt).all())

    taste_vector: dict[str, float] = {}
    if user is not None and user.personalization_enabled:
        taste_vector = dict(user.taste_profile_vector or {})

    ctx = RerankContext(
        lat=lat,
        lng=lng,
        time_hours=time_hours,
        budget_inr=budget_inr,
        start_time=start_time,
        weather=weather or {},
        taste_vector=taste_vector,
    )
    return rerank(candidates, ctx, limit=limit)
