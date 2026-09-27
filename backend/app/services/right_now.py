"""Context-Aware "Right Now" Engine (PRD 4.8).

Turns current conditions into a single 0-100 score per experience plus a short,
human-readable context panel explaining it, and re-ranks a feed around it.

Five components, weighted to 1.0:

* **quality**   base desirability (rating + local-gem score)
* **weather**   suitability for the current/next-hours conditions
* **time**      time-of-day fit (sunrise/sunset, meal windows, night spots)
* **crowd**     expected crowd from the venue's density + hour-of-day priors
* **safety**    late-night / lighting context

Everything is deterministic and degrades gracefully with no weather or sun
data, so it is safe to call on every request and easy to test.
"""

from __future__ import annotations

import logging
from datetime import datetime, timezone
from typing import Any

from sqlmodel import Session, select

from app.models import Experience, User
from app.services import graphs, reranker, taste
from app.services.context import IST
from app.services.recommender import parse_hhmm
from app.services.weather import MUMBAI_LAT, MUMBAI_LON

logger = logging.getLogger(__name__)

# Component weights (sum to 1.0).
W_QUALITY = 0.30
W_WEATHER = 0.25
W_TIME = 0.20
W_CROWD = 0.15
W_SAFETY = 0.10

CROWD_SCORE = {"LOW": 0.95, "MEDIUM": 0.70, "HIGH": 0.40, "CLOSED": 0.0}

#: Minutes around sunset/sunrise that count as the "golden window".
GOLDEN_WINDOW_MIN = 75
_SUNSET_TAGS = {
    "sunset", "views", "viewpoint", "good_for_photos", "photography",
    "sea_view", "sea_face", "skyline", "rooftop",
}
_SUNRISE_TAGS = {"sunrise", "early_morning", "good_for_morning_walk", "morning"}

#: Blend of the taste/route reranker and the live Right Now score in a feed.
FEED_RERANK_WEIGHT = 0.55
FEED_RIGHT_NOW_WEIGHT = 0.45


def now_minutes(now: datetime | None = None) -> int:
    """Minutes since local midnight (IST) for the given/current moment.

    The clocks here are Mumbai clocks: a UTC ``datetime`` is converted to IST
    rather than read as if it were already local, which used to shift the whole
    time-of-day and safety model by 5h30m.
    """
    moment = now or datetime.now(timezone.utc)
    if moment.tzinfo is None:
        moment = moment.replace(tzinfo=timezone.utc)
    local = moment.astimezone(IST)
    return local.hour * 60 + local.minute


def is_weekend(now: datetime | None = None) -> bool:
    """True when it is Saturday/Sunday in Mumbai (not in UTC)."""
    moment = now or datetime.now(timezone.utc)
    if moment.tzinfo is None:
        moment = moment.replace(tzinfo=timezone.utc)
    return moment.astimezone(IST).weekday() >= 5


def _fmt(minutes: int) -> str:
    minutes %= 24 * 60
    return f"{minutes // 60:02d}:{minutes % 60:02d}"


def _quality_score(exp: Experience) -> float:
    return max(
        0.0, min(1.0, 0.6 * (exp.rating / 5.0) + 0.4 * (exp.local_gem_score or 0.0))
    )


def _crowd_score(exp: Experience, now_min: int, *, weekend: bool) -> tuple[float, str | None]:
    level = (exp.crowd_density_level or "MEDIUM").upper()
    score = CROWD_SCORE.get(level, 0.70)
    hour = (now_min // 60) % 24
    note: str | None = None
    peak = (11 <= hour <= 14) or (17 <= hour <= 20)
    if peak:
        score -= 0.15
        note = "Peak hours — expect a crowd"
    if weekend:
        score -= 0.05
        note = note or "Weekend — busier than usual"
    score = max(0.0, min(1.0, score))
    # Let a genuinely quiet venue say so, so the panel is not one repeated line.
    if note is None:
        if level in ("LOW", "QUIET"):
            note = "Quiet right now — a good window"
        elif level in ("HIGH", "BUSY", "VERY_HIGH", "VERY_BUSY"):
            note = "A popular spot — expect a crowd"
    return score, note


def _safety_score(exp: Experience, now_min: int) -> tuple[float, str | None]:
    hour = (now_min // 60) % 24
    if hour >= 22 or hour < 5:
        if reranker.outdoorish(exp):
            return 0.50, "Late-night outdoors — stick to lit, busy areas"
        return 0.85, None
    return 0.90, None


def _sun_adjustment(
    exp: Experience, now_min: int, sun: dict[str, Any]
) -> tuple[float, str | None]:
    """Golden-hour lift for sunset/sunrise-oriented venues."""
    if not sun or not sun.get("available"):
        return 0.0, None
    tags = {taste.normalize_tag(t) for t in (exp.tags or [])}
    sunset = parse_hhmm(sun.get("sunset"))
    if sunset is not None and tags & _SUNSET_TAGS:
        delta = sunset - now_min
        if 0 <= delta <= GOLDEN_WINDOW_MIN:
            return 0.25, f"Sunset at {sun['sunset']} — prime viewing window"
    sunrise = parse_hhmm(sun.get("sunrise"))
    if sunrise is not None and tags & _SUNRISE_TAGS:
        delta = sunrise - now_min
        if 0 <= delta <= GOLDEN_WINDOW_MIN:
            return 0.25, f"Sunrise at {sun['sunrise']} — catch the early light"
    return 0.0, None


def label_for_score(score: float) -> str:
    if score >= 82:
        return "Great right now"
    if score >= 68:
        return "Good right now"
    if score >= 52:
        return "Okay right now"
    return "Better later"


def score_for(
    exp: Experience,
    *,
    weather: dict[str, Any] | None = None,
    sun: dict[str, Any] | None = None,
    now_min: int | None = None,
    weekend: bool | None = None,
) -> dict[str, Any]:
    """Compute the Right Now score, components and context lines."""
    now_min = now_min if now_min is not None else now_minutes()
    weekend = weekend if weekend is not None else is_weekend()
    weather = weather or {}
    sun = sun or {}

    quality = _quality_score(exp)
    weather_fit, weather_note = reranker.weather_score(exp, weather)
    time_fit, time_note = reranker.time_of_day_score(exp, _fmt(now_min))
    crowd, crowd_note = _crowd_score(exp, now_min, weekend=weekend)
    safety, safety_note = _safety_score(exp, now_min)

    sun_delta, sun_note = _sun_adjustment(exp, now_min, sun)
    time_fit = max(0.0, min(1.0, time_fit + sun_delta))

    components = {
        "quality": round(quality, 4),
        "weather": round(weather_fit, 4),
        "time": round(time_fit, 4),
        "crowd": round(crowd, 4),
        "safety": round(safety, 4),
    }
    weighted = (
        quality * W_QUALITY
        + weather_fit * W_WEATHER
        + time_fit * W_TIME
        + crowd * W_CROWD
        + safety * W_SAFETY
    )
    score = round(weighted * 100.0, 1)

    context: list[str] = []
    for note in (sun_note, weather_note, crowd_note, safety_note, time_note):
        if note:
            context.append(note)
    if not context:
        context.append("Conditions look steady right now")

    return {
        "score": score,
        "label": label_for_score(score),
        "components": components,
        "context": context[:3],
        "computed_at": datetime.now(timezone.utc).isoformat(),
    }


# ---------------------------------------------------------------------------
# Persistence / refresh
# ---------------------------------------------------------------------------


async def refresh_scores(
    session: Session,
    *,
    lat: float | None = None,
    lng: float | None = None,
    limit: int | None = None,
) -> int:
    """Recompute and store Right Now scores for the catalogue (or a slice)."""
    from app.services.weather import fetch_sun_times, fetch_weather

    lat = MUMBAI_LAT if lat is None else lat
    lng = MUMBAI_LON if lng is None else lng
    weather = await fetch_weather(lat, lng)
    sun = await fetch_sun_times(lat, lng)
    moment = datetime.now(timezone.utc)
    now_min = now_minutes(moment)

    stmt = select(Experience)
    if limit:
        stmt = stmt.limit(max(1, limit))
    rows = list(session.exec(stmt).all())

    for exp in rows:
        result = score_for(exp, weather=weather, sun=sun, now_min=now_min)
        exp.right_now_score = result["score"]
        exp.right_now_context_json = {
            "label": result["label"],
            "context": result["context"],
            "components": result["components"],
        }
        exp.right_now_updated_at = moment
        session.add(exp)
    session.commit()
    return len(rows)


# ---------------------------------------------------------------------------
# Feed
# ---------------------------------------------------------------------------


def right_now_feed(
    session: Session,
    user: User | None,
    *,
    lat: float | None = None,
    lng: float | None = None,
    time_hours: float | None = None,
    budget_inr: int | None = None,
    start_time: str | None = None,
    weather: dict[str, Any] | None = None,
    sun: dict[str, Any] | None = None,
    limit: int = 10,
    now_min: int | None = None,
) -> list[dict[str, Any]]:
    """Blend the taste/route reranker with the live Right Now score."""
    pool = graphs.taste_aware_recommend(
        session,
        user,
        lat=lat,
        lng=lng,
        time_hours=time_hours,
        budget_inr=budget_inr,
        start_time=start_time,
        weather=weather or {},
        limit=max(limit * 4, 40),
    )
    weekend = is_weekend()
    items: list[dict[str, Any]] = []
    for ranked in pool:
        result = score_for(
            ranked.experience, weather=weather, sun=sun, now_min=now_min, weekend=weekend
        )
        final = (
            ranked.score * FEED_RERANK_WEIGHT
            + (result["score"] / 100.0) * FEED_RIGHT_NOW_WEIGHT
        )
        items.append(
            {
                "experience": ranked.experience,
                "right_now_score": result["score"],
                "right_now_label": result["label"],
                "context": result["context"],
                "components": result["components"],
                "rerank_score": round(ranked.score, 4),
                "final_score": round(final, 4),
                "distance_km": ranked.distance_km,
                "travel_time_min": ranked.travel_time_min,
                "why": ranked.why,
            }
        )
    items.sort(key=lambda item: item["final_score"], reverse=True)
    return items[:limit]
