"""Google Places API (New) integration, normalized into LocalIQ models.

The server-side key (``GOOGLE_PLACES_API_KEY``) is only ever used from this
process. Photos are exposed to clients through a LocalIQ proxy endpoint, so the
key never appears in a URL handed to Flutter.

Every function degrades gracefully: with no key, a network error, or a quota
error, the caller receives ``None`` / an empty result and is expected to fall
back to the local SQLite dataset.
"""

from __future__ import annotations

import logging
from typing import Any
from urllib.parse import quote

import httpx
from pydantic import BaseModel, Field

from app.config import get_settings

logger = logging.getLogger(__name__)

PLACES_TEXT_SEARCH_URL = "https://places.googleapis.com/v1/places:searchText"
PLACES_NEARBY_URL = "https://places.googleapis.com/v1/places:searchNearby"
PHOTO_MEDIA_PATH = "/api/v1/images/place"

TEXT_SEARCH_FIELDS = ",".join(
    [
        "places.id",
        "places.displayName",
        "places.formattedAddress",
        "places.location",
        "places.rating",
        "places.userRatingCount",
        "places.priceLevel",
        "places.primaryType",
        "places.types",
        "places.photos",
        "places.regularOpeningHours.weekdayDescriptions",
        "places.regularOpeningHours.openNow",
        "places.googleMapsUri",
        "places.businessStatus",
    ]
)
# NB: "places.shortDescription" is not part of Places API (New) Text Search /
# Nearby Search. Requesting it makes Google reject the whole field mask with
# HTTP 400 ("Cannot find matching fields for path"), which silently disabled
# every Places call. Descriptions are therefore empty for Google results; the
# curated SQLite rows keep their own.

# Google primary types -> LocalIQ categories.
TYPE_TO_CATEGORY: dict[str, str] = {
    "restaurant": "food",
    "cafe": "food",
    "bakery": "food",
    "bar": "nightlife",
    "night_club": "nightlife",
    "tourist_attraction": "culture",
    "historical_landmark": "culture",
    "place_of_worship": "culture",
    "museum": "art",
    "art_gallery": "art",
    "performing_arts_theater": "art",
    "shopping_mall": "shopping",
    "market": "shopping",
    "clothing_store": "shopping",
    "park": "outdoor",
    "tourist_attraction_outdoor": "outdoor",
    "beach": "outdoor",
}

PRICE_LEVEL_TO_INR: dict[str, int] = {
    "PRICE_LEVEL_FREE": 0,
    "PRICE_LEVEL_INEXPENSIVE": 200,
    "PRICE_LEVEL_MODERATE": 600,
    "PRICE_LEVEL_EXPENSIVE": 1500,
    "PRICE_LEVEL_VERY_EXPENSIVE": 4000,
}

TIMEOUT_S = 8.0


class PlacesResult(BaseModel):
    """Normalized place, independent of Google's response shape."""

    google_place_id: str = Field(default="")
    name: str
    category: str = "culture"
    address: str = ""
    description: str = ""
    lat: float
    lng: float
    rating: float = 0.0
    review_count: int = 0
    avg_cost: int = 0
    image_url: str | None = None
    photo_name: str | None = None
    open_time: str | None = None
    close_time: str | None = None
    open_now: bool | None = None
    google_maps_uri: str | None = None
    source: str = "google_places"


def _api_key() -> str:
    """Server-restricted Places key. Empty means 'feature disabled'."""
    return get_settings().google_places_api_key.strip()


def is_configured() -> bool:
    return bool(_api_key())


def photo_proxy_url(photo_name: str | None) -> str | None:
    """LocalIQ URL that streams a Google photo without leaking the key."""
    if not photo_name:
        return None
    return f"{PHOTO_MEDIA_PATH}?name={quote(photo_name, safe='')}"


def _parse_opening_hours(hours: dict[str, Any] | None) -> tuple[str | None, str | None, bool | None]:
    """Pull open/close times and openNow out of regularOpeningHours."""
    if not hours:
        return None, None, None
    descriptions = hours.get("weekdayDescriptions") or []
    if not descriptions:
        return None, None, hours.get("openNow")
    # e.g. "Monday: 8:00 AM – 11:00 PM"
    today_index = datetime_weekday_index()
    entry = None
    for text in descriptions:
        if not isinstance(text, str):
            continue
        if text.lower().startswith(today_index):
            entry = text
            break
    if entry is None:
        return None, None, hours.get("openNow")
    _, _, span = entry.partition(": ")
    if "–" not in span and "-" not in span:
        return None, None, hours.get("openNow")
    separator = "–" if "–" in span else "-"
    parts = span.split(separator)
    if len(parts) != 2:
        return None, None, hours.get("openNow")
    return _to_24h(parts[0]), _to_24h(parts[1]), hours.get("openNow")


def datetime_weekday_index() -> str:
    from datetime import datetime

    return datetime.now().strftime("%A").lower()


def _to_24h(value: str) -> str | None:
    """Convert '8:00 AM' -> '08:00'. Returns None when unparseable."""
    text = value.strip().upper()
    for suffix in ("AM", "PM"):
        if text.endswith(suffix):
            period = suffix
            text = text[: -len(suffix)].strip()
            break
    else:
        return None
    if ":" not in text:
        return None
    hour_text, _, minute_text = text.partition(":")
    try:
        hour = int(hour_text)
        minute = int(minute_text[:2])
    except ValueError:
        return None
    if period == "PM" and hour < 12:
        hour += 12
    if period == "AM" and hour == 12:
        hour = 0
    if not (0 <= hour <= 23 and 0 <= minute <= 59):
        return None
    return f"{hour:02d}:{minute:02d}"


def normalize_place(raw: dict[str, Any]) -> PlacesResult:
    """Map one Google place payload to our own model."""
    location = raw.get("location") or {}
    lat = float(location.get("latitude") or 0.0)
    lng = float(location.get("longitude") or 0.0)

    types = [str(t) for t in (raw.get("types") or [])]
    primary = str(raw.get("primaryType") or "")
    category = TYPE_TO_CATEGORY.get(primary, "")
    if not category:
        for candidate in types:
            category = TYPE_TO_CATEGORY.get(candidate, "")
            if category:
                break
    if not category:
        category = "culture"

    display_name = raw.get("displayName") or {}
    name = str(display_name.get("text") or "Unknown place")

    photos = raw.get("photos") or []
    photo_name = str(photos[0].get("name")) if photos and isinstance(photos[0], dict) else None

    open_time, close_time, open_now = _parse_opening_hours(raw.get("regularOpeningHours"))

    return PlacesResult(
        google_place_id=str(raw.get("id") or ""),
        name=name,
        category=category,
        address=str(raw.get("formattedAddress") or ""),
        description=str(raw.get("description") or ""),
        lat=lat,
        lng=lng,
        rating=float(raw.get("rating") or 0.0),
        review_count=int(raw.get("userRatingCount") or 0),
        avg_cost=PRICE_LEVEL_TO_INR.get(str(raw.get("priceLevel") or ""), 0),
        image_url=photo_proxy_url(photo_name),
        photo_name=photo_name,
        open_time=open_time,
        close_time=close_time,
        open_now=open_now,
        google_maps_uri=raw.get("googleMapsUri"),
    )


async def _post_json(url: str, payload: dict[str, Any], field_mask: str) -> dict[str, Any]:
    key = _api_key()
    headers = {"X-Goog-Api-Key": key, "X-Goog-FieldMask": field_mask}
    async with httpx.AsyncClient(timeout=TIMEOUT_S) as client:
        response = await client.post(url, json=payload, headers=headers)
        response.raise_for_status()
        return response.json()


async def search_places(
    text_query: str,
    *,
    lat: float | None = None,
    lng: float | None = None,
    radius_m: int = 8000,
    page_size: int = 10,
) -> list[PlacesResult]:
    """Text Search. Returns ``[]`` when unavailable (caller falls back)."""
    if not text_query.strip() or not is_configured():
        return []
    payload: dict[str, Any] = {
        "textQuery": text_query.strip(),
        "pageSize": max(1, min(page_size, 20)),
        "languageCode": "en",
    }
    if lat is not None and lng is not None:
        payload["locationBias"] = {
            "circle": {
                "center": {"latitude": lat, "longitude": lng},
                "radius": max(100, min(radius_m, 50000)),
            }
        }
    try:
        data = await _post_json(PLACES_TEXT_SEARCH_URL, payload, TEXT_SEARCH_FIELDS)
    except Exception as exc:
        logger.warning("Google Places text search failed: %s", exc)
        return []
    places = data.get("places") or []
    return [normalize_place(p) for p in places if isinstance(p, dict)]


async def search_nearby(
    lat: float,
    lng: float,
    *,
    radius_m: int = 3000,
    included_types: list[str] | None = None,
    page_size: int = 20,
) -> list[PlacesResult]:
    """Nearby Search. Returns ``[]`` when unavailable."""
    if not is_configured():
        return []
    payload: dict[str, Any] = {
        "includedTypes": included_types or ["restaurant", "tourist_attraction", "cafe"],
        "maxResultCount": max(1, min(page_size, 20)),
        "locationRestriction": {
            "circle": {
                "center": {"latitude": lat, "longitude": lng},
                "radius": max(100, min(radius_m, 50000)),
            }
        },
        "languageCode": "en",
    }
    try:
        data = await _post_json(PLACES_NEARBY_URL, payload, TEXT_SEARCH_FIELDS)
    except Exception as exc:
        logger.warning("Google Places nearby search failed: %s", exc)
        return []
    places = data.get("places") or []
    return [normalize_place(p) for p in places if isinstance(p, dict)]


async def fetch_photo(photo_name: str, max_width_px: int = 800) -> tuple[bytes, str] | None:
    """Fetch photo bytes with the server key. Returns ``(bytes, content_type)``.

    The key stays in this process; clients only ever see the proxied bytes.
    """
    if not photo_name or not is_configured():
        return None
    # A photo resource name looks like "places/<place_id>/photos/<photo_ref>".
    # The media endpoint is /v1/<name>/media, so the "places/" prefix must be
    # kept exactly once (stripping it produced a 404 for every photo).
    resource = photo_name.removeprefix("/")
    if not resource.startswith("places/"):
        resource = f"places/{resource}"
    url = f"https://places.googleapis.com/v1/{resource}/media"
    try:
        async with httpx.AsyncClient(timeout=TIMEOUT_S, follow_redirects=True) as client:
            response = await client.get(
                url,
                params={"maxWidthPx": max(100, min(max_width_px, 1600)), "key": _api_key()},
            )
            response.raise_for_status()
            content_type = response.headers.get("content-type", "image/jpeg")
            return response.content, content_type
    except Exception as exc:
        logger.warning("Google photo fetch failed: %s", exc)
        return None


async def google_health() -> dict:
    """Non-fatal health probe for the status endpoint."""
    if not is_configured():
        return {"configured": False, "available": False, "reason": "no_server_key"}
    try:
        data = await search_places("Bandra", page_size=1)
        return {"configured": True, "available": bool(data), "reason": None if data else "empty_response"}
    except Exception as exc:  # pragma: no cover - defensive
        return {"configured": True, "available": False, "reason": str(exc)[:120]}
