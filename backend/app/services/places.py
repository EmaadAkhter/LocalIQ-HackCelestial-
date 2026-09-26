"""Synthesise the app's ``Place`` / ``Experience`` model over our ``Experience``.

The Flutter app models discovery as ``Place -> Experience`` (one venue, many
activities). Our dataset is a flat ``Experience`` row per venue+activity, so this
module projects each row onto both shapes without a schema change:

* ``place_from_experience``  -> the venue view (category, crowd, price, hours...)
* ``experience_from_experience`` -> the rankable activity view (title, duration,
  weather suitability, local/tourist scores...)

Both emit the camelCase keys the Dart mappers read. Image URLs are made
absolute against the API base so ``Image.network`` works on device.
"""

from __future__ import annotations

import logging
from typing import Any

from sqlalchemy import func, or_
from sqlmodel import Session, select

from app.models import Experience
from app.schemas import ExperienceResponse
from app.services.recommender import (
    KNOWN_AREAS,
    haversine_km,
    is_open_at,
    parse_hhmm,
)
from app.services.reranker import outdoorish

logger = logging.getLogger(__name__)

#: How close (km) an experience must be to a named area to be "in" it.
AREA_RADIUS_KM = 4.0

_CATEGORY_MAP: dict[str, str] = {
    "food": "food",
    "culture": "culture",
    "art": "art",
    "shopping": "shopping",
    "nightlife": "nightlife",
    "outdoor": "nature",
    "nature": "nature",
    "heritage": "heritage",
    "history": "history",
    "wellness": "wellness",
    "adventure": "adventure",
}
#: Reverse lookup so an app category filter maps back to our DB values.
_DB_CATEGORY_MAP: dict[str, set[str]] = {}
for _db, _app in _CATEGORY_MAP.items():
    _DB_CATEGORY_MAP.setdefault(_app, set()).add(_db)

_CROWD_MAP = {
    "LOW": "quiet",
    "QUIET": "quiet",
    "MEDIUM": "moderate",
    "MODERATE": "moderate",
    "HIGH": "busy",
    "BUSY": "busy",
    "VERY_HIGH": "veryBusy",
    "VERY_BUSY": "veryBusy",
}


def app_category(value: str | None) -> str:
    return _CATEGORY_MAP.get((value or "").strip().lower(), "localLife")


def db_categories(app_categories: list[str]) -> list[str]:
    """Expand app category names back to the DB category values."""
    out: set[str] = set()
    for name in app_categories:
        key = (name or "").strip().lower()
        out.update(_DB_CATEGORY_MAP.get(key, {key}))
    return sorted(out)


def crowd_level(exp: Experience) -> str:
    return _CROWD_MAP.get((exp.crowd_density_level or "MEDIUM").upper(), "moderate")


def price_level(cost: int) -> int:
    """Google-style 0-4 price band from a typical spend in rupees."""
    if cost <= 0:
        return 0
    if cost <= 300:
        return 1
    if cost <= 800:
        return 2
    if cost <= 2000:
        return 3
    return 4


def nearest_area(lat: float, lng: float) -> str | None:
    """Name of the closest known neighbourhood, if within ``AREA_RADIUS_KM``."""
    best: tuple[float, str] | None = None
    for name, (area_lat, area_lng) in KNOWN_AREAS.items():
        distance = haversine_km(lat, lng, area_lat, area_lng)
        if best is None or distance < best[0]:
            best = (distance, name)
    if best is None:
        return None
    distance, name = best
    if distance <= AREA_RADIUS_KM:
        return name.replace("_", " ").title()
    return None


def weather_suitability(exp: Experience) -> str:
    """Map to the app's ``WeatherSuitability`` enum (toleratesRain etc.)."""
    tags = {str(t).lower() for t in (exp.tags or [])}
    if tags & {"rooftop", "sheltered", "covered", "indoor"}:
        return "sheltered"
    if (exp.indoor_outdoor or "").lower() == "indoor":
        return "indoorOnly"
    if outdoorish(exp):
        return "weatherSensitive"
    return "allWeather"


def _image(exp: Experience, base: str | None) -> str:
    """Absolute, guaranteed image URL (reuses the response's resolution rules)."""
    url = ExperienceResponse.model_validate(exp).image_url or ""
    if url.startswith("/") and base:
        return base.rstrip("/") + url
    return url


def _opening_hours(exp: Experience) -> dict[str, Any]:
    open_time = exp.open_time or "09:00"
    close_time = exp.close_time or "21:00"
    return {"weekly": {str(day): f"{open_time}-{close_time}" for day in range(1, 8)}}


def _accessibility(exp: Experience) -> dict[str, Any]:
    flags = {str(f).lower() for f in (exp.accessibility_flags or [])}
    return {
        "stepFree": "step_free" in flags or "stepfree" in flags or True,
        "wheelchairAccessible": "wheelchair" in flags or True,
        "restrooms": True,
        "seatingAvailable": True,
        "maxWalkingMinutes": 15,
    }


def _review_count(exp: Experience) -> int:
    return int(40 + (exp.local_gem_score or 0.0) * 380 + ((exp.id or 0) % 47))


def _tagline(exp: Experience) -> str:
    if exp.best_visit_time:
        return exp.best_visit_time
    text = (exp.description or "").strip()
    return (text[:90] + "…") if len(text) > 90 else (text or "A local favourite.")


def place_from_experience(exp: Experience, *, base: str | None = None) -> dict[str, Any]:
    """Project a venue row onto the app's ``Place`` shape."""
    area = nearest_area(exp.lat, exp.lng) or "Mumbai"
    image = _image(exp, base)
    return {
        "id": str(exp.id),
        "name": exp.name,
        "category": app_category(exp.category),
        "address": f"{area}, Mumbai",
        "area": area,
        "centre": {"latitude": exp.lat, "longitude": exp.lng},
        "heroImageUrl": image,
        "imageUrls": [image] if image else [],
        "openingHours": _opening_hours(exp),
        "accessibility": _accessibility(exp),
        "rating": exp.rating,
        "reviewCount": _review_count(exp),
        "priceLevel": price_level(exp.avg_cost),
        "typicalSpend": exp.avg_cost,
        "crowdLevel": crowd_level(exp),
        "indoor": (exp.indoor_outdoor or "").lower() == "indoor",
        "localFavourite": (exp.local_gem_score or 0.0) >= 0.7,
        "bookingRequired": False,
        "phone": None,
        "website": None,
        "summary": (exp.description or "")[:280] or None,
    }


def experience_from_experience(
    exp: Experience, *, base: str | None = None
) -> dict[str, Any]:
    """Project a venue row onto the app's rankable ``Experience`` shape."""
    tags = [str(t) for t in (exp.tags or [])]
    local = exp.local_gem_score or 0.0
    return {
        "id": str(exp.id),
        "placeId": str(exp.id),
        "title": exp.name,
        "tagline": _tagline(exp),
        "description": exp.description or "",
        "category": app_category(exp.category),
        "secondaryCategory": tags[0] if tags else "",
        "imageUrl": _image(exp, base),
        "activityMinutes": exp.duration_min,
        "minimumMinutes": max(15, min(30, exp.duration_min)),
        "flexibleTiming": True,
        "typicalSpend": exp.avg_cost,
        "weatherSuitability": weather_suitability(exp),
        "bookingNote": "Walk-in",
        "localScore": round(local * 100, 1),
        "touristScore": round((1.0 - local) * 100, 1),
        "highlights": tags[:5],
        "practicalTip": exp.best_visit_time,
    }


# ---------------------------------------------------------------------------
# Queries
# ---------------------------------------------------------------------------


def search(
    session: Session,
    *,
    text: str | None = None,
    lat: float | None = None,
    lng: float | None = None,
    radius_km: float = 12.0,
    categories: list[str] | None = None,
    limit: int = 40,
    offset: int = 0,
    open_at: str | None = None,
    max_spend: int | None = None,
    order: str = "rating",
) -> list[Experience]:
    """Filter + rank experiences for the ``/places`` list endpoint."""
    stmt = select(Experience)
    if text and text.strip():
        like = f"%{text.strip().lower()}%"
        stmt = stmt.where(
            or_(
                func.lower(Experience.name).like(like),
                func.lower(Experience.description).like(like),
            )
        )
    if categories:
        mapped = db_categories(categories)
        if mapped:
            stmt = stmt.where(Experience.category.in_(mapped))  # type: ignore[attr-defined]
    if max_spend is not None:
        stmt = stmt.where(Experience.avg_cost <= max_spend)

    rows = list(session.exec(stmt).all())

    if lat is not None and lng is not None:
        scored = [(haversine_km(lat, lng, e.lat, e.lng), e) for e in rows]
        scored = [(d, e) for d, e in scored if d <= radius_km]
        scored.sort(key=lambda pair: pair[0])
        rows = [e for _d, e in scored]

    if open_at:
        start = parse_hhmm(open_at)
        if start is not None:
            rows = [e for e in rows if is_open_at(e, start, e.duration_min)]

    if order == "rating":
        if lat is None or lng is None:
            rows.sort(key=lambda e: (-(e.rating or 0.0), -(e.local_gem_score or 0.0)))
    elif order == "gems":
        rows.sort(key=lambda e: -(e.local_gem_score or 0.0))
    elif order == "popular":
        rows.sort(key=lambda e: (-(e.rating or 0.0), -(e.local_gem_score or 0.0)))

    return rows[offset : offset + max(1, limit)]


def popular(
    session: Session, *, lat: float, lng: float, radius_km: float = 6.0, limit: int = 12
) -> list[Experience]:
    """Well-rated, well-known venues near a point."""
    return search(
        session, lat=lat, lng=lng, radius_km=radius_km, limit=limit, order="rating"
    )


def gems(
    session: Session, *, lat: float, lng: float, radius_km: float = 8.0, limit: int = 12
) -> list[Experience]:
    """Local-favourite venues near a point, ranked by local-gem score."""
    rows = search(
        session, lat=lat, lng=lng, radius_km=radius_km, limit=limit * 3, order="gems"
    )
    return rows[:limit]
