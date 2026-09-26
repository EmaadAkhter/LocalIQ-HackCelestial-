"""Recommendations API endpoints."""

import hashlib
import json
import logging

from fastapi import APIRouter, Depends, HTTPException, Request, Response
from sqlalchemy import case
from sqlmodel import Session, func, select

from app.config import get_settings
from app.database import get_session
from app.models import Experience, RecommendationFeedback, User
from app.rate_limit import PUBLIC_LIMIT, RECOMMEND_LIMIT, limiter
from app.schemas import (
    ExperienceResponse,
    FeedbackRequest,
    FeedbackResponse,
    OpeningHoursInfo,
    RecommendationItem,
    RecommendationRequest,
    RecommendationResponse,
    RouteInfo,
    WeatherContext,
)
from app.services import google_routes, recommender
from app.services.auth import get_current_user_optional
from app.services.semantic_search import semantic_search, _apply_tag_filters
from app.services.cache import TTLCache
from app.services.weather import fetch_weather

logger = logging.getLogger(__name__)
router = APIRouter()

settings = get_settings()

VALID_TRAVEL_MODES = {"WALK", "DRIVE", "BICYCLE", "TRANSIT"}

# Curated dataset entries carry no photos of their own; when a Places key is
# configured we look up one photo per recommendation (bounded + cached).
_PHOTO_LOOKUP_LIMIT = 6
_photo_cache: dict[str, str | None] = {}


async def _enrich_images(names: list[str], lat: float, lng: float) -> dict[str, str | None]:
    """Map experience name -> LocalIQ photo proxy URL, best effort.

    Skipped entirely when no server-side Places key is configured.
    """
    from app.services import google_places

    if not google_places.is_configured():
        return {}

    resolved: dict[str, str | None] = {}
    for name in names[:_PHOTO_LOOKUP_LIMIT]:
        if name in _photo_cache:
            resolved[name] = _photo_cache[name]
            continue
        results = await google_places.search_places(
            f"{name} Mumbai", lat=lat, lng=lng, page_size=1
        )
        url = results[0].image_url if results else None
        _photo_cache[name] = url
        resolved[name] = url
    return resolved

# Identical constraint sets are common (slider drags, repeated demo runs).
_recommend_cache = TTLCache(
    maxsize=settings.recommend_cache_maxsize,
    ttl_seconds=settings.recommend_cache_ttl_seconds,
)


def clear_recommend_cache() -> None:
    """Drop cached recommendations (used by tests)."""
    _recommend_cache.clear()


def recommend_cache_stats() -> dict[str, int]:
    return _recommend_cache.stats()


def _recommend_cache_key(payload: RecommendationRequest) -> str:
    blob = json.dumps(payload.model_dump(mode="json"), sort_keys=True)
    return hashlib.sha256(blob.encode("utf-8")).hexdigest()


def _feedback_scores(session: Session) -> dict[int, float]:
    """Net helpful ratio per experience, in [-1, 1]."""
    statement = (
        select(
            RecommendationFeedback.experience_id,
            func.count().label("total"),
            func.sum(case((RecommendationFeedback.helpful, 1), else_=0)).label("helpful"),
        ).group_by(RecommendationFeedback.experience_id)
    )
    scores: dict[int, float] = {}
    for experience_id, total, helpful in session.execute(statement).all():
        total = int(total or 0)
        helpful = int(helpful or 0)
        if total:
            scores[int(experience_id)] = (helpful - (total - helpful)) / total
    return scores


@router.post("/recommend", response_model=RecommendationResponse, summary="Ranked feasible recommendations")
@limiter.limit(RECOMMEND_LIMIT)
async def get_recommendations(
    request: Request,
    response: Response,
    payload: RecommendationRequest,
    session: Session = Depends(get_session),
):
    """Validate constraints -> feasibility filter -> weather-aware ranking."""
    cache_key = _recommend_cache_key(payload)
    if settings.recommend_cache_enabled:
        cached = _recommend_cache.get(cache_key)
        if cached is not None:
            return cached

    logger.info(
        "Recommend request: location=%s time=%s budget=%s interests=%s",
        payload.location,
        payload.time_hours,
        payload.budget_inr,
        payload.interests,
    )

    # The full pool size is reported to the client ("12 -> 4" reveal), so count
    # it separately from the candidate set we score.
    total_candidates = int(session.exec(select(func.count()).select_from(Experience)).one())

    # Semantic retrieval branch: embed intent, retrieve top-K by vector similarity,
    # then feasibility-filter + re-rank. Falls back to SQL keyword retrieval when
    # semantic is disabled or no query text is available.
    semantic_query = (payload.semantic_query or " ".join(payload.interests or [])).strip()
    use_semantic = payload.use_semantic and bool(semantic_query)

    if use_semantic:
        logger.info("Semantic recommend query: %s", semantic_query[:80])
        candidate_ids = await semantic_search(
            session,
            semantic_query,
            top_k=max(50, payload.limit * 5),
            required_tags=payload.required_tags or None,
            excluded_tags=payload.excluded_tags or None,
            category=payload.interests[0] if payload.interests else None,
            indoor_outdoor=None,
            lat=payload.origin_lat,
            lng=payload.origin_lng,
            radius_km=30.0 if payload.origin_lat is not None else None,
        )
        if candidate_ids:
            candidates = list(session.exec(select(Experience).where(Experience.id.in_(candidate_ids))).all())
            # Preserve semantic order.
            order = {exp_id: idx for idx, exp_id in enumerate(candidate_ids)}
            candidates.sort(key=lambda e: order.get(e.id, 9999))
        else:
            candidates = []
    else:
        # Budget is a hard feasibility filter, so apply it in SQL and only load rows
        # that can survive. Everything else (time, hours, distance, accessibility)
        # stays in the ranking engine.
        stmt = select(Experience)
        if payload.budget_inr is not None:
            stmt = stmt.where(Experience.avg_cost <= payload.budget_inr)
        if payload.required_tags:
            stmt = _apply_tag_filters(stmt, payload.required_tags, payload.excluded_tags)
        candidates = list(session.exec(stmt).all())

    # Weather is best-effort: failure yields neutral context, never 500.
    try:
        weather = await fetch_weather()
    except Exception as exc:  # pragma: no cover - defensive
        logger.warning("Weather service raised unexpectedly: %s", exc)
        from app.services.weather import neutral_weather

        weather = neutral_weather(reason="exception")

    # Tag hit annotations for semantic explanations.
    required = set(payload.required_tags or [])
    semantic_tag_hits: dict[int, list[str]] = {}
    if use_semantic or required:
        for exp in candidates:
            exp_tags = set(exp.tags or [])
            hits = sorted(required & exp_tags)
            if hits:
                semantic_tag_hits[exp.id] = hits

    result = recommender.recommend(
        candidates,
        location=payload.location,
        time_hours=payload.time_hours,
        budget_inr=payload.budget_inr,
        interests=payload.interests,
        accessibility=payload.accessibility,
        start_time=payload.start_time,
        weather=weather,
        feedback_scores=_feedback_scores(session),
        limit=payload.limit,
        semantic_query=semantic_query if use_semantic else None,
        semantic_tag_hits=semantic_tag_hits,
    )

    top = result["results"]
    origin_lat = payload.origin_lat
    origin_lng = payload.origin_lng
    if origin_lat is None or origin_lng is None:
        coords = result.get("user_coords")
        if coords:
            origin_lat, origin_lng = coords

    # --- Route enrichment (optional, always fails safe) ---
    routes: list = [None] * len(top)
    route_source = "local"
    if payload.include_route and origin_lat is not None and origin_lng is not None and top:
        mode = payload.travel_mode.upper()
        travel_mode = mode if mode in VALID_TRAVEL_MODES else "WALK"
        try:
            routes = await google_routes.route_between_many(
                origin_lat,
                origin_lng,
                [(r.experience.lat, r.experience.lng) for r in top],
                travel_mode=travel_mode,  # type: ignore[arg-type]
            )
        except Exception as exc:  # pragma: no cover - defensive
            logger.warning("Route enrichment failed, using local estimates: %s", exc)
            routes = [None] * len(top)
        if any(routes):
            route_source = "google_routes"

    images = await _enrich_images(
        [r.experience.name for r in top],
        origin_lat if origin_lat is not None else 19.076,
        origin_lng if origin_lng is not None else 72.8777,
    )

    weather_block = WeatherContext(
        available=bool(weather.get("available", False)),
        temp_c=weather.get("temp_c"),
        condition=str(weather.get("condition", "unknown")),
        is_rainy=bool(weather.get("is_rainy", False)),
        suitable_outdoor=bool(weather.get("suitable_outdoor", True)),
        description=str(weather.get("description", "")),
    )

    items: list[RecommendationItem] = []
    dropped_by_route: list[str] = []
    for index, scored in enumerate(top):
        exp: Experience = scored.experience
        google_route = routes[index] if index < len(routes) else None

        if google_route is not None:
            distance_km = round(google_route.distance_m / 1000, 2)
            travel_minutes = google_route.duration_min or scored.travel_time_min
            route_info = RouteInfo(
                distance_m=google_route.distance_m,
                duration_s=google_route.duration_s,
                duration_min=travel_minutes,
                polyline=google_route.polyline,
                travel_mode=google_route.travel_mode,
                source=google_route.source,
            )

            # Hard constraints were screened with a fast local estimate. Real
            # route data can be much slower/farther, so re-validate before the
            # result is ever shown: a recommendation must never exceed the
            # requested window or the distance cap.
            recheck = recommender.recheck_with_route(
                exp,
                distance_km=distance_km,
                travel_minutes=travel_minutes,
                time_hours=payload.time_hours,
            )
            if not recheck.ok:
                dropped_by_route.append(f"{exp.name}: {recheck.reason}")
                logger.info("Dropped after route recheck: %s (%s)", exp.name, recheck.reason)
                continue
        else:
            distance_km = scored.distance_km
            travel_minutes = scored.travel_time_min
            route_info = RouteInfo(
                distance_m=int(scored.distance_km * 1000),
                duration_s=travel_minutes * 60,
                duration_min=travel_minutes,
                polyline=None,
                travel_mode=payload.travel_mode.upper()
                if payload.travel_mode.upper() in VALID_TRAVEL_MODES
                else "WALK",
                source="local",
            )

        is_open = recommender.is_open_at(
            exp, recommender.parse_hhmm(payload.start_time), exp.duration_min + 20
        )

        items.append(
            RecommendationItem(
                id=exp.id or 0,
                name=exp.name,
                category=exp.category,
                image=images.get(exp.name) or exp.image_url or None,
                description=exp.description,
                lat=exp.lat,
                lng=exp.lng,
                area="",
                cost=exp.avg_cost,
                estimated_cost=exp.avg_cost,
                rating=exp.rating,
                review_count=0,
                opening_hours=OpeningHoursInfo(
                    open_time=exp.open_time,
                    close_time=exp.close_time,
                    is_open=is_open,
                    label="Open" if is_open else "Closed",
                ),
                duration_min=exp.duration_min,
                distance_km=distance_km,
                travel_time_min=travel_minutes,
                total_time_min=exp.duration_min + travel_minutes * 2 + recommender.BUFFER_MIN,
                weather=weather_block,
                route=route_info,
                why_this_fits=scored.why_this_fits,
                reasons=_reasons_for(exp, payload),
                score=scored.score,
                score_parts=scored.score_parts,
                tags=list(exp.tags or []),
                accessibility_flags=list(exp.accessibility_flags or []),
                indoor_outdoor=exp.indoor_outdoor,
                local_gem_score=exp.local_gem_score,
                source="sqlite",
                experience=ExperienceResponse.model_validate(exp),
            )
        )

    if dropped_by_route:
        logger.info(
            "Route recheck dropped %d/%d recommendations: %s",
            len(dropped_by_route),
            len(top),
            "; ".join(dropped_by_route),
        )

    out = RecommendationResponse(
        total_candidates=total_candidates,
        # Post-enrichment truth: exactly what the client will receive.
        feasible_count=len(items),
        weather_used=result["weather_used"],
        weather_summary=weather.get("description"),
        weather=weather_block,
        route_source=route_source,
        recommendations=items,
    )

    if settings.recommend_cache_enabled:
        _recommend_cache.set(cache_key, out)
    return out


@router.post(
    "/recommendations/{experience_id}/feedback",
    response_model=FeedbackResponse,
    summary="Record thumbs up/down on a recommendation",
)
@limiter.limit(PUBLIC_LIMIT)
def submit_feedback(
    request: Request,
    response: Response,
    experience_id: int,
    payload: FeedbackRequest,
    session: Session = Depends(get_session),
    current_user: User | None = Depends(get_current_user_optional),
):
    """Persist feedback and invalidate cached recommendations.

    Aggregated feedback nudges future ranking via ``FEEDBACK_WEIGHT``.
    """
    experience = session.get(Experience, experience_id)
    if experience is None:
        raise HTTPException(status_code=404, detail="Experience not found")

    session.add(
        RecommendationFeedback(
            user_id=current_user.id if current_user else None,
            experience_id=experience_id,
            helpful=payload.helpful,
            location=payload.location,
            interests=payload.interests,
        )
    )
    session.commit()
    clear_recommend_cache()
    logger.info("Feedback recorded: experience=%s helpful=%s", experience_id, payload.helpful)
    return FeedbackResponse(experience_id=experience_id, helpful=payload.helpful)


def _reasons_for(exp: Experience, payload: RecommendationRequest) -> list[str]:
    """Deterministic bullet reasons (no LLM, stable across runs)."""
    reasons: list[str] = []
    if payload.budget_inr is not None and exp.avg_cost <= payload.budget_inr:
        reasons.append(f"Fits your budget (₹{payload.budget_inr})")
    if payload.time_hours is not None and exp.duration_min <= payload.time_hours * 60:
        hours = int(payload.time_hours)
        reasons.append(f"Works inside your {hours} hour window")
    if exp.rating >= 4.5:
        reasons.append(f"Highly rated ({exp.rating:.1f}★)")
    if exp.local_gem_score >= 0.85:
        reasons.append("A genuine local gem")
    flags = [f.lower() for f in (exp.accessibility_flags or [])]
    if any("wheelchair" in f for f in flags):
        reasons.append("Wheelchair accessible")
    elif any("step-free" in f for f in flags):
        reasons.append("Step-free access")
    if exp.indoor_outdoor == "indoor":
        reasons.append("Indoor, so the weather cannot ruin it")
    reasons.append("Close to other recommended places")
    return reasons[:5]
