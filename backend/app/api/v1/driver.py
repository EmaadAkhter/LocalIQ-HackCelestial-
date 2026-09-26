"""Driver trip endpoints.

A guide's live trip map: where to collect the guest, the ordered stops and the
drop-off, with route geometry the client can draw.

    GET  /driver/trips                        active trips for the signed-in guide
    GET  /driver/trips/{booking_id}           pickup + stops + drop + route
    POST /driver/trips/{booking_id}/status    advance the trip
    POST /driver/trips/{booking_id}/location  report the driver's position
    GET  /bookings/{booking_id}/tracking      guest-side view of the same trip

Only the owning guide may read or mutate a trip; a guest may track their own.
"""

from __future__ import annotations

import logging

from fastapi import APIRouter, Depends, HTTPException, Query, Request, Response
from sqlmodel import Session

from app.database import get_session
from app.models import Guide, PackageBooking, User
from app.rate_limit import PUBLIC_LIMIT, limiter
from app.schemas import (
    DriverLocationUpdate,
    DriverTripDetail,
    DriverTripStatusUpdate,
    DriverTripSummary,
)
from app.services import driver_trips
from app.services.auth import get_current_user, get_current_user_optional

logger = logging.getLogger(__name__)
router = APIRouter()


def _require_guide(session: Session, user: User) -> Guide:
    guide = driver_trips.resolve_guide(session, user)
    if guide is None or guide.id is None:
        raise HTTPException(status_code=403, detail="not_a_guide")
    return guide


def _require_trip(session: Session, booking_id: int, guide_id: int) -> PackageBooking:
    booking = session.get(PackageBooking, booking_id)
    if booking is None or booking.guide_id != guide_id:
        raise HTTPException(status_code=404, detail="Trip not found")
    return booking


@router.get(
    "/driver/trips",
    response_model=list[DriverTripSummary],
    summary="Active trips assigned to the signed-in guide",
)
@limiter.limit(PUBLIC_LIMIT)
def my_driver_trips(
    request: Request,
    response: Response,
    include_completed: bool = Query(default=False),
    session: Session = Depends(get_session),
    current_user: User = Depends(get_current_user),
):
    guide = _require_guide(session, current_user)
    rows = driver_trips.list_trips(
        session, guide.id or 0, active_only=not include_completed
    )
    return [DriverTripSummary(**driver_trips.trip_summary(session, b)) for b in rows]


@router.get(
    "/driver/trips/{booking_id}",
    response_model=DriverTripDetail,
    summary="Trip detail: pickup, stops, drop-off and route",
)
@limiter.limit(PUBLIC_LIMIT)
async def driver_trip_detail(
    request: Request,
    response: Response,
    booking_id: int,
    session: Session = Depends(get_session),
    current_user: User = Depends(get_current_user),
):
    guide = _require_guide(session, current_user)
    booking = _require_trip(session, booking_id, guide.id or 0)
    return DriverTripDetail(**await driver_trips.trip_payload(session, booking))


@router.post(
    "/driver/trips/{booking_id}/status",
    response_model=DriverTripDetail,
    summary="Advance the trip (confirmed -> in_progress -> completed)",
)
@limiter.limit(PUBLIC_LIMIT)
async def update_driver_trip_status(
    request: Request,
    response: Response,
    booking_id: int,
    payload: DriverTripStatusUpdate,
    session: Session = Depends(get_session),
    current_user: User = Depends(get_current_user),
):
    guide = _require_guide(session, current_user)
    booking = _require_trip(session, booking_id, guide.id or 0)
    try:
        driver_trips.advance(session, booking, payload.status)
    except ValueError as exc:
        raise HTTPException(status_code=409, detail=str(exc))
    return DriverTripDetail(**await driver_trips.trip_payload(session, booking))


@router.post(
    "/driver/trips/{booking_id}/location",
    response_model=DriverTripDetail,
    summary="Report the driver's current position",
)
@limiter.limit(PUBLIC_LIMIT)
async def report_driver_location(
    request: Request,
    response: Response,
    booking_id: int,
    payload: DriverLocationUpdate,
    session: Session = Depends(get_session),
    current_user: User = Depends(get_current_user),
):
    guide = _require_guide(session, current_user)
    booking = _require_trip(session, booking_id, guide.id or 0)
    driver_trips.update_driver_location(session, booking, payload.lat, payload.lng)
    return DriverTripDetail(**await driver_trips.trip_payload(session, booking))


@router.get(
    "/bookings/{booking_id}/tracking",
    response_model=DriverTripDetail,
    summary="Guest view of a trip, including the driver's live position",
)
@limiter.limit(PUBLIC_LIMIT)
async def booking_tracking(
    request: Request,
    response: Response,
    booking_id: int,
    session: Session = Depends(get_session),
    current_user: User | None = Depends(get_current_user_optional),
):
    booking = session.get(PackageBooking, booking_id)
    if booking is None:
        raise HTTPException(status_code=404, detail="Trip not found")
    if booking.user_id is not None and (
        current_user is None or current_user.id != booking.user_id
    ):
        raise HTTPException(status_code=403, detail="Not your booking")
    return DriverTripDetail(**await driver_trips.trip_payload(session, booking))
