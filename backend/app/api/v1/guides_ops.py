"""Journeys 4, 6, 7 and 8: the guide side.

* Journey 6 — onboarding + **simulated** verification + availability + own experience
* Journey 4 — booking request -> quote -> accept/decline -> tour -> review
* Journey 7 — guide operations state machine (accept -> confirm -> conduct -> complete -> payment)
* Journey 8 — training, certification and tier progression / feature gating

Verification is simulated per Phase 1: only a document *type* and a short
reference are stored, never a file or a government ID number, and no response
ever echoes them back in full.
"""

from __future__ import annotations

import logging
from datetime import date as date_type

from fastapi import APIRouter, Depends, Header, HTTPException, Query, status
from sqlmodel import Session, select

from app.database import get_session
from app.models import Experience, Guide, User
from app.models_prd import (
    GuideAvailability,
    GuideBooking,
    GuideProfile,
    GuideReview,
    GuideTraining,
)
from app.schemas_prd import (
    GuideAvailabilityCreate,
    GuideAvailabilityResponse,
    GuideBookingCreate,
    GuideBookingQuote,
    GuideBookingResponse,
    GuideBookingTransition,
    GuideGrowthResponse,
    GuideExperienceCreate,
    GuideExperienceResponse,
    GuideIdUpload,
    GuideOnboardStart,
    GuideProfileResponse,
    GuideReviewCreate,
    GuideReviewResponse,
    GuideTrainingComplete,
    GuideTrainingCreate,
    GuideTrainingResponse,
)
from app.services import journey_rules as rules
from app.services import notifications as notification_service
from app.timeutil import utcnow
from app.api.v1.journey_deps import enforce_trust, guide_profile

logger = logging.getLogger(__name__)
router = APIRouter()

#: Traveller-facing copy for each booking transition. The guide is the one
#: acting, so only the traveller is notified.
_BOOKING_NOTIFICATIONS: dict[str, tuple[str, str]] = {
    "accepted": ("Booking accepted", "Your guide accepted the booking."),
    "confirmed": ("Booking confirmed", "Your booking is confirmed."),
    "in_progress": ("Tour started", "Your guide has started the tour."),
    "completed": ("Tour completed", "Your tour is complete. Leave a review?"),
    "declined": ("Booking declined", "The guide could not take this booking."),
    "cancelled": ("Booking cancelled", "This booking was cancelled."),
}


def _notify_booking_status(session: Session, booking: GuideBooking, status: str) -> None:
    """Tell the traveller their booking moved.

    Only the traveller is notified: the guide triggered the change, so sending
    them a copy would be noise.
    """
    copy = _BOOKING_NOTIFICATIONS.get(status)
    if copy is None:
        return
    title, body = copy
    notification_service.create(
        session,
        user_id=booking.user_id,
        title=title,
        body=body,
        kind=notification_service.BOOKING,
        data={"booking_id": booking.id, "status": status},
    )


def _require_guide_owner(
    session: Session, guide_id: int, x_user_id: int | None
) -> GuideProfile:
    """Only the guide's own user may mutate their profile.

    A guide onboarded without an account has ``user_id = None``; the first
    authenticated caller claims it, which keeps the demo usable without opening
    the endpoint to everyone afterwards.
    """
    profile = guide_profile(session, guide_id)
    if profile.user_id is None:
        if x_user_id is None:
            raise HTTPException(
                status_code=401, detail="X-User-Id header required to claim this guide"
            )
        if session.get(User, x_user_id) is None:
            raise HTTPException(status_code=401, detail="Unknown user")
        profile.user_id = x_user_id
        session.add(profile)
        session.commit()
        session.refresh(profile)
        return profile
    if x_user_id is None:
        raise HTTPException(status_code=401, detail="X-User-Id header required")
    if profile.user_id != x_user_id:
        raise HTTPException(status_code=403, detail="Not this guide's profile")
    return profile


#: Averages a guide's ratings into the canonical 0-5 scale.
def _average_rating(profile: GuideProfile) -> float:
    if not profile.review_count:
        return 0.0
    return round(profile.rating_sum / profile.review_count, 2)


def _certifications(session: Session, guide_id: int) -> list[str]:
    rows = session.exec(
        select(GuideTraining).where(
            GuideTraining.guide_id == guide_id,
            GuideTraining.status == "completed",
            GuideTraining.grants_tier.is_not(None),
        )
    ).all()
    return [r.grants_tier for r in rows if r.grants_tier]


def _profile_payload(session: Session, profile: GuideProfile) -> GuideProfileResponse:
    guide = session.get(Guide, profile.guide_id)
    average = _average_rating(profile)
    next_tier = rules.next_guide_tier(
        tier=profile.tier,
        completed_tours=profile.completed_tours,
        average_rating=average,
        certifications=len(_certifications(session, profile.guide_id)),
    )
    trainings = session.exec(
        select(GuideTraining).where(GuideTraining.guide_id == profile.guide_id)
    ).all()
    return GuideProfileResponse(
        guide_id=profile.guide_id,
        name=guide.name if guide else f"guide-{profile.guide_id}",
        onboarding_state=profile.onboarding_state,
        verification_status=profile.verification_status,
        verification_tier=profile.verification_tier,
        tier=profile.tier,
        xp=profile.xp,
        completed_tours=profile.completed_tours,
        review_count=profile.review_count,
        average_rating=average,
        is_published=profile.is_published,
        features=rules.tier_features(profile.tier),
        visibility_boost=rules.visibility_boost(profile.tier),
        next_tier=next_tier,
        certifications=_certifications(session, profile.guide_id),
        trainings=[
            {
                "course_code": t.course_code,
                "course_name": t.course_name,
                "status": t.status,
                "score": t.score,
                "grants_tier": t.grants_tier,
            }
            for t in trainings
        ],
        can_accept_bookings=rules.has_feature(profile.tier, "accept_booking")
        and profile.verification_status == "verified",
    )


# ---------------------------------------------------------------------------
# Journey 6: onboarding + simulated verification
# ---------------------------------------------------------------------------


@router.post(
    "/guides/onboard",
    response_model=GuideProfileResponse,
    status_code=status.HTTP_201_CREATED,
    summary="Guide signup (journey 6, step 1)",
)
def guide_onboard(
    payload: GuideOnboardStart,
    session: Session = Depends(get_session),
    x_user_id: int | None = Header(default=None, alias="X-User-Id"),
):
    """Create the guide row plus its onboarding/verification profile."""
    if x_user_id is not None and session.get(User, x_user_id) is None:
        raise HTTPException(status_code=401, detail="Unknown user")

    guide = Guide(
        name=payload.name,
        specialty=payload.specialty,
        languages=list(payload.languages),
        rate_per_hour=payload.rate_per_hour,
        photo=payload.photo,
    )
    session.add(guide)
    session.commit()
    session.refresh(guide)

    profile = GuideProfile(
        guide_id=guide.id or 0,
        user_id=x_user_id,
        onboarding_state="signup",
        verification_status="unverified",
        verification_tier="basic",
        bio=payload.bio,
        city=payload.city,
    )
    session.add(profile)
    session.commit()
    session.refresh(profile)
    logger.info("Guide %s onboarded (state=%s)", guide.id, profile.onboarding_state)
    return _profile_payload(session, profile)


@router.post(
    "/guides/{guide_id}/verification",
    response_model=GuideProfileResponse,
    summary="Upload ID metadata + simulated verification (journey 6, step 2)",
)
def submit_verification(
    guide_id: int,
    payload: GuideIdUpload,
    session: Session = Depends(get_session),
    x_user_id: int | None = Header(default=None, alias="X-User-Id"),
):
    """Journey 6: store metadata, then run the **simulated** verification.

    Phase 1 has no KYC provider, so the outcome is chosen by the caller to drive
    the demo. Only the document type and a masked reference are persisted; the
    raw reference is never returned.
    """
    if session.get(Guide, guide_id) is None:
        raise HTTPException(status_code=404, detail="Guide not found")
    profile = _require_guide_owner(session, guide_id, x_user_id)

    ok, reason = rules.can_transition_guide(profile.onboarding_state, "id_uploaded")
    if not ok:
        raise HTTPException(status_code=409, detail=reason)

    masked = payload.document_reference[-4:]
    profile.onboarding_state = "id_uploaded"
    profile.id_document_type = payload.document_type
    profile.id_document_reference = f"****{masked}"
    profile.verification_status = "pending"
    session.add(profile)

    if payload.simulated_outcome == "approve":
        ok, reason = rules.can_transition_guide("id_uploaded", "verified")
        if not ok:
            raise HTTPException(status_code=409, detail=reason)
        profile.onboarding_state = "verified"
        profile.verification_status = "verified"
        profile.verification_tier = "standard"
        profile.verified_at = utcnow()
    else:
        profile.onboarding_state = "rejected"
        profile.verification_status = "rejected"
        profile.verification_tier = "unverified"
    session.add(profile)
    session.commit()
    session.refresh(profile)
    logger.info(
        "Guide %s verification (simulated) -> %s / tier %s",
        guide_id,
        profile.verification_status,
        profile.verification_tier,
    )
    return _profile_payload(session, profile)


@router.post(
    "/guides/{guide_id}/publish",
    response_model=GuideProfileResponse,
    summary="Activate a verified guide (journey 6, step 4)",
)
def activate_guide(
    guide_id: int,
    session: Session = Depends(get_session),
    x_user_id: int | None = Header(default=None, alias="X-User-Id"),
):
    """Journey 6 final step: verified -> active, listing published."""
    profile = _require_guide_owner(session, guide_id, x_user_id)
    ok, reason = rules.can_transition_guide(profile.onboarding_state, "active")
    if not ok:
        raise HTTPException(status_code=409, detail=reason)
    profile.onboarding_state = "active"
    profile.is_published = True
    session.add(profile)
    session.commit()
    session.refresh(profile)
    return _profile_payload(session, profile)


@router.post(
    "/guides/{guide_id}/experiences",
    response_model=GuideExperienceResponse,
    status_code=status.HTTP_201_CREATED,
    summary="Guide creates their own experience (journey 6, step 5)",
)
def guide_create_experience(
    guide_id: int,
    payload: GuideExperienceCreate,
    session: Session = Depends(get_session),
    x_user_id: int | None = Header(default=None, alias="X-User-Id"),
):
    """Journey 6: a verified guide can add an experience (draft by default)."""
    profile = _require_guide_owner(session, guide_id, x_user_id)
    if profile.verification_status != "verified":
        raise HTTPException(
            status_code=403, detail="guide must be verified before creating experiences"
        )

    publish = payload.publish
    experience = Experience(
        name=payload.name,
        category=payload.category.lower(),
        lat=payload.lat,
        lng=payload.lng,
        avg_cost=payload.avg_cost,
        duration_min=payload.duration_min,
        open_time=payload.open_time,
        close_time=payload.close_time,
        rating=0.0,
        description=payload.description,
        image_url=payload.image_url,
        tags=list(payload.tags),
        accessibility_flags=list(payload.accessibility_flags),
        indoor_outdoor=payload.indoor_outdoor.lower(),
        local_gem_score=payload.local_gem_score,
    )
    session.add(experience)
    session.commit()
    session.refresh(experience)

    guide = session.get(Guide, guide_id)
    if guide is not None and experience.id is not None:
        session.add(Guide(experience_id=experience.id, name=guide.name,
                           specialty=guide.specialty, rate_per_hour=guide.rate_per_hour,
                           languages=list(guide.languages or []), photo=guide.photo))
        session.commit()
    logger.info("Guide %s created experience %s (published=%s)", guide_id, experience.id, publish)
    return GuideExperienceResponse(
        id=experience.id or 0,
        name=experience.name,
        status="published" if publish else "draft",
        created_by_guide_id=guide_id,
    )


@router.get("/guides/{guide_id}/profile", response_model=GuideProfileResponse, summary="Guide profile state")
def get_guide_profile_route(
    guide_id: int, session: Session = Depends(get_session)
):
    return _profile_payload(session, guide_profile(session, guide_id))


# ---------------------------------------------------------------------------
# Journey 6: availability
# ---------------------------------------------------------------------------


@router.post(
    "/guides/{guide_id}/availability",
    response_model=GuideAvailabilityResponse,
    status_code=status.HTTP_201_CREATED,
    summary="Set availability (journey 6)",
)
def add_availability(
    guide_id: int,
    payload: GuideAvailabilityCreate,
    session: Session = Depends(get_session),
    x_user_id: int | None = Header(default=None, alias="X-User-Id"),
):
    if session.get(Guide, guide_id) is None:
        raise HTTPException(status_code=404, detail="Guide not found")
    profile = _require_guide_owner(session, guide_id, x_user_id)
    if profile.verification_status != "verified":
        raise HTTPException(status_code=403, detail="guide must be verified to publish slots")
    if payload.end_time <= payload.start_time:
        raise HTTPException(status_code=422, detail="end_time must be after start_time")

    clash = session.exec(
        select(GuideAvailability).where(
            GuideAvailability.guide_id == guide_id,
            GuideAvailability.date == payload.date,
        )
    ).all()
    for slot in clash:
        if not (payload.end_time <= slot.start_time or payload.start_time >= slot.end_time):
            raise HTTPException(
                status_code=409,
                detail=f"overlaps existing slot {slot.start_time}-{slot.end_time}",
            )

    slot = GuideAvailability(
        guide_id=guide_id,
        date=payload.date,
        start_time=payload.start_time,
        end_time=payload.end_time,
        max_group_size=payload.max_group_size,
        note=payload.note,
    )
    session.add(slot)
    session.commit()
    session.refresh(slot)
    return slot


@router.get(
    "/guides/{guide_id}/availability",
    response_model=list[GuideAvailabilityResponse],
    summary="Guide availability",
)
def list_availability(
    guide_id: int,
    session: Session = Depends(get_session),
    from_date: date_type | None = Query(default=None),
):
    stmt = select(GuideAvailability).where(GuideAvailability.guide_id == guide_id)
    if from_date is not None:
        stmt = stmt.where(GuideAvailability.date >= from_date)
    return session.exec(stmt.order_by(GuideAvailability.date, GuideAvailability.start_time)).all()


# ---------------------------------------------------------------------------
# Journey 4: booking
# ---------------------------------------------------------------------------


def _end_time(start: str, duration_min: int) -> str:
    h, m = (int(x) for x in start.split(":")[:2])
    total = h * 60 + m + duration_min
    return f"{(total // 60) % 24:02d}:{total % 60:02d}"


def _booking_payload(session: Session, booking: GuideBooking) -> GuideBookingResponse:
    guide = session.get(Guide, booking.guide_id)
    return GuideBookingResponse(
        id=booking.id or 0,
        user_id=booking.user_id,
        guide_id=booking.guide_id,
        guide_name=guide.name if guide else None,
        experience_id=booking.experience_id,
        date=booking.date,
        start_time=booking.start_time,
        duration_min=booking.duration_min,
        group_size=booking.group_size,
        status=booking.status,
        payment_status=booking.payment_status,
        hourly_rate=booking.hourly_rate,
        total_cost=booking.total_cost,
        currency=booking.currency,
        notes=booking.notes,
        allowed_transitions=sorted(rules.BOOKING_TRANSITIONS.get(booking.status, set())),
        created_at=booking.created_at,
        decline_reason=booking.decline_reason,
        reviewed=session.exec(
            select(GuideReview).where(GuideReview.booking_id == booking.id)
        ).first()
        is not None,
    )


@router.get(
    "/guides/{guide_id}/quote",
    response_model=GuideBookingQuote,
    summary="Cost estimate before booking (journey 4)",
)
def quote_booking(
    guide_id: int,
    duration_min: int = Query(..., ge=30, le=480),
    group_size: int = Query(default=2, ge=1, le=20),
    extras_per_head: int = Query(default=0, ge=0, le=5000),
    session: Session = Depends(get_session),
):
    """Journey 4: transparent cost estimate, no side effects."""
    guide = session.get(Guide, guide_id)
    if guide is None:
        raise HTTPException(status_code=404, detail="Guide not found")
    charged_hours = rules.math_ceil_div(duration_min, 60)
    return GuideBookingQuote(
        guide_id=guide_id,
        hourly_rate=guide.rate_per_hour,
        duration_min=duration_min,
        group_size=group_size,
        charged_hours=charged_hours,
        extras_per_head=extras_per_head,
        total_cost=rules.calculate_booking_cost(
            guide.rate_per_hour, duration_min, group_size, extras_per_head
        ),
    )


@router.post(
    "/guide-bookings",
    response_model=GuideBookingResponse,
    status_code=status.HTTP_201_CREATED,
    summary="Request a guide booking (journey 4)",
)
def create_booking(
    payload: GuideBookingCreate,
    session: Session = Depends(get_session),
    x_user_id: int = Header(..., alias="X-User-Id"),
):
    """Journey 4: request a booking for a chosen date/time/duration/size."""
    enforce_trust(session, x_user_id, "book_guide")
    guide = session.get(Guide, payload.guide_id)
    if guide is None:
        raise HTTPException(status_code=404, detail="Guide not found")
    profile = guide_profile(session, payload.guide_id)
    if profile.verification_status != "verified":
        raise HTTPException(status_code=403, detail="guide is not verified for bookings")
    if not rules.has_feature(profile.tier, "accept_booking"):
        raise HTTPException(status_code=403, detail="guide tier cannot accept bookings yet")

    if payload.experience_id is not None and session.get(Experience, payload.experience_id) is None:
        raise HTTPException(status_code=404, detail="Experience not found")

    end = _end_time(payload.start_time, payload.duration_min)
    day_slots = session.exec(
        select(GuideAvailability).where(
            GuideAvailability.guide_id == payload.guide_id,
            GuideAvailability.date == payload.date,
        )
    ).all()
    if day_slots and rules.booking_availability_conflict(
        payload.date,
        payload.start_time,
        end,
        [
            {
                "date": str(s.date),
                "start_time": s.start_time,
                "end_time": s.end_time,
                "is_booked": s.is_booked,
            }
            for s in day_slots
        ],
    ):
        raise HTTPException(status_code=409, detail="guide is not free in that window")

    if payload.availability_id is not None:
        slot = session.get(GuideAvailability, payload.availability_id)
        if slot is None or slot.guide_id != payload.guide_id:
            raise HTTPException(status_code=404, detail="Availability slot not found")
        if slot.is_booked:
            raise HTTPException(status_code=409, detail="that slot is already booked")
        if payload.group_size > slot.max_group_size:
            raise HTTPException(
                status_code=422,
                detail=f"slot allows at most {slot.max_group_size} people",
            )
        if payload.start_time < slot.start_time or end > slot.end_time:
            raise HTTPException(
                status_code=422,
                detail=f"booking must fit inside {slot.start_time}-{slot.end_time}",
            )
        slot.is_booked = True
        session.add(slot)

    charged_hours = rules.math_ceil_div(payload.duration_min, 60)
    total = rules.calculate_booking_cost(
        guide.rate_per_hour, payload.duration_min, payload.group_size, payload.extras_per_head
    )
    booking = GuideBooking(
        user_id=x_user_id,
        guide_id=payload.guide_id,
        experience_id=payload.experience_id,
        availability_id=payload.availability_id,
        date=payload.date,
        start_time=payload.start_time,
        duration_min=payload.duration_min,
        group_size=payload.group_size,
        hourly_rate=guide.rate_per_hour,
        total_cost=total,
        notes=payload.notes,
        requested_at=utcnow(),
    )
    session.add(booking)
    session.commit()
    session.refresh(booking)
    logger.info(
        "Guide booking %s: guide=%s user=%s %s %s %smin x%d total=₹%d (charged %sh)",
        booking.id, payload.guide_id, x_user_id, payload.date, payload.start_time,
        payload.duration_min, payload.group_size, total, charged_hours,
    )
    return _booking_payload(session, booking)


@router.get(
    "/guide-bookings", response_model=list[GuideBookingResponse], summary="My bookings (traveller)"
)
def my_bookings(
    session: Session = Depends(get_session),
    x_user_id: int = Header(..., alias="X-User-Id"),
):
    rows = session.exec(
        select(GuideBooking)
        .where(GuideBooking.user_id == x_user_id)
        .order_by(GuideBooking.id.desc())
    ).all()
    return [_booking_payload(session, b) for b in rows]


@router.get(
    "/guides/{guide_id}/bookings",
    response_model=list[GuideBookingResponse],
    summary="Incoming requests (journey 7)",
)
def guide_incoming(
    guide_id: int,
    session: Session = Depends(get_session),
    status_filter: str | None = Query(default=None, alias="status"),
):
    """Journey 7: a guide sees who asked them to lead a tour."""
    stmt = select(GuideBooking).where(GuideBooking.guide_id == guide_id)
    if status_filter:
        stmt = stmt.where(GuideBooking.status == status_filter)
    rows = session.exec(stmt.order_by(GuideBooking.id.desc())).all()
    return [_booking_payload(session, b) for b in rows]


@router.get(
    "/guide-bookings/{booking_id}",
    response_model=GuideBookingResponse,
    summary="Booking detail",
)
def get_booking(
    booking_id: int,
    session: Session = Depends(get_session),
    x_user_id: int = Header(..., alias="X-User-Id"),
):
    booking = session.get(GuideBooking, booking_id)
    if booking is None:
        raise HTTPException(status_code=404, detail="Booking not found")
    profile = guide_profile(session, booking.guide_id)
    is_guide = profile.user_id == x_user_id
    if booking.user_id != x_user_id and not is_guide:
        raise HTTPException(status_code=403, detail="Not your booking")
    return _booking_payload(session, booking)


@router.post(
    "/guide-bookings/{booking_id}/transition",
    response_model=GuideBookingResponse,
    summary="Advance the booking state machine (journeys 4 + 7)",
)
def transition_booking(
    booking_id: int,
    payload: GuideBookingTransition,
    session: Session = Depends(get_session),
    x_user_id: int = Header(..., alias="X-User-Id"),
):
    """Journey 7: accept/decline -> confirmed -> in_progress -> completed.

    The transition table and the actor check both live in
    ``journey_rules`` and are enforced here, server-side.
    """
    booking = session.get(GuideBooking, booking_id)
    if booking is None:
        raise HTTPException(status_code=404, detail="Booking not found")

    profile = guide_profile(session, booking.guide_id)
    actor = "guide" if profile.user_id == x_user_id else "user"
    if actor == "user" and booking.user_id != x_user_id:
        raise HTTPException(status_code=403, detail="Not your booking")

    ok, reason = rules.can_transition_booking(booking.status, payload.status, actor)
    if not ok:
        raise HTTPException(status_code=409, detail=reason)

    now = utcnow()
    booking.status = payload.status
    if payload.status == "accepted":
        booking.accepted_at = now
    elif payload.status == "confirmed":
        booking.confirmed_at = now
    elif payload.status == "in_progress":
        booking.started_at = now
    elif payload.status == "completed":
        booking.completed_at = now
        booking.payment_status = "settled"
        profile.completed_tours += 1
        profile.xp += 50
        session.add(profile)
    else:  # declined / cancelled
        booking.closed_at = now
        booking.decline_reason = payload.reason
        if payload.payment_status:
            booking.payment_status = payload.payment_status
        if payload.status == "declined" and booking.availability_id:
            slot = session.get(GuideAvailability, booking.availability_id)
            if slot is not None:
                slot.is_booked = False
                session.add(slot)
    if payload.status not in ("declined", "cancelled") and payload.payment_status:
        booking.payment_status = payload.payment_status
    session.add(booking)
    session.commit()
    session.refresh(booking)
    logger.info("Booking %s: %s -> %s by %s", booking_id, "moved", payload.status, actor)
    _notify_booking_status(session, booking, payload.status)
    return _booking_payload(session, booking)


@router.post(
    "/guide-bookings/{booking_id}/reviews",
    response_model=GuideReviewResponse,
    status_code=status.HTTP_201_CREATED,
    summary="Review a completed tour (journey 4)",
)
def review_booking(
    booking_id: int,
    payload: GuideReviewCreate,
    session: Session = Depends(get_session),
    x_user_id: int = Header(..., alias="X-User-Id"),
):
    """Journey 4 final step: only the traveller, only after completion."""
    enforce_trust(session, x_user_id, "leave_review")
    booking = session.get(GuideBooking, booking_id)
    if booking is None or booking.user_id != x_user_id:
        raise HTTPException(status_code=404, detail="Booking not found")
    if booking.status != "completed":
        raise HTTPException(status_code=409, detail="only completed tours can be reviewed")
    if session.exec(
        select(GuideReview).where(
            GuideReview.booking_id == booking_id, GuideReview.user_id == x_user_id
        )
    ).first():
        raise HTTPException(status_code=409, detail="already reviewed this tour")

    review = GuideReview(
        booking_id=booking_id,
        user_id=x_user_id,
        guide_id=booking.guide_id,
        rating=payload.rating,
        comment=payload.comment,
        punctuality=payload.punctuality,
        knowledge=payload.knowledge,
    )
    session.add(review)

    profile = guide_profile(session, booking.guide_id)
    profile.rating_sum += payload.rating
    profile.review_count += 1
    session.add(profile)
    session.commit()
    session.refresh(review)
    logger.info("Guide %s reviewed %s (now %s)", booking.guide_id, payload.rating, _average_rating(profile))
    return review


# ---------------------------------------------------------------------------
# Journey 8: growth
# ---------------------------------------------------------------------------


@router.post(
    "/guides/{guide_id}/trainings",
    response_model=GuideTrainingResponse,
    status_code=status.HTTP_201_CREATED,
    summary="Enrol in a training course (journey 8)",
)
def enrol_training(
    guide_id: int,
    payload: GuideTrainingCreate,
    session: Session = Depends(get_session),
    x_user_id: int | None = Header(default=None, alias="X-User-Id"),
):
    guide_profile(session, guide_id)
    _require_guide_owner(session, guide_id, x_user_id)
    existing = session.exec(
        select(GuideTraining).where(
            GuideTraining.guide_id == guide_id,
            GuideTraining.course_code == payload.course_code,
        )
    ).first()
    if existing:
        raise HTTPException(status_code=409, detail="already enrolled in this course")
    training = GuideTraining(
        guide_id=guide_id,
        course_code=payload.course_code,
        course_name=payload.course_name or payload.course_code,
        status="in_progress",
        grants_tier=payload.grants_tier,
    )
    session.add(training)
    session.commit()
    session.refresh(training)
    return training


@router.post(
    "/guides/{guide_id}/trainings/{training_id}/complete",
    response_model=GuideTrainingResponse,
    summary="Complete a course -> certification (journey 8)",
)
def complete_training(
    guide_id: int,
    training_id: int,
    payload: GuideTrainingComplete,
    session: Session = Depends(get_session),
    x_user_id: int | None = Header(default=None, alias="X-User-Id"),
):
    """Passing the course (>=50) grants the certification it promises."""
    _require_guide_owner(session, guide_id, x_user_id)
    training = session.get(GuideTraining, training_id)
    if training is None or training.guide_id != guide_id:
        raise HTTPException(status_code=404, detail="Training not found")
    if training.status == "completed":
        raise HTTPException(status_code=409, detail="course already completed")

    training.score = payload.score
    if payload.score < 50:
        training.status = "in_progress"
        session.add(training)
        session.commit()
        session.refresh(training)
        raise HTTPException(
            status_code=422,
            detail=f"score {payload.score} below the pass mark of 50; retake allowed",
        )

    training.status = "completed"
    training.completed_at = utcnow()
    session.add(training)

    profile = guide_profile(session, guide_id)
    if training.grants_tier and training.grants_tier in rules.GUIDE_TIERS:
        current = rules.GUIDE_TIERS.index(profile.tier)
        if rules.GUIDE_TIERS.index(training.grants_tier) > current:
            profile.tier = training.grants_tier
            session.add(profile)
    profile.xp += 25
    session.add(profile)
    session.commit()
    session.refresh(training)
    logger.info("Guide %s completed course %s (tier now %s)", guide_id, training.course_code, profile.tier)
    return training


@router.get(
    "/guides/{guide_id}/growth",
    response_model=GuideGrowthResponse,
    summary="Tier progress and unlocked features (journey 8)",
)
def guide_growth(guide_id: int, session: Session = Depends(get_session)):
    """Journey 8: what the guide has, what is next, what is unlocked."""
    profile = guide_profile(session, guide_id)
    average = _average_rating(profile)
    certifications = _certifications(session, guide_id)
    next_tier = rules.next_guide_tier(
        tier=profile.tier,
        completed_tours=profile.completed_tours,
        average_rating=average,
        certifications=len(certifications),
    )
    requirement = rules.TIER_REQUIREMENTS.get(next_tier or "", {})
    trainings = session.exec(
        select(GuideTraining).where(GuideTraining.guide_id == guide_id)
    ).all()
    return GuideGrowthResponse(
        guide_id=guide_id,
        tier=profile.tier,
        next_tier=next_tier,
        tier_progress={
            "completed_tours": {
                "have": profile.completed_tours,
                "need": requirement.get("completed_tours", 0),
            },
            "average_rating": {
                "have": average,
                "need": requirement.get("rating", 0.0),
            },
            "certifications": {
                "have": len(certifications),
                "need": requirement.get("certifications", 0),
            },
        },
        xp=profile.xp,
        completed_tours=profile.completed_tours,
        review_count=profile.review_count,
        average_rating=average,
        certifications=certifications,
        features=rules.tier_features(profile.tier),
        visibility_boost=rules.visibility_boost(profile.tier),
        trainings=[
            {
                "course_code": t.course_code,
                "course_name": t.course_name,
                "status": t.status,
                "score": t.score,
                "grants_tier": t.grants_tier,
            }
            for t in trainings
        ],
    )
