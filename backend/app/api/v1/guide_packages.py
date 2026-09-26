"""Guide package marketplace endpoints.

A guide package is an end-to-end experience: pickup location -> ordered stops
-> drop-off. It replaces the older hourly-guide model with a bookable product.
"""

from __future__ import annotations

import logging
import secrets
from datetime import date as date_type
from datetime import datetime, timezone

from fastapi import APIRouter, Depends, HTTPException, Request, Response
from sqlmodel import Session, select

from app.database import get_session
from app.models import (
    Guide,
    GuideAvailability,
    GuideBooking,
    GuidePackage,
    GuidePackageStop,
    GuideReview,
    User,
)
from app.rate_limit import PUBLIC_LIMIT, limiter
from app.schemas import (
    GuideAvailabilityCreate,
    GuideAvailabilityResponse,
    GuideBookingCreate,
    GuideBookingResponse,
    GuidePackageCreate,
    GuidePackageResponse,
    GuidePackageStopResponse,
    GuideReviewCreate,
    GuideReviewResponse,
)
from app.services.auth import get_current_user_optional

logger = logging.getLogger(__name__)
router = APIRouter()


def _new_ref() -> str:
    return f"LQ-{secrets.token_hex(3).upper()}"


@router.get("/guides/{guide_id}/packages", response_model=list[GuidePackageResponse], summary="List guide packages")
@limiter.limit(PUBLIC_LIMIT)
def list_guide_packages(
    request: Request,
    response: Response,
    guide_id: int,
    session: Session = Depends(get_session),
):
    """Return active packages for a guide."""
    guide = session.get(Guide, guide_id)
    if guide is None:
        raise HTTPException(status_code=404, detail="Guide not found")
    packages = session.exec(
        select(GuidePackage)
        .where(GuidePackage.guide_id == guide_id)
        .where(GuidePackage.is_active == True)
        .order_by(GuidePackage.total_duration_hours)
    ).all()
    responses: list[GuidePackageResponse] = []
    for package in packages:
        stops = list(
            session.exec(
                select(GuidePackageStop)
                .where(GuidePackageStop.package_id == package.id)
                .order_by(GuidePackageStop.sequence)
            ).all()
        )
        item = GuidePackageResponse.model_validate(package)
        item.stops = [GuidePackageStopResponse.model_validate(s) for s in stops]
        responses.append(item)
    return responses


@router.post(
    "/guides/{guide_id}/packages",
    response_model=GuidePackageResponse,
    status_code=201,
    summary="Create a guide package",
)
@limiter.limit(PUBLIC_LIMIT)
def create_guide_package(
    request: Request,
    response: Response,
    guide_id: int,
    payload: GuidePackageCreate,
    session: Session = Depends(get_session),
):
    """Create a new end-to-end package for a guide.

    In a real app this would be guide/admin-only; for now any client can create
    packages to support rapid seeding.
    """
    guide = session.get(Guide, guide_id)
    if guide is None:
        raise HTTPException(status_code=404, detail="Guide not found")

    package = GuidePackage(
        guide_id=guide_id,
        **payload.model_dump(exclude={"stops"}),
    )
    session.add(package)
    session.commit()
    session.refresh(package)

    for stop in payload.stops:
        session.add(GuidePackageStop(package_id=package.id, **stop.model_dump()))
    session.commit()

    # Reload package + stops (no ORM relationship on these tables).
    stops = list(
        session.exec(
            select(GuidePackageStop)
            .where(GuidePackageStop.package_id == package.id)
            .order_by(GuidePackageStop.sequence)
        ).all()
    )

    logger.info("Created guide package id=%s for guide=%s", package.id, guide_id)
    response = GuidePackageResponse.model_validate(package)
    response.stops = [GuidePackageStopResponse.model_validate(s) for s in stops]
    return response


@router.get(
    "/guide-packages/{package_id}",
    response_model=GuidePackageResponse,
    summary="Get a guide package",
)
@limiter.limit(PUBLIC_LIMIT)
def get_guide_package(
    request: Request,
    response: Response,
    package_id: int,
    session: Session = Depends(get_session),
):
    package = session.get(GuidePackage, package_id)
    if package is None or not package.is_active:
        raise HTTPException(status_code=404, detail="Package not found")
    stops = list(
        session.exec(
            select(GuidePackageStop)
            .where(GuidePackageStop.package_id == package.id)
            .order_by(GuidePackageStop.sequence)
        ).all()
    )
    response = GuidePackageResponse.model_validate(package)
    response.stops = [GuidePackageStopResponse.model_validate(s) for s in stops]
    return response


@router.post(
    "/guide-packages/{package_id}/book",
    response_model=GuideBookingResponse,
    status_code=201,
    summary="Book a guide package",
)
@limiter.limit(PUBLIC_LIMIT)
def book_guide_package(
    request: Request,
    response: Response,
    package_id: int,
    payload: GuideBookingCreate,
    session: Session = Depends(get_session),
    current_user: User | None = Depends(get_current_user_optional),
):
    """Create a pending booking for a package.

    Auth is optional so the demo flow works. No payment is taken.
    """
    package = session.get(GuidePackage, package_id)
    if package is None or not package.is_active:
        raise HTTPException(status_code=404, detail="Package not found")
    if payload.group_size > package.max_group_size:
        raise HTTPException(
            status_code=400,
            detail=f"Group size exceeds maximum of {package.max_group_size}",
        )

    booking = GuideBooking(
        guide_id=package.guide_id,
        package_id=package_id,
        user_id=current_user.id if current_user else None,
        date=payload.date,
        start_time=payload.start_time,
        group_size=payload.group_size,
        pickup_address=payload.pickup_address,
        note=payload.note,
        status="pending",
        booking_ref=_new_ref(),
        created_at=datetime.now(timezone.utc),
    )
    session.add(booking)
    session.commit()
    session.refresh(booking)

    logger.info(
        "Guide package booking ref=%s package=%s user=%s",
        booking.booking_ref,
        package_id,
        booking.user_id,
    )
    return GuideBookingResponse.model_validate(booking)


@router.get(
    "/guide-bookings/me",
    response_model=list[GuideBookingResponse],
    summary="My guide package bookings",
)
@limiter.limit(PUBLIC_LIMIT)
def my_guide_bookings(
    request: Request,
    response: Response,
    session: Session = Depends(get_session),
    current_user: User | None = Depends(get_current_user_optional),
):
    """Bookings for the authenticated user, newest first."""
    if current_user is None:
        return []
    rows = session.exec(
        select(GuideBooking)
        .where(GuideBooking.user_id == current_user.id)
        .order_by(GuideBooking.id.desc())
    ).all()
    return [GuideBookingResponse.model_validate(r) for r in rows]


@router.get(
    "/guides/{guide_id}/availability",
    response_model=list[GuideAvailabilityResponse],
    summary="Guide availability",
)
@limiter.limit(PUBLIC_LIMIT)
def guide_availability(
    request: Request,
    response: Response,
    guide_id: int,
    session: Session = Depends(get_session),
):
    guide = session.get(Guide, guide_id)
    if guide is None:
        raise HTTPException(status_code=404, detail="Guide not found")
    rows = session.exec(
        select(GuideAvailability)
        .where(GuideAvailability.guide_id == guide_id)
        .order_by(GuideAvailability.available_date)
    ).all()
    return [GuideAvailabilityResponse.model_validate(r) for r in rows]


@router.post(
    "/guides/{guide_id}/availability",
    response_model=GuideAvailabilityResponse,
    status_code=201,
    summary="Add a guide availability slot",
)
@limiter.limit(PUBLIC_LIMIT)
def add_guide_availability(
    request: Request,
    response: Response,
    guide_id: int,
    payload: GuideAvailabilityCreate,
    session: Session = Depends(get_session),
):
    guide = session.get(Guide, guide_id)
    if guide is None:
        raise HTTPException(status_code=404, detail="Guide not found")
    try:
        available_date = date_type.fromisoformat(payload.available_date)
    except ValueError:
        raise HTTPException(status_code=400, detail="available_date must be YYYY-MM-DD")

    row = GuideAvailability(
        guide_id=guide_id,
        available_date=available_date,
        start_time=payload.start_time,
        end_time=payload.end_time,
        is_available=payload.is_available,
    )
    session.add(row)
    session.commit()
    session.refresh(row)
    return GuideAvailabilityResponse.model_validate(row)


@router.post(
    "/guide-packages/{package_id}/reviews",
    response_model=GuideReviewResponse,
    status_code=201,
    summary="Review a completed booking",
)
@limiter.limit(PUBLIC_LIMIT)
def review_guide_package(
    request: Request,
    response: Response,
    package_id: int,
    payload: GuideReviewCreate,
    session: Session = Depends(get_session),
    current_user: User | None = Depends(get_current_user_optional),
):
    package = session.get(GuidePackage, package_id)
    if package is None:
        raise HTTPException(status_code=404, detail="Package not found")
    booking = session.get(GuideBooking, payload.booking_id)
    if booking is None or booking.package_id != package_id:
        raise HTTPException(status_code=404, detail="Booking not found for package")

    review = GuideReview(
        booking_id=payload.booking_id,
        guide_id=package.guide_id,
        package_id=package_id,
        user_id=current_user.id if current_user else booking.user_id,
        rating=payload.rating,
        review_text=payload.review_text,
    )
    session.add(review)
    session.commit()
    session.refresh(review)
    return GuideReviewResponse.model_validate(review)


@router.get(
    "/guide-packages/{package_id}/reviews",
    response_model=list[GuideReviewResponse],
    summary="Reviews for a package",
)
@limiter.limit(PUBLIC_LIMIT)
def list_guide_package_reviews(
    request: Request,
    response: Response,
    package_id: int,
    session: Session = Depends(get_session),
):
    rows = session.exec(
        select(GuideReview)
        .where(GuideReview.package_id == package_id)
        .order_by(GuideReview.id.desc())
    ).all()
    return [GuideReviewResponse.model_validate(r) for r in rows]
