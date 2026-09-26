"""Explainable re-ranking layer (PRD 4.1.2 / 4.8).

Sits *in front of* search and recommendation results and reorders a candidate
pool with transparent components: travel cost, weather suitability, time-of-day
fit and the user's taste vector. Every score carries its parts so the UI (and
the companion agent) can explain *why* something moved up or down.

Deterministic and dependency-free: it never calls out to a network service, so
it is safe to run on every request and easy to unit-test.
"""

from __future__ import annotations

import math
from dataclasses import dataclass, field
from typing import Any

from app.models import Experience
from app.services import recommender, taste

# Component weights. They deliberately sum to 1.0 so scores stay in [0, 1].
W_BASE = 0.25
W_TASTE = 0.30
W_PROXIMITY = 0.20
W_WEATHER = 0.15
W_TIME_OF_DAY = 0.10

# Distance at which proximity is essentially irrelevant (~Dhaka? no, Mumbai).
PROXIMITY_SCALE_KM = 8.0

# Tags that only make sense at particular hours (24h, local).
_TIME_TAGS: dict[str, tuple[int, int]] = {
    "sunrise": (5, 8),
    "good_for_morning_walk": (5, 10),
    "good_for_breakfast": (7, 11),
    "morning": (5, 11),
    "good_for_lunch": (11, 15),
    "lunch": (11, 15),
    "good_for_photos": (6, 19),
    "sunset": (16, 20),
    "good_for_evening_snacks": (16, 21),
    "evening": (16, 22),
    "good_for_night_walk": (19, 24),
    "late_night": (21, 24),
    "night_view": (19, 24),
}


@dataclass
class RerankContext:
    """Everything needed to re-rank, captured at request time."""

    lat: float | None = None
    lng: float | None = None
    time_hours: float | None = None
    budget_inr: int | None = None
    start_time: str | None = None
    weather: dict[str, Any] = field(default_factory=dict)
    taste_vector: dict[str, float] = field(default_factory=dict)
    travel_mode: str = "WALK"
    drop_infeasible: bool = True


@dataclass
class Reranked:
    experience: Experience
    score: float
    parts: dict[str, float]
    distance_km: float
    travel_time_min: int
    why: list[str]


def _proximity(distance_km: float) -> float:
    return math.exp(-max(0.0, distance_km) / PROXIMITY_SCALE_KM)


def _weather_score(exp: Experience, weather: dict[str, Any]) -> tuple[float, str | None]:
    """1.0 = perfect for the conditions, 0.0 = bad fit."""
    if not weather or not weather.get("available"):
        return 0.6, None  # neutral: unknown weather should not swing the ranking
    rainy = bool(weather.get("is_rainy"))
    suitable_outdoor = bool(weather.get("suitable_outdoor", True))
    indoor = (exp.indoor_outdoor or "").lower() == "indoor"
    if rainy or not suitable_outdoor:
        return (1.0, "Indoor — safe from the rain") if indoor else (0.15, "Rain may disrupt this")
    # Clear weather: outdoor gets a small lift, indoor stays fine.
    return (0.85 if outdoorish(exp) else 0.7), None


def outdoorish(exp: Experience) -> bool:
    if (exp.indoor_outdoor or "").lower() == "outdoor":
        return True
    tags = {taste.normalize_tag(t) for t in (exp.tags or [])}
    return bool(tags & {"outdoor", "beach", "nature", "sunset", "sunrise", "views", "walking"})


def _time_of_day_score(exp: Experience, start_time: str | None) -> tuple[float, str | None]:
    if not start_time:
        return 0.6, None
    hour = recommender.parse_hhmm(start_time).hour
    tags = {taste.normalize_tag(t) for t in (exp.tags or [])}
    best = 0.6
    note: str | None = None
    for tag, (lo, hi) in _TIME_TAGS.items():
        if tag in tags:
            if lo <= hour < hi:
                if 0.95 > best:
                    best, note = 0.95, f"Best around {lo:02d}:00–{hi:02d}:00"
            else:
                best = min(best, 0.35)
                note = note or f"Better between {lo:02d}:00–{hi:02d}:00"
    return best, note


def score_experience(exp: Experience, ctx: RerankContext) -> Reranked:
    """Score one experience; assumes it already passed hard feasibility."""
    distance_km = 0.0
    travel_min = 0
    if ctx.lat is not None and ctx.lng is not None:
        distance_km = recommender.haversine_km(ctx.lat, ctx.lng, exp.lat, exp.lng)
        travel_min = recommender.estimate_travel_time_min(distance_km)

    base = 0.6 * (exp.rating / 5.0) + 0.4 * (exp.local_gem_score or 0.0)
    taste_score = 0.0
    if ctx.taste_vector:
        # Map [-1, 1] similarity onto [0, 1]; negatives are penalised.
        taste_score = (taste.experience_taste_score(exp, ctx.taste_vector) + 1.0) / 2.0
    proximity = _proximity(distance_km) if ctx.lat is not None else 0.5
    weather_score, weather_note = _weather_score(exp, ctx.weather)
    tod_score, tod_note = _time_of_day_score(exp, ctx.start_time)

    parts = {
        "base": round(base * W_BASE, 4),
        "taste": round(taste_score * W_TASTE, 4),
        "proximity": round(proximity * W_PROXIMITY, 4),
        "weather": round(weather_score * W_WEATHER, 4),
        "time_of_day": round(tod_score * W_TIME_OF_DAY, 4),
    }
    score = sum(parts.values())

    why: list[str] = []
    if ctx.taste_vector and taste_score > 0.65:
        top = taste._top_tags(ctx.taste_vector, positive=True, limit=2)
        if top:
            why.append("Matches your taste for " + ", ".join(top))
    if travel_min and travel_min <= 20:
        why.append(f"Only ~{travel_min} min away")
    if weather_note:
        why.append(weather_note)
    if tod_note:
        why.append(tod_note)

    return Reranked(
        experience=exp,
        score=round(score, 4),
        parts=parts,
        distance_km=round(distance_km, 2),
        travel_time_min=travel_min,
        why=why,
    )


def rerank(
    experiences: list[Experience], ctx: RerankContext, *, limit: int | None = None
) -> list[Reranked]:
    """Filter (hard feasibility) then re-rank a candidate pool.

    When ``ctx.drop_infeasible`` is set, experiences that cannot fit the user's
    time window once travel is counted are removed, which is the "if it takes
    too long to get there, don't show it" rule from the PRD.
    """
    scored: list[Reranked] = []
    for exp in experiences:
        if ctx.drop_infeasible and ctx.time_hours:
            travel_min = 0
            if ctx.lat is not None and ctx.lng is not None:
                d = recommender.haversine_km(ctx.lat, ctx.lng, exp.lat, exp.lng)
                travel_min = recommender.estimate_travel_time_min(d)
            total = exp.duration_min + travel_min * 2 + recommender.BUFFER_MIN
            if total > ctx.time_hours * 60:
                continue
        scored.append(score_experience(exp, ctx))

    scored.sort(key=lambda r: r.score, reverse=True)
    return scored[:limit] if limit else scored


def rerank_dicts(experiences: list[Experience], ctx: RerankContext, *, limit: int | None = None) -> list[dict[str, Any]]:
    """Convenience wrapper returning plain dicts for API/agent use."""
    return [
        {
            "experience": r.experience,
            "score": r.score,
            "parts": r.parts,
            "distance_km": r.distance_km,
            "travel_time_min": r.travel_time_min,
            "why": r.why,
        }
        for r in rerank(experiences, ctx, limit=limit)
    ]
