"""Semantic + tag hybrid search over experiences.

Works on both Postgres+pgvector and SQLite (which stores vectors as JSON and
uses a brute-force cosine scan). The public API is intentionally simple:
``semantic_search`` returns candidate experience IDs that the existing
feasibility ranker then scores.
"""

from __future__ import annotations

import logging
import math
from typing import Any

from sqlalchemy import text
from sqlmodel import Session, select

from app.config import get_settings
from app.models import Experience, ExperienceTag, Tag
from app.services.embeddings import embed_text, normalize_vector

logger = logging.getLogger(__name__)

settings = get_settings()


def _cosine_similarity(a: list[float], b: list[float]) -> float:
    """Cosine similarity between two equal-length vectors."""
    dot = sum(x * y for x, y in zip(a, b))
    norm_a = math.sqrt(sum(x * x for x in a))
    norm_b = math.sqrt(sum(x * x for x in b))
    if norm_a == 0 or norm_b == 0:
        return 0.0
    return dot / (norm_a * norm_b)


def _is_postgres(session: Session) -> bool:
    return "postgresql" in str(session.bind.url).lower() if session.bind else False


async def semantic_search(
    session: Session,
    query_text: str,
    *,
    top_k: int = 50,
    required_tags: list[str] | None = None,
    excluded_tags: list[str] | None = None,
    category: str | None = None,
    indoor_outdoor: str | None = None,
    lat: float | None = None,
    lng: float | None = None,
    radius_km: float | None = None,
) -> list[int]:
    """Return experience IDs ordered by semantic relevance.

    On Postgres+pgvector this uses ``<=>`` cosine-distance with pre-filtering.
    On SQLite it loads candidate embeddings into memory and scores them.
    """
    if not query_text or not query_text.strip():
        return _fallback_ids(session, required_tags, excluded_tags, category, indoor_outdoor)

    query_vector = normalize_vector(await embed_text(query_text))

    if _is_postgres(session):
        ids = _pgvector_search(
            session,
            query_vector,
            top_k=top_k,
            required_tags=required_tags,
            excluded_tags=excluded_tags,
            category=category,
            indoor_outdoor=indoor_outdoor,
            lat=lat,
            lng=lng,
            radius_km=radius_km,
        )
    else:
        ids = _sqlite_search(
            session,
            query_vector,
            top_k=top_k,
            required_tags=required_tags,
            excluded_tags=excluded_tags,
            category=category,
            indoor_outdoor=indoor_outdoor,
            lat=lat,
            lng=lng,
            radius_km=radius_km,
        )

    # No embeddings yet (fresh DB / tests): fall back to tag + rating order so
    # semantic mode still returns useful candidates.
    if not ids:
        return _fallback_ids(session, required_tags, excluded_tags, category, indoor_outdoor)
    return ids


def _fallback_ids(
    session: Session,
    required_tags: list[str] | None = None,
    excluded_tags: list[str] | None = None,
    category: str | None = None,
    indoor_outdoor: str | None = None,
) -> list[int]:
    """When no query text is given, return tag-filtered IDs by rating."""
    stmt = select(Experience.id)
    if category:
        stmt = stmt.where(Experience.category == category)
    if indoor_outdoor:
        stmt = stmt.where(Experience.indoor_outdoor == indoor_outdoor)
    stmt = _apply_tag_filters(stmt, required_tags, excluded_tags)
    stmt = stmt.order_by(Experience.rating.desc()).limit(200)
    # SQLModel returns scalars for a single-column select, so normalise both
    # scalar and row-tuple results.
    results = session.exec(stmt).all()
    return [row if isinstance(row, int) else row[0] for row in results]


def _apply_tag_filters(
    stmt: Any,
    required_tags: list[str] | None,
    excluded_tags: list[str] | None,
) -> Any:
    """Add tag EXISTS/NOT EXISTS filters to an Experience select."""
    if required_tags:
        required = [t.lower() for t in required_tags if t]
        for tag_name in required:
            stmt = stmt.where(
                Experience.id.in_(
                    select(ExperienceTag.experience_id)
                    .join(Tag)
                    .where(Tag.name == tag_name)
                )
            )
    if excluded_tags:
        excluded = [t.lower() for t in excluded_tags if t]
        for tag_name in excluded:
            stmt = stmt.where(
                ~Experience.id.in_(
                    select(ExperienceTag.experience_id)
                    .join(Tag)
                    .where(Tag.name == tag_name)
                )
            )
    return stmt


def _pgvector_search(
    session: Session,
    query_vector: list[float],
    *,
    top_k: int,
    required_tags: list[str] | None,
    excluded_tags: list[str] | None,
    category: str | None,
    indoor_outdoor: str | None,
    lat: float | None,
    lng: float | None,
    radius_km: float | None,
) -> list[int]:
    """pgvector native cosine-distance search with pre-filters."""
    dim = len(query_vector)
    vector_literal = "[" + ",".join(str(v) for v in query_vector) + "]"

    where_clauses: list[str] = []
    params: dict[str, Any] = {"top_k": top_k, "qv": vector_literal}

    if category:
        where_clauses.append("e.category = :category")
        params["category"] = category
    if indoor_outdoor:
        where_clauses.append("e.indoor_outdoor = :io")
        params["io"] = indoor_outdoor
    if radius_km is not None and lat is not None and lng is not None:
        where_clauses.append(
            "(6371 * acos("
            "cos(radians(:lat)) * cos(radians(e.lat)) * cos(radians(e.lng) - radians(:lng)) + "
            "sin(radians(:lat)) * sin(radians(e.lat))"
            ")) <= :radius"
        )
        params["lat"] = lat
        params["lng"] = lng
        params["radius"] = radius_km

    if required_tags:
        for idx, tag_name in enumerate(required_tags):
            alias = f"et_req_{idx}"
            where_clauses.append(
                f"EXISTS (SELECT 1 FROM experience_tags {alias} "
                f"JOIN tags t{idx} ON t{idx}.id = {alias}.tag_id "
                f"WHERE {alias}.experience_id = e.id AND t{idx}.name = :req_tag_{idx})"
            )
            params[f"req_tag_{idx}"] = tag_name

    if excluded_tags:
        for idx, tag_name in enumerate(excluded_tags):
            where_clauses.append(
                f"NOT EXISTS (SELECT 1 FROM experience_tags et_exc_{idx} "
                f"JOIN tags t_exc_{idx} ON t_exc_{idx}.id = et_exc_{idx}.tag_id "
                f"WHERE et_exc_{idx}.experience_id = e.id AND t_exc_{idx}.name = :exc_tag_{idx})"
            )
            params[f"exc_tag_{idx}"] = tag_name

    where_sql = " AND ".join(where_clauses) if where_clauses else "TRUE"

    sql = f"""
        SELECT e.id,
               e.embedding <=> :qv AS distance
        FROM experiences e
        WHERE e.embedding IS NOT NULL
          AND {where_sql}
        ORDER BY e.embedding <=> :qv
        LIMIT :top_k
    """
    rows = session.execute(text(sql), params).all()
    return [int(row[0]) for row in rows]


def _sqlite_search(
    session: Session,
    query_vector: list[float],
    *,
    top_k: int,
    required_tags: list[str] | None,
    excluded_tags: list[str] | None,
    category: str | None,
    indoor_outdoor: str | None,
    lat: float | None,
    lng: float | None,
    radius_km: float | None,
) -> list[int]:
    """Brute-force cosine search for SQLite dev/tests."""
    stmt = select(Experience).where(Experience.embedding.is_not(None))  # type: ignore[attr-defined]
    if category:
        stmt = stmt.where(Experience.category == category)
    if indoor_outdoor:
        stmt = stmt.where(Experience.indoor_outdoor == indoor_outdoor)
    stmt = _apply_tag_filters(stmt, required_tags, excluded_tags)

    candidates = list(session.exec(stmt).all())
    scored: list[tuple[float, int]] = []
    for exp in candidates:
        if not exp.embedding:
            continue
        if radius_km is not None and lat is not None and lng is not None:
            from app.services.recommender import haversine_km

            d = haversine_km(lat, lng, exp.lat, exp.lng)
            if d > radius_km:
                continue
        sim = _cosine_similarity(query_vector, exp.embedding)
        scored.append((sim, exp.id))

    scored.sort(key=lambda x: x[0], reverse=True)
    return [exp_id for _, exp_id in scored[:top_k]]
