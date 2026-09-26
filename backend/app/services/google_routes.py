"""Google Routes API integration for travel time, distance and geometry.

The recommendation engine calls :func:`route_between_many` to enrich results
with real driving/walking metrics and an encoded polyline. Every failure path
returns ``None`` so the caller falls back to the offline Haversine heuristic
already implemented in :mod:`app.services.recommender`.

Only the server-restricted ``GOOGLE_ROUTES_API_KEY`` is used.
"""

from __future__ import annotations

import logging
import re
from typing import Literal

import httpx
from pydantic import BaseModel, Field

from app.config import get_settings

logger = logging.getLogger(__name__)

COMPUTE_ROUTES_URL = "https://routes.googleapis.com/directions/v2:computeRoutes"
ROUTES_FIELD_MASK = ",".join(
    [
        "routes.distanceMeters",
        "routes.duration",
        "routes.polyline.encodedPolyline",
        "routes.legs.distanceMeters",
        "routes.legs.duration",
    ]
)

TIMEOUT_S = 8.0
TravelMode = Literal["WALK", "DRIVE", "BICYCLE", "TRANSIT"]

_DURATION_RE = re.compile(r"^(\d+(?:\.\d+)?)s$")


class RouteResult(BaseModel):
    """Normalized leg/direction data for the client."""

    distance_m: int = Field(default=0, description="Route distance in metres.")
    duration_s: int = Field(default=0, description="Route duration in seconds.")
    duration_min: int = Field(default=0, description="Rounded minutes for display.")
    polyline: str | None = Field(
        default=None, description="Encoded polyline for drawing the route."
    )
    travel_mode: str = "WALK"
    source: str = Field(default="local", description="'google_routes' or 'local'.")


def _api_key() -> str:
    return get_settings().google_routes_api_key.strip()


def is_configured() -> bool:
    return bool(_api_key())


def _parse_duration(value: object) -> int:
    """Routes API returns durations like '123s'."""
    if isinstance(value, (int, float)):
        return int(value)
    if not isinstance(value, str):
        return 0
    match = _DURATION_RE.match(value.strip())
    return int(float(match.group(1))) if match else 0


async def compute_route(
    origin_lat: float,
    origin_lng: float,
    dest_lat: float,
    dest_lng: float,
    *,
    travel_mode: TravelMode = "WALK",
) -> RouteResult | None:
    """Single route lookup. Returns ``None`` when Google is unavailable."""
    if not is_configured():
        return None
    payload = {
        "origin": {"location": {"latLng": {"latitude": origin_lat, "longitude": origin_lng}}},
        "destination": {"location": {"latLng": {"latitude": dest_lat, "longitude": dest_lng}}},
        "travelMode": travel_mode,
    }
    # Google rejects routingPreference for anything other than DRIVE:
    # "Routing preference cannot be set for WALK or BICYCLE routing mode."
    if travel_mode == "DRIVE":
        payload["routingPreference"] = "TRAFFIC_AWARE"
    try:
        async with httpx.AsyncClient(timeout=TIMEOUT_S) as client:
            response = await client.post(
                COMPUTE_ROUTES_URL,
                json=payload,
                headers={"X-Goog-Api-Key": _api_key(), "X-Goog-FieldMask": ROUTES_FIELD_MASK},
            )
            response.raise_for_status()
            data = response.json()
    except Exception as exc:
        logger.warning("Google Routes compute failed: %s", exc)
        return None

    routes = data.get("routes") or []
    if not routes:
        return None
    route = routes[0]
    duration_s = _parse_duration(route.get("duration"))
    return RouteResult(
        distance_m=int(route.get("distanceMeters") or 0),
        duration_s=duration_s,
        duration_min=round(duration_s / 60),
        polyline=(route.get("polyline") or {}).get("encodedPolyline"),
        travel_mode=travel_mode,
        source="google_routes",
    )


async def route_between_many(
    origin_lat: float,
    origin_lng: float,
    destinations: list[tuple[float, float]],
    *,
    travel_mode: TravelMode = "WALK",
) -> list[RouteResult | None]:
    """Route to several destinations, preserving input order.

    Bounded so one recommendation request cannot fan out into dozens of calls;
    callers fall back to local estimates for anything beyond the cap.
    """
    if not is_configured() or not destinations:
        return [None] * len(destinations)

    cap = 10
    results: list[RouteResult | None] = []
    for lat, lng in destinations[:cap]:
        results.append(
            await compute_route(origin_lat, origin_lng, lat, lng, travel_mode=travel_mode)
        )
    results.extend([None] * (len(destinations) - len(results)))
    return results


async def google_health() -> dict:
    if not is_configured():
        return {"configured": False, "available": False, "reason": "no_server_key"}
    try:
        result = await compute_route(19.0596, 72.8295, 19.1075, 72.8263)
        return {
            "configured": True,
            "available": result is not None,
            "reason": None if result else "empty_response",
        }
    except Exception as exc:  # pragma: no cover - defensive
        return {"configured": True, "available": False, "reason": str(exc)[:120]}
