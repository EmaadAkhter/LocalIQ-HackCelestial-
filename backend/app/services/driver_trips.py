"""Driver trip view: pickup, ordered stops, drop-off and the route geometry.

A *trip* is a :class:`~app.models.PackageBooking` — a guest booked one of the
guide's packages. The driver (the guide) needs three things on screen:

1. where to collect the guest (pickup),
2. the stops in order, with dwell times,
3. where to drop them (the drop-off, defaulting to the pickup).

Geometry comes from Google Routes when ``GOOGLE_ROUTES_API_KEY`` is set. Without
it we synthesise a plausible road-like path (a gentle bow between waypoints) so
the map is never empty — the same "graceful fallback" rule the rest of LocalIQ
follows. Nothing here requires a paid API.
"""

from __future__ import annotations

import logging
import math
from datetime import datetime, timezone
from typing import Any

from sqlmodel import Session, select

from app.models import (
    Guide,
    GuidePackage,
    GuidePackageStop,
    PackageBooking,
    User,
)
from app.models_prd import GuideProfile
from app.services import google_routes
from app.services.recommender import haversine_km

logger = logging.getLogger(__name__)

#: Driver-side trip lifecycle. A driver can move a pending booking to confirmed,
#: start it, then close it. Anything else is rejected server-side.
TRIP_TRANSITIONS: dict[str, set[str]] = {
    "requested": {"confirmed", "cancelled"},
    "pending": {"confirmed", "cancelled"},
    "accepted": {"confirmed", "cancelled"},
    "confirmed": {"in_progress", "cancelled"},
    "in_progress": {"completed"},
    "completed": set(),
    "cancelled": set(),
}

#: What the map shows before the trip starts.
ACTIVE_STATUSES = ("requested", "pending", "accepted", "confirmed", "in_progress")


# ---------------------------------------------------------------------------
# Geometry
# ---------------------------------------------------------------------------


def decode_polyline(encoded: str) -> list[tuple[float, float]]:
    """Decode a Google encoded polyline into ``(lat, lng)`` pairs."""
    if not encoded:
        return []
    coordinates: list[tuple[float, float]] = []
    index = 0
    lat = 0
    lng = 0
    length = len(encoded)
    while index < length:
        for is_longitude in (False, True):
            shift = 0
            result = 0
            while True:
                if index >= length:
                    return coordinates
                byte = ord(encoded[index]) - 63
                index += 1
                result |= (byte & 0x1F) << shift
                shift += 5
                if byte < 0x20:
                    break
            delta = ~(result >> 1) if (result & 1) else (result >> 1)
            if is_longitude:
                lng += delta
            else:
                lat += delta
        coordinates.append((lat * 1e-5, lng * 1e-5))
    return coordinates


def _unit_seed(*values: float) -> float:
    """Deterministic 0..1 from coordinates (no ``hash()``, no RNG)."""
    accumulator = 0
    for value in values:
        accumulator = (accumulator * 131 + int(round(value * 1e5))) % 1_000_003
    return accumulator / 1_000_003


def synthesise_path(
    points: list[tuple[float, float]], *, per_leg: int = 12
) -> list[tuple[float, float]]:
    """A road-like curve through ``points`` for the offline fallback.

    Each leg gets a shallow bow perpendicular to the straight line, so the map
    reads as a route rather than a ruler line. Deterministic for a given input.
    """
    if len(points) < 2:
        return list(points)

    path: list[tuple[float, float]] = []
    for index, (start, end) in enumerate(zip(points, points[1:])):
        if index == 0:
            path.append(start)
        d_lat = end[0] - start[0]
        d_lng = end[1] - start[1]
        span = math.hypot(d_lat, d_lng) or 1e-9
        perp_lat = -d_lng / span
        perp_lng = d_lat / span
        bow = 0.00035 + _unit_seed(*start, *end) * 0.00045
        for step in range(1, per_leg + 1):
            t = step / per_leg
            curve = math.sin(math.pi * t) * bow
            path.append(
                (
                    start[0] + d_lat * t + perp_lat * curve,
                    start[1] + d_lng * t + perp_lng * curve,
                )
            )
    return path


async def build_route(
    points: list[tuple[float, float]], *, travel_mode: str = "DRIVE"
) -> dict[str, Any]:
    """Route geometry + totals between ordered waypoints.

    Returns ``path`` (list of ``{lat, lng}``), ``distance_km``, ``duration_min``
    and ``source`` (``google_routes`` or ``local``).
    """
    points = [p for p in points if p[0] is not None and p[1] is not None]
    if len(points) < 2:
        return {"path": [], "distance_km": 0.0, "duration_min": 0, "source": "local"}

    if google_routes.is_configured():
        path: list[tuple[float, float]] = []
        total_m = 0
        total_s = 0
        ok = True
        for start, end in zip(points, points[1:]):
            result = await google_routes.compute_route(
                start[0], start[1], end[0], end[1], travel_mode=travel_mode  # type: ignore[arg-type]
            )
            if result is None:
                ok = False
                break
            total_m += result.distance_m
            total_s += result.duration_s
            if result.polyline:
                segment = decode_polyline(result.polyline)
                if path and segment:
                    segment = segment[1:]
                path.extend(segment)
        if ok and len(path) >= 2:
            return {
                "path": [{"lat": lat, "lng": lng} for lat, lng in path],
                "distance_km": round(total_m / 1000, 2),
                "duration_min": round(total_s / 60),
                "source": "google_routes",
            }

    path = synthesise_path(points)
    distance = sum(
        haversine_km(a[0], a[1], b[0], b[1]) for a, b in zip(points, points[1:])
    )
    # ~22 km/h average in Mumbai traffic.
    return {
        "path": [{"lat": lat, "lng": lng} for lat, lng in path],
        "distance_km": round(distance, 2),
        "duration_min": max(1, round(distance / 22 * 60)),
        "source": "local",
    }


# ---------------------------------------------------------------------------
# Lookups
# ---------------------------------------------------------------------------


def resolve_guide(session: Session, user: User) -> Guide | None:
    """The guide owned by ``user``, or None when they are not a guide yet."""
    if user.id is None:
        return None
    profile = session.exec(
        select(GuideProfile).where(GuideProfile.user_id == user.id)
    ).first()
    if profile is None:
        return None
    return session.get(Guide, profile.guide_id)


def _guide_name(session: Session, guide_id: int) -> str | None:
    guide = session.get(Guide, guide_id)
    return guide.name if guide else None


def list_trips(
    session: Session, guide_id: int, *, active_only: bool = True
) -> list[PackageBooking]:
    statement = select(PackageBooking).where(PackageBooking.guide_id == guide_id)
    if active_only:
        statement = statement.where(PackageBooking.status.in_(ACTIVE_STATUSES))  # type: ignore[attr-defined]
    return list(
        session.exec(statement.order_by(PackageBooking.id.desc())).all()  # type: ignore[attr-defined]
    )


def stops_for(session: Session, package_id: int | None) -> list[GuidePackageStop]:
    if package_id is None:
        return []
    return list(
        session.exec(
            select(GuidePackageStop)
            .where(GuidePackageStop.package_id == package_id)
            .order_by(GuidePackageStop.sequence)  # type: ignore[attr-defined]
        ).all()
    )


def _waypoints(
    booking: PackageBooking, stops: list[GuidePackageStop]
) -> list[tuple[float, float]]:
    """Pickup -> ordered stops -> drop, skipping anything without coordinates."""
    points: list[tuple[float, float]] = []
    if booking.pickup_lat is not None and booking.pickup_lng is not None:
        points.append((booking.pickup_lat, booking.pickup_lng))
    for stop in stops:
        if stop.lat is not None and stop.lng is not None:
            points.append((stop.lat, stop.lng))
    drop = _drop_of(booking)
    if drop is not None:
        # Avoid a zero-length final leg when the drop is the pickup.
        if not points or haversine_km(points[-1][0], points[-1][1], drop[0], drop[1]) > 0.02:
            points.append(drop)
    return points


def _drop_of(booking: PackageBooking) -> tuple[float, float] | None:
    """Explicit drop point, else a loop back to the pickup."""
    if booking.drop_lat is not None and booking.drop_lng is not None:
        return (booking.drop_lat, booking.drop_lng)
    if booking.pickup_lat is not None and booking.pickup_lng is not None:
        return (booking.pickup_lat, booking.pickup_lng)
    return None


def allowed_transitions(status: str) -> list[str]:
    return sorted(TRIP_TRANSITIONS.get(status, set()))


# ---------------------------------------------------------------------------
# Payloads
# ---------------------------------------------------------------------------


def _point(lat: float | None, lng: float | None, label: str | None, address: str | None) -> dict | None:
    if lat is None or lng is None:
        return None
    return {"lat": lat, "lng": lng, "label": label, "address": address}


async def trip_payload(session: Session, booking: PackageBooking) -> dict[str, Any]:
    """Everything the driver (or a tracking guest) map needs."""
    package = session.get(GuidePackage, booking.package_id) if booking.package_id else None
    stops = stops_for(session, booking.package_id)

    pickup = _point(booking.pickup_lat, booking.pickup_lng, "Pickup", booking.pickup_address)
    drop_point = _drop_of(booking)
    drop = (
        _point(drop_point[0], drop_point[1], "Drop-off", booking.drop_address)
        if drop_point
        else None
    )
    if drop is not None and booking.drop_lat is None and booking.pickup_lat is not None:
        drop["label"] = "Drop-off (same as pickup)"

    route = await build_route(_waypoints(booking, stops))

    stop_payload = [
        {
            "sequence": stop.sequence,
            "name": stop.location_name,
            "lat": stop.lat,
            "lng": stop.lng,
            "duration_min": stop.duration_min,
            "travel_time_min": stop.travel_time_min,
            "segment_type": stop.segment_type,
            "guide_notes": stop.guide_notes,
        }
        for stop in stops
    ]

    driver_location = (
        _point(booking.driver_lat, booking.driver_lng, "Driver", None)
        if booking.driver_lat is not None and booking.driver_lng is not None
        else None
    )

    remaining = None
    if driver_location is not None and drop is not None:
        left_km = haversine_km(
            driver_location["lat"], driver_location["lng"], drop["lat"], drop["lng"]
        )
        remaining = {
            "distance_km": round(left_km, 2),
            "duration_min": max(1, round(left_km / 22 * 60)),
        }

    return {
        "id": booking.id,
        "booking_ref": booking.booking_ref,
        "status": booking.status,
        "allowed_transitions": allowed_transitions(booking.status),
        "date": booking.date,
        "start_time": booking.start_time,
        "hours": booking.hours,
        "group_size": booking.group_size,
        "guest_name": booking.guest_name,
        "guest_phone": booking.guest_phone,
        "note": booking.note,
        "package_id": booking.package_id,
        "package_title": package.title if package else None,
        "guide_id": booking.guide_id,
        "guide_name": _guide_name(session, booking.guide_id),
        "pickup": pickup,
        "drop": drop,
        "stops": stop_payload,
        "route": route["path"],
        "distance_km": route["distance_km"],
        "duration_min": route["duration_min"],
        "route_source": route["source"],
        "driver_location": driver_location,
        "remaining": remaining,
    }


def trip_summary(session: Session, booking: PackageBooking) -> dict[str, Any]:
    """Light list row — no geometry, safe to fetch in bulk."""
    package = session.get(GuidePackage, booking.package_id) if booking.package_id else None
    return {
        "id": booking.id,
        "booking_ref": booking.booking_ref,
        "status": booking.status,
        "date": booking.date,
        "start_time": booking.start_time,
        "group_size": booking.group_size,
        "guest_name": booking.guest_name,
        "package_title": package.title if package else None,
        "pickup_address": booking.pickup_address,
        "pickup": _point(booking.pickup_lat, booking.pickup_lng, "Pickup", booking.pickup_address),
        "has_driver_location": booking.driver_lat is not None,
    }


# ---------------------------------------------------------------------------
# Mutations
# ---------------------------------------------------------------------------


def advance(session: Session, booking: PackageBooking, target: str) -> PackageBooking:
    """Move a trip to ``target``, enforcing the state machine."""
    if target not in TRIP_TRANSITIONS.get(booking.status, set()):
        raise ValueError(f"cannot go from '{booking.status}' to '{target}'")
    booking.status = target
    now = datetime.now(timezone.utc)
    if target == "in_progress":
        booking.started_at = now
    elif target == "completed":
        booking.completed_at = now
    session.add(booking)
    session.commit()
    session.refresh(booking)
    return booking


def update_driver_location(
    session: Session, booking: PackageBooking, lat: float, lng: float
) -> PackageBooking:
    booking.driver_lat = lat
    booking.driver_lng = lng
    booking.driver_updated_at = datetime.now(timezone.utc)
    session.add(booking)
    session.commit()
    session.refresh(booking)
    return booking
