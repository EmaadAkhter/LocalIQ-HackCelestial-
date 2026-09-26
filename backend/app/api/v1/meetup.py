"""Journey 2: Random Meetup (simulated, PRD v2 Phase 1).

Flow: verification check -> compatibility match -> shared plan -> safety state
-> post-meet review.

Everything is deterministic and server-gated:

* creating a request requires the ``standard`` simulated trust tier;
* matching is compatibility scoring over stated preferences (no strangers are
  contacted, no PII is exposed beyond a display name);
* blocks are honoured during matching;
* requests expire.
"""

from __future__ import annotations

import logging
from datetime import timedelta

from fastapi import APIRouter, Depends, Header, HTTPException, Query, status
from sqlmodel import Session, select

from app.database import get_session
from app.models import Experience, User
from app.models_prd import (
    GuideProfile,
    MeetupBlock,
    MeetupMatch,
    MeetupRequest,
    MeetupReview,
    UserProgress,
)
from app.schemas_prd import (
    BlockCreate,
    BlockResponse,
    MatchCandidate,
    MeetupMatchRequest,
    MeetupRequestCreate,
    MeetupRequestResponse,
    MeetupReviewCreate,
    MeetupReviewResponse,
    MeetupStatusRequest,
    TrustGate,
)
from app.services import journey_rules as rules
from app.timeutil import utcnow
from app.api.v1.journey_deps import enforce_trust, get_experience_or_404

logger = logging.getLogger(__name__)
router = APIRouter()


def _expired(request: MeetupRequest) -> bool:
    return rules.is_expired(request.expires_at).expired


def _request_payload(
    session: Session, request: MeetupRequest, gate: dict | None = None
) -> MeetupRequestResponse:
    trust_gate = None
    if gate is not None:
        trust_gate = TrustGate(**gate)
    return MeetupRequestResponse(
        id=request.id or 0,
        user_id=request.user_id,
        status="expired" if _expired(request) else request.status,
        category=request.category,
        area=request.area,
        start_time=request.start_time,
        duration_min=request.duration_min,
        budget_inr=request.budget_inr,
        group_size_pref=request.group_size_pref,
        interests=list(request.interests or []),
        trust_gate=trust_gate,
        created_at=request.created_at,
        expires_at=request.expires_at,
    )


def _match_payload(session: Session, match: MeetupMatch) -> dict:
    experience = (
        session.get(Experience, match.experience_id) if match.experience_id else None
    )
    names = [
        (session.get(User, uid).name if session.get(User, uid) else f"user-{uid}")
        for uid in (match.member_ids or [])
    ]
    return {
        "id": match.id,
        "request_id": match.request_id,
        "status": match.status,
        "experience": (
            {
                "id": experience.id,
                "name": experience.name,
                "category": experience.category,
                "avg_cost": experience.avg_cost,
                "duration_min": experience.duration_min,
                "image_url": experience.image_url,
            }
            if experience
            else None
        ),
        "member_ids": list(match.member_ids or []),
        "member_names": names,
        "compatibility_score": match.compatibility_score,
        "shared_interests": list(match.shared_interests or []),
        "plan": dict(match.plan or {}),
        "meeting_point": match.meeting_point,
        "safety": {"score": match.safety_score, "meeting_point": match.meeting_point},
        "start_time": match.start_time,
        "duration_min": match.duration_min,
        "total_cost": match.total_cost,
        "keep_group": match.keep_group,
    }


@router.post(
    "/meetup/requests",
    response_model=MeetupRequestResponse,
    status_code=status.HTTP_201_CREATED,
    summary="Create a meetup request (trust gated)",
)
def create_meetup_request(
    payload: MeetupRequestCreate,
    session: Session = Depends(get_session),
    x_user_id: int = Header(..., alias="X-User-Id"),
):
    """Step 1: verification check, then create the request."""
    user = session.get(User, x_user_id)
    if user is None:
        raise HTTPException(status_code=401, detail="Unknown user")

    gate = enforce_trust(session, x_user_id, "create_meetup_request")
    get_experience_or_404(session, payload.experience_id)

    request = MeetupRequest(
        user_id=x_user_id,
        experience_id=payload.experience_id,
        category=payload.category.lower(),
        area=payload.area,
        lat=payload.lat,
        lng=payload.lng,
        start_time=payload.start_time,
        duration_min=payload.duration_min,
        budget_inr=payload.budget_inr,
        group_size_pref=payload.group_size_pref,
        interests=[i.lower() for i in payload.interests],
        note=payload.note,
        expires_at=utcnow() + timedelta(hours=payload.expires_in_hours),
    )
    session.add(request)
    session.commit()
    session.refresh(request)

    response = _request_payload(session, request, gate)
    logger.info("Meetup request %s by user %s (tier %s)", request.id, x_user_id, gate["current_tier"])
    return response


@router.get("/meetup/requests", response_model=list[MeetupRequestResponse], summary="My meetup requests")
def list_my_requests(
    session: Session = Depends(get_session),
    x_user_id: int = Header(..., alias="X-User-Id"),
):
    rows = session.exec(
        select(MeetupRequest)
        .where(MeetupRequest.user_id == x_user_id)
        .order_by(MeetupRequest.id.desc())
    ).all()
    return [_request_payload(session, r) for r in rows]


@router.get(
    "/meetup/requests/{request_id}",
    response_model=MeetupRequestResponse,
    summary="Get one meetup request",
)
def get_meetup_request(
    request_id: int,
    session: Session = Depends(get_session),
    x_user_id: int = Header(..., alias="X-User-Id"),
):
    request = session.get(MeetupRequest, request_id)
    if request is None or request.user_id != x_user_id:
        raise HTTPException(status_code=404, detail="Meetup request not found")
    return _request_payload(session, request)


@router.get(
    "/meetup/requests/{request_id}/candidates",
    response_model=list[MatchCandidate],
    summary="Compatibility-scored candidates",
)
def list_candidates(
    request_id: int,
    session: Session = Depends(get_session),
    x_user_id: int = Header(..., alias="X-User-Id"),
    include_ineligible: bool = Query(default=True),
):
    """Step 2: deterministic compatibility scoring against other travellers.

    Phase 1 matches against other *registered* travellers' stated interests and
    budget. No personal data beyond a display name is exposed.
    """
    request = session.get(MeetupRequest, request_id)
    if request is None or request.user_id != x_user_id:
        raise HTTPException(status_code=404, detail="Meetup request not found")
    if _expired(request):
        raise HTTPException(status_code=409, detail="Meetup request has expired")

    blocked = {
        (row.blocker_id, row.blocked_id) for row in session.exec(select(MeetupBlock)).all()
    } | {(row.blocked_id, row.blocker_id) for row in session.exec(select(MeetupBlock)).all()}

    others = session.exec(select(User).where(User.id != request.user_id)).all()
    out: list[MatchCandidate] = []
    for candidate in others:
        # Candidate preferences: their posted meetup requests, newest first.
        their_requests = session.exec(
            select(MeetupRequest)
            .where(MeetupRequest.user_id == candidate.id)
            .order_by(MeetupRequest.id.desc())
        ).all()
        interests = list(their_requests[0].interests or []) if their_requests else []
        budget = their_requests[0].budget_inr if their_requests else request.budget_inr
        duration = their_requests[0].duration_min if their_requests else request.duration_min
        start = their_requests[0].start_time if their_requests else request.start_time
        tier = (
            "standard"
            if session.exec(
                select(GuideProfile).where(GuideProfile.user_id == candidate.id)
            ).first()
            else "basic"
        )

        compat = rules.compatibility_score(
            request_interests=list(request.interests or []),
            request_budget=request.budget_inr,
            request_duration=request.duration_min,
            request_start=request.start_time,
            member_interests=interests,
            member_budget=budget,
            member_duration=duration,
            member_start=start,
            member_tier=tier,
        )
        is_blocked = (request.user_id, candidate.id) in blocked
        eligible, reason = rules.can_match(
            compat["score"], request.group_size_pref, blocked=is_blocked
        )
        if not include_ineligible and not eligible:
            continue
        out.append(
            MatchCandidate(
                user_id=candidate.id,
                name=candidate.name,
                compatibility=compat,
                shared_interests=compat["shared_interests"],
                eligible=eligible,
                reason=reason,
            )
        )
    out.sort(key=lambda c: (-c.compatibility["score"], c.user_id))
    return out


@router.post(
    "/meetup/requests/{request_id}/match",
    summary="Form a meetup group (compatibility + shared plan + safety)",
)
def form_match(
    request_id: int,
    payload: MeetupMatchRequest | None = None,
    session: Session = Depends(get_session),
    x_user_id: int = Header(..., alias="X-User-Id"),
):
    """Step 3: form the micro-group and build the shared plan + safety state.

    ``member_ids`` is optional: when the client does not choose anyone, the
    server picks the best eligible candidates it already ranked, which is the
    behaviour the journey describes ("we find you a group").
    """
    member_ids = list(payload.member_ids) if payload else []
    request = session.get(MeetupRequest, request_id)
    if request is None or request.user_id != x_user_id:
        raise HTTPException(status_code=404, detail="Meetup request not found")
    if _expired(request):
        raise HTTPException(status_code=409, detail="Meetup request has expired")
    if request.status != "open":
        raise HTTPException(status_code=409, detail=f"request is '{request.status}', not open")

    gate = enforce_trust(session, x_user_id, "be_matched")

    if not member_ids:
        ranked = list_candidates(
            request_id,
            session=session,
            x_user_id=x_user_id,
        )
        wanted = max(1, (request.group_size_pref or 2) - 1)
        member_ids = [row.user_id for row in ranked if row.eligible][:wanted]
        if not member_ids:
            raise HTTPException(
                status_code=409, detail="no eligible candidates to match with right now"
            )

    if len(member_ids) + 1 < 2:
        raise HTTPException(status_code=400, detail="A meetup needs at least 2 people")
    if len(member_ids) + 1 > 5:
        raise HTTPException(status_code=400, detail="MVP caps meetups at 5 people")

    blocked = {
        (row.blocker_id, row.blocked_id) for row in session.exec(select(MeetupBlock)).all()
    } | {(row.blocked_id, row.blocker_id) for row in session.exec(select(MeetupBlock)).all()}

    all_members = [request.user_id, *member_ids]
    shared: set[str] = set()
    scores: list[float] = []
    for member_id in member_ids:
        if (request.user_id, member_id) in blocked or (member_id, request.user_id) in blocked:
            raise HTTPException(
                status_code=409, detail=f"cannot match user {member_id} (blocked/reported)"
            )
        their = session.exec(
            select(MeetupRequest)
            .where(MeetupRequest.user_id == member_id)
            .order_by(MeetupRequest.id.desc())
        ).first()
        compat = rules.compatibility_score(
            request_interests=list(request.interests or []),
            request_budget=request.budget_inr,
            request_duration=request.duration_min,
            request_start=request.start_time,
            member_interests=list(their.interests or []) if their else [],
            member_budget=their.budget_inr if their else request.budget_inr,
            member_duration=their.duration_min if their else request.duration_min,
            member_start=their.start_time if their else request.start_time,
            member_tier="standard",
        )
        eligible, reason = rules.can_match(
            compat["score"], len(member_ids) + 1, blocked=False
        )
        if not eligible:
            raise HTTPException(
                status_code=409,
                detail=f"user {member_id} not eligible: {reason} (score {compat['score']})",
            )
        scores.append(compat["score"])
        shared.update(compat["shared_interests"])

    experience = (
        session.get(Experience, request.experience_id) if request.experience_id else None
    )
    safety = rules.safety_score(experience, hour=int(request.start_time[:2]))
    group_size = len(all_members)
    per_head = int((request.budget_inr or 0) / max(1, group_size))

    plan = {
        "stops": (
            [
                {
                    "experience_id": experience.id,
                    "name": experience.name,
                    "category": experience.category,
                    "duration_min": experience.duration_min,
                }
            ]
            if experience
            else []
        ),
        "start_time": request.start_time,
        "duration_min": request.duration_min,
        "per_head_budget": per_head,
        "total_budget": per_head * group_size,
        "group_size": group_size,
    }

    match = MeetupMatch(
        request_id=request_id,
        experience_id=request.experience_id,
        member_ids=all_members,
        compatibility_score=round(sum(scores) / len(scores), 1) if scores else 0.0,
        shared_interests=sorted(shared),
        plan=plan,
        meeting_point=safety["meeting_point"],
        safety_score=safety["score"],
        start_time=request.start_time,
        duration_min=request.duration_min,
        total_cost=plan["total_budget"],
    )
    request.status = "matched"
    session.add(match)
    session.commit()
    session.refresh(match)

    logger.info(
        "Meetup match %s formed: users=%s compatibility=%.1f safety=%s",
        match.id,
        all_members,
        match.compatibility_score,
        safety["score"],
    )
    payload = _match_payload(session, match)
    payload["trust_gate"] = gate
    payload["safety"]["signals"] = safety["signals"]
    return payload


@router.get("/meetup/matches/{match_id}", summary="Get a meetup group")
def get_match(
    match_id: int,
    session: Session = Depends(get_session),
    x_user_id: int = Header(..., alias="X-User-Id"),
):
    match = session.get(MeetupMatch, match_id)
    if match is None or x_user_id not in (match.member_ids or []):
        raise HTTPException(status_code=404, detail="Meetup match not found")
    return _match_payload(session, match)


@router.post("/meetup/matches/{match_id}/status", summary="Confirm / complete / cancel")
def update_match_status(
    match_id: int,
    payload: MeetupStatusRequest,
    session: Session = Depends(get_session),
    x_user_id: int = Header(..., alias="X-User-Id"),
):
    """Step 4/5: confirm the plan, then mark it completed."""
    match = session.get(MeetupMatch, match_id)
    if match is None or x_user_id not in (match.member_ids or []):
        raise HTTPException(status_code=404, detail="Meetup match not found")

    allowed = {
        "formed": {"confirmed", "cancelled"},
        "confirmed": {"completed", "cancelled"},
        "completed": set(),
        "cancelled": set(),
    }
    if payload.status not in allowed.get(match.status, set()):
        raise HTTPException(
            status_code=409, detail=f"cannot go from '{match.status}' to '{payload.status}'"
        )
    match.status = payload.status
    session.add(match)
    session.commit()
    session.refresh(match)
    return _match_payload(session, match)


@router.post(
    "/meetup/matches/{match_id}/reviews",
    response_model=MeetupReviewResponse,
    status_code=status.HTTP_201_CREATED,
    summary="Post-meetup review of the experience",
)
def review_meetup(
    match_id: int,
    payload: MeetupReviewCreate,
    session: Session = Depends(get_session),
    x_user_id: int = Header(..., alias="X-User-Id"),
):
    """Step 5: rate the experience (not each other)."""
    enforce_trust(session, x_user_id, "leave_review")
    match = session.get(MeetupMatch, match_id)
    if match is None or x_user_id not in (match.member_ids or []):
        raise HTTPException(status_code=404, detail="Meetup match not found")
    if match.status != "completed":
        raise HTTPException(status_code=409, detail="meetup must be completed before reviewing")

    existing = session.exec(
        select(MeetupReview).where(
            MeetupReview.match_id == match_id, MeetupReview.user_id == x_user_id
        )
    ).first()
    if existing:
        raise HTTPException(status_code=409, detail="already reviewed this meetup")

    review = MeetupReview(
        match_id=match_id,
        user_id=x_user_id,
        experience_rating=payload.experience_rating,
        would_repeat=payload.would_repeat,
        comment=payload.comment,
    )
    session.add(review)
    session.commit()
    session.refresh(review)
    return review


@router.post(
    "/meetup/blocks",
    response_model=BlockResponse,
    status_code=status.HTTP_201_CREATED,
    summary="Block or report a member",
)
def block_member(
    payload: BlockCreate,
    session: Session = Depends(get_session),
    x_user_id: int = Header(..., alias="X-User-Id"),
):
    """Block/report state. Blocks are enforced during matching."""
    if payload.blocked_id == x_user_id:
        raise HTTPException(status_code=400, detail="cannot block yourself")
    if session.get(User, payload.blocked_id) is None:
        raise HTTPException(status_code=404, detail="Unknown user")

    existing = session.exec(
        select(MeetupBlock).where(
            MeetupBlock.blocker_id == x_user_id, MeetupBlock.blocked_id == payload.blocked_id
        )
    ).first()
    if existing:
        return existing
    row = MeetupBlock(
        blocker_id=x_user_id,
        blocked_id=payload.blocked_id,
        reason=payload.reason,
        reported=payload.report,
    )
    session.add(row)
    session.commit()
    session.refresh(row)
    return row


@router.get("/meetup/progress", summary="My meetup XP/level")
def my_meetup_progress(
    session: Session = Depends(get_session),
    x_user_id: int = Header(..., alias="X-User-Id"),
):
    from app.models_prd import Badge

    progress = session.exec(
        select(UserProgress).where(UserProgress.user_id == x_user_id)
    ).first()
    if progress is None:
        progress = UserProgress(user_id=x_user_id, xp=0, level=1)
        session.add(progress)
        session.commit()
        session.refresh(progress)
    catalogue = {b.code: b for b in session.exec(select(Badge)).all()}
    badges = [
        {
            "code": code,
            "name": catalogue[code].name if code in catalogue else code,
            "description": catalogue[code].description if code in catalogue else "",
        }
        for code in (progress.badges or [])
    ]
    return {
        "user_id": x_user_id,
        "xp": progress.xp,
        "level": progress.level,
        "level_name": f"Level {progress.level}",
        "badges": badges,
        "quests_started": progress.quests_started,
        "quests_completed": progress.quests_completed,
    }
