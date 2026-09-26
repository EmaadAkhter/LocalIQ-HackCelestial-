"""Geocoding for discovered places.

Uses OpenStreetMap Nominatim (free, no key) with the required politeness rules:
a descriptive User-Agent and at most one request per second. Results are cached
in memory and on disk is unnecessary for a batch job.

Falls back to the nearest known Mumbai area anchor when the network is
unavailable or the query cannot be resolved, so a scrape never fails on
geocoding alone.
"""

from __future__ import annotations

import asyncio
import logging
import time
from typing import Any

import httpx

from app.config import get_settings

logger = logging.getLogger(__name__)

_cache: dict[str, tuple[float, float] | None] = {}
_lock = asyncio.Lock()
_last_call = 0.0

#: MMR (Mumbai Metropolitan Region) bounding box — reject far-away matches.
MMR_BOUNDS = {"min_lat": 18.7, "max_lat": 19.6, "min_lng": 72.5, "max_lng": 73.6}


def in_mmr(lat: float, lng: float) -> bool:
    return (
        MMR_BOUNDS["min_lat"] <= lat <= MMR_BOUNDS["max_lat"]
        and MMR_BOUNDS["min_lng"] <= lng <= MMR_BOUNDS["max_lng"]
    )


def _area_anchor(area: str | None) -> tuple[float, float] | None:
    if not area:
        return None
    from app.services.recommender import KNOWN_AREAS, resolve_location

    return resolve_location(area)


async def geocode(query: str, *, area: str | None = None, country: str = "India") -> tuple[float, float] | None:
    """Return (lat, lng) for a free-text place query, or None.

    ``area`` biases the query and provides a fallback anchor. Results outside
    the MMR bounding box are rejected (an "Elephanta Caves" match in another
    country must not enter the dataset).
    """
    global _last_call
    q = (query or "").strip()
    if not q:
        return _area_anchor(area)
    key = f"{q}|{area or ''}".lower()
    if key in _cache:
        return _cache[key]

    settings = get_settings()
    if not settings.geocode_enabled:
        anchor = _area_anchor(area)
        _cache[key] = anchor
        return anchor

    async with _lock:
        # Nominatim: max 1 request/second.
        wait = settings.geocode_min_interval_seconds - (time.monotonic() - _last_call)
        if wait > 0:
            await asyncio.sleep(wait)
        try:
            search = f"{q}, {area}, Mumbai, {country}" if area else f"{q}, Mumbai, {country}"
            async with httpx.AsyncClient(timeout=settings.geocode_timeout_seconds) as client:
                resp = await client.get(
                    settings.geocode_base_url,
                    params={"q": search, "format": "json", "limit": 1},
                    headers={"User-Agent": settings.geocode_user_agent},
                )
                resp.raise_for_status()
                data = resp.json()
            _last_call = time.monotonic()
            if data:
                lat, lng = float(data[0]["lat"]), float(data[0]["lon"])
                if in_mmr(lat, lng):
                    _cache[key] = (lat, lng)
                    return (lat, lng)
                logger.debug("Rejected out-of-MMR geocode for %r: %s,%s", q, lat, lng)
        except Exception as exc:
            _last_call = time.monotonic()
            logger.warning("Geocode failed for %r: %s", q, exc)

    anchor = _area_anchor(area)
    _cache[key] = anchor
    return anchor


def clear_geocode_cache() -> None:
    _cache.clear()


def cache_stats() -> dict[str, Any]:
    return {"size": len(_cache)}
