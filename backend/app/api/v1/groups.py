"""Journey 3: Group decision.

Flow: create group -> members/preferences -> group-optimal recommendations
-> vote -> final plan lock.

The group constraint set is the *aggregate* of member preferences (lowest
budget, median time, union of interests, accessibility if anyone needs it) and
is then fed through the existing recommendation engine, so group plans obey the
same hard constraints as solo ones.
"""

from __future__ import annotations

import logging

from fastapi import APIRouter, Depends, Header, HTTPException, status
from sqlmodel import Session, select

from app.database import get_session
from app.models import Experience, User
from app.models_prd import Group, GroupMember, GroupOption, GroupVote
from app.schemas_prd import (
    GroupCreate,
    GroupMemberResponse,
    GroupOptionResponse,
    GroupPreferences,
    GroupResponse,
    GroupVoteCreate,
    GroupVoteResponse,
    GroupVoteTally,
)
from app.services import journey_rules as rules
from app.services import recommender
from app.timeutil import utcnow

logger = logging.getLogger(__name__)
router = APIRouter()

GROUP_TRANSITIONS: dict[str, set[str]] = {
    "collecting_preferences": {"collecting_votes", "cancelled"},
    "collecting_votes": {"locked", "collecting_preferences", "cancelled"},
    "locked": set(),
    "cancelled": set(),
}


def _group_or_404(session: Session, group_id: int, user_id: int | None = None) -> Group:
    group = session.get(Group, group_id)
    if group is None:
        raise HTTPException(status_code=404, detail="Group not found")
    if user_id is not None:
        member = session.exec(
            select(GroupMember).where(
                GroupMember.group_id == group_id, GroupMember.user_id == user_id
            )
        ).first()
        if member is None and group.owner_id != user_id:
            raise HTTPException(status_code=403, detail="Not a member of this group")
    return group


def _members(session: Session, group_id: int) -> list[GroupMember]:
    return list(
        session.exec(select(GroupMember).where(GroupMember.group_id == group_id)).all()
    )


def _aggregated(group: Group, members: list[GroupMember]) -> dict:
    return rules.aggregate_group_constraints(
        [
            {
                "interests": list(m.interests or []),
                "budget_inr": m.budget_inr,
                "time_hours": m.time_hours,
                "accessibility": m.accessibility,
            }
            for m in members
        ],
        {
            "location": group.area,
            "budget_inr": group.budget_inr,
            "time_hours": group.time_hours,
            "interests": list(group.interests or []),
            "accessibility": group.accessibility,
        },
    )


def _group_payload(session: Session, group: Group) -> GroupResponse:
    members = _members(session, group.id or 0)
    options = session.exec(
        select(GroupOption)
        .where(GroupOption.group_id == group.id)
        .order_by(GroupOption.rank)
    ).all()
    votes = session.exec(select(GroupVote).where(GroupVote.group_id == group.id)).all()
    return GroupResponse(
        id=group.id or 0,
        name=group.name,
        owner_id=group.owner_id,
        status=group.status,
        area=group.area,
        time_hours=group.time_hours,
        budget_inr=group.budget_inr,
        interests=list(group.interests or []),
        accessibility=group.accessibility,
        max_members=group.max_members,
        member_count=len(members),
        aggregated=_aggregated(group, members),
        final_plan=dict(group.final_plan) if group.final_plan else None,
        locked_at=group.locked_at,
        options=[
            GroupOptionResponse(
                id=o.id or 0,
                label=o.label,
                rank=o.rank,
                score=o.score,
                stops=list(o.stops or []),
                total_minutes=o.total_minutes,
                total_cost=o.total_cost,
                votes=o.votes,
                is_winner=o.is_winner,
            )
            for o in options
        ],
        votes_cast=len({v.user_id for v in votes}),
        quorum_reached=rules.quorum_reached(len({v.user_id for v in votes}), len(members)),
    )


@router.post(
    "/groups", response_model=GroupResponse, status_code=status.HTTP_201_CREATED, summary="Create a group"
)
def create_group(
    payload: GroupCreate,
    session: Session = Depends(get_session),
    x_user_id: int = Header(..., alias="X-User-Id"),
):
    """Step 1: create the group; the owner joins as a member."""
    from app.api.v1.journey_deps import enforce_trust

    if session.get(User, x_user_id) is None:
        raise HTTPException(status_code=401, detail="Unknown user")
    enforce_trust(session, x_user_id, "create_group")

    group = Group(
        name=payload.name,
        owner_id=x_user_id,
        area=payload.area,
        time_hours=payload.time_hours,
        budget_inr=payload.budget_inr,
        interests=[i.lower() for i in payload.interests],
        accessibility=payload.accessibility,
        max_members=payload.max_members,
    )
    session.add(group)
    session.commit()
    session.refresh(group)

    session.add(
        GroupMember(
            group_id=group.id or 0,
            user_id=x_user_id,
            is_owner=True,
            interests=[i.lower() for i in payload.interests],
            budget_inr=payload.budget_inr,
            time_hours=payload.time_hours,
            accessibility=payload.accessibility,
        )
    )
    session.commit()
    logger.info("Group %s created by user %s", group.id, x_user_id)
    return _group_payload(session, group)


@router.post(
    "/groups/{group_id}/members",
    response_model=GroupMemberResponse,
    status_code=status.HTTP_201_CREATED,
    summary="Join a group with preferences",
)
def join_group(
    group_id: int,
    payload: GroupPreferences,
    session: Session = Depends(get_session),
    x_user_id: int = Header(..., alias="X-User-Id"),
):
    """Step 2: members declare their preferences."""
    from app.api.v1.journey_deps import enforce_trust

    enforce_trust(session, x_user_id, "join_group")
    group = _group_or_404(session, group_id)
    if group.status != "collecting_preferences":
        raise HTTPException(status_code=409, detail=f"group is '{group.status}'")

    members = _members(session, group_id)
    if len(members) >= group.max_members:
        raise HTTPException(status_code=409, detail="group is full")

    existing = session.exec(
        select(GroupMember).where(
            GroupMember.group_id == group_id, GroupMember.user_id == x_user_id
        )
    ).first()
    if existing:
        existing.interests = [i.lower() for i in payload.interests]
        existing.budget_inr = payload.budget_inr
        existing.time_hours = payload.time_hours
        existing.accessibility = payload.accessibility
        member = existing
    else:
        member = GroupMember(
            group_id=group_id,
            user_id=x_user_id,
            is_owner=False,
            interests=[i.lower() for i in payload.interests],
            budget_inr=payload.budget_inr,
            time_hours=payload.time_hours,
            accessibility=payload.accessibility,
        )
        session.add(member)
    session.commit()
    session.refresh(member)
    user = session.get(User, x_user_id)
    return GroupMemberResponse(
        user_id=member.user_id,
        name=user.name if user else f"user-{x_user_id}",
        is_owner=member.is_owner,
        interests=list(member.interests or []),
        budget_inr=member.budget_inr,
        time_hours=member.time_hours,
        accessibility=member.accessibility,
        has_voted=member.has_voted,
    )


@router.get("/groups/{group_id}", response_model=GroupResponse, summary="Get a group")
def get_group(
    group_id: int,
    session: Session = Depends(get_session),
    x_user_id: int = Header(..., alias="X-User-Id"),
):
    return _group_payload(session, _group_or_404(session, group_id, x_user_id))


@router.get(
    "/groups/{group_id}/members", response_model=list[GroupMemberResponse], summary="Group members"
)
def list_members(
    group_id: int,
    session: Session = Depends(get_session),
    x_user_id: int = Header(..., alias="X-User-Id"),
):
    _group_or_404(session, group_id, x_user_id)
    out = []
    for member in _members(session, group_id):
        user = session.get(User, member.user_id)
        out.append(
            GroupMemberResponse(
                user_id=member.user_id,
                name=user.name if user else f"user-{member.user_id}",
                is_owner=member.is_owner,
                interests=list(member.interests or []),
                budget_inr=member.budget_inr,
                time_hours=member.time_hours,
                accessibility=member.accessibility,
                has_voted=member.has_voted,
            )
        )
    return out


@router.post(
    "/groups/{group_id}/options",
    response_model=list[GroupOptionResponse],
    summary="Generate group-optimal plan options",
)
def generate_options(
    group_id: int,
    session: Session = Depends(get_session),
    x_user_id: int = Header(..., alias="X-User-Id"),
):
    """Step 3: group-optimal recommendations via the existing engine.

    Up to three options are produced: the top-ranked single stop, the best
    pair, and the best value pick. All are built from the aggregated group
    constraints, so every option already satisfies the hard constraints.
    """
    group = _group_or_404(session, group_id, x_user_id)
    if group.status not in ("collecting_preferences", "collecting_votes"):
        raise HTTPException(status_code=409, detail=f"group is '{group.status}'")

    members = _members(session, group_id)
    agg = _aggregated(group, members)

    experiences = list(session.exec(select(Experience)).all())
    ranked = recommender.recommend(
        experiences,
        location=agg["location"],
        time_hours=agg["time_hours"],
        budget_inr=agg["budget_inr"],
        interests=agg["interests"],
        accessibility="wheelchair-accessible" if agg["accessibility"] else None,
        limit=10,
    )["results"]
    if not ranked:
        raise HTTPException(
            status_code=409, detail="no feasible plan for the group's constraints"
        )

    for old in session.exec(
        select(GroupOption).where(GroupOption.group_id == group_id)
    ).all():
        session.delete(old)
    session.commit()

    picks: list[tuple[str, list]] = [
        ("Top pick", [ranked[0].experience.id]),
    ]
    if len(ranked) > 1:
        pair = sorted(ranked[:2], key=lambda r: r.distance_km)
        picks.append(("Quick pair", [r.experience.id for r in pair]))
    if len(ranked) > 2:
        picks.append(("Value option", [ranked[-1].experience.id, ranked[0].experience.id]))

    created: list[GroupOption] = []
    for rank, (label, stop_ids) in enumerate(picks, start=1):
        stops = [session.get(Experience, sid) for sid in stop_ids]
        stops = [s for s in stops if s is not None]
        minutes = sum(s.duration_min for s in stops)
        cost = sum(s.avg_cost for s in stops)
        option = GroupOption(
            group_id=group_id,
            label=label,
            rank=rank,
            score=ranked[0].score if rank == 1 else round(ranked[0].score / rank, 2),
            stops=stop_ids,
            total_minutes=minutes,
            total_cost=cost,
        )
        session.add(option)
        created.append(option)
    group.status = "collecting_votes"
    session.add(group)
    session.commit()
    for option in created:
        session.refresh(option)

    logger.info(
        "Group %s generated %d options from %d members", group_id, len(created), len(members)
    )
    return [
        GroupOptionResponse(
            id=o.id or 0,
            label=o.label,
            rank=o.rank,
            score=o.score,
            stops=list(o.stops or []),
            total_minutes=o.total_minutes,
            total_cost=o.total_cost,
            votes=o.votes,
            is_winner=o.is_winner,
        )
        for o in created
    ]


@router.post(
    "/groups/{group_id}/votes",
    response_model=GroupVoteResponse,
    status_code=status.HTTP_201_CREATED,
    summary="Vote for an option",
)
def cast_vote(
    group_id: int,
    payload: GroupVoteCreate,
    session: Session = Depends(get_session),
    x_user_id: int = Header(..., alias="X-User-Id"),
):
    """Step 4: one vote per member; re-voting replaces the previous vote."""
    group = _group_or_404(session, group_id, x_user_id)
    if group.status != "collecting_votes":
        raise HTTPException(
            status_code=409, detail=f"group is '{group.status}', not collecting votes"
        )
    option = session.get(GroupOption, payload.option_id)
    if option is None or option.group_id != group_id:
        raise HTTPException(status_code=404, detail="Option not found in this group")

    existing = session.exec(
        select(GroupVote).where(
            GroupVote.group_id == group_id, GroupVote.user_id == x_user_id
        )
    ).first()
    if existing:
        if existing.option_id == payload.option_id:
            raise HTTPException(status_code=409, detail="already voted for this option")
        session.delete(existing)
        session.flush()
        option = session.get(GroupOption, payload.option_id)
        option.votes = max(0, option.votes - 1)
        session.add(option)

    vote = GroupVote(
        group_id=group_id,
        option_id=payload.option_id,
        user_id=x_user_id,
        rank=payload.rank,
        comment=payload.comment,
    )
    option = session.get(GroupOption, payload.option_id)
    option.votes += 1
    session.add(option)
    session.add(vote)

    member = session.exec(
        select(GroupMember).where(
            GroupMember.group_id == group_id, GroupMember.user_id == x_user_id
        )
    ).first()
    if member:
        member.has_voted = True
        session.add(member)
    session.commit()
    session.refresh(vote)
    return vote


@router.get(
    "/groups/{group_id}/votes",
    response_model=GroupVoteTally,
    summary="Vote tally (and lock once quorum is reached)",
)
def tally_votes(
    group_id: int,
    session: Session = Depends(get_session),
    x_user_id: int = Header(..., alias="X-User-Id"),
):
    """Step 5: tally, and lock the plan when a majority has voted."""
    group = _group_or_404(session, group_id, x_user_id)
    if group.status not in ("collecting_votes", "locked"):
        raise HTTPException(status_code=409, detail=f"group is '{group.status}'")

    members = _members(session, group_id)
    votes = list(session.exec(select(GroupVote).where(GroupVote.group_id == group_id)).all())
    options = list(
        session.exec(
            select(GroupOption).where(GroupOption.group_id == group_id)
        ).all()
    )
    option_rank = {o.id or 0: o.rank for o in options}
    vote_dicts = [
        {"option_id": v.option_id, "user_id": v.user_id, "rank": v.rank} for v in votes
    ]
    tally = rules.tally_votes(vote_dicts, option_rank)
    winner_id, tie = rules.resolve_winner(tally, len(vote_dicts))
    member_count = len(members)
    votes_cast = len({v["user_id"] for v in vote_dicts})
    quorum = rules.quorum_reached(votes_cast, member_count)

    final_plan = dict(group.final_plan) if group.final_plan else None
    if group.status == "collecting_votes" and quorum and winner_id and not tie:
        winner = next((o for o in options if o.id == winner_id), None)
        if winner is not None:
            for option in options:
                option.is_winner = option.id == winner_id
                session.add(option)
            stops = [
                {
                    "experience_id": sid,
                    "name": (s.name if (s := session.get(Experience, sid)) else ""),
                }
                for sid in (winner.stops or [])
            ]
            final_plan = {
                "option_id": winner.id,
                "label": winner.label,
                "stops": stops,
                "total_minutes": winner.total_minutes,
                "total_cost": winner.total_cost,
                "votes": winner.votes,
            }
            group.final_plan = final_plan
            group.status = "locked"
            group.locked_at = utcnow()
            session.add(group)
            session.commit()
            logger.info("Group %s locked with option %s (%d votes)", group_id, winner_id, winner.votes)

    return GroupVoteTally(
        group_id=group_id,
        status=group.status,
        member_count=member_count,
        votes_cast=votes_cast,
        quorum_reached=quorum,
        winner_option_id=winner_id if group.status == "locked" else None,
        tie=tie,
        tally=[
            {
                "option_id": oid,
                "votes": data["votes"],
                "avg_rank": data["avg_rank"],
                "voters": data["voters"],
            }
            for oid, data in sorted(tally.items())
        ],
        final_plan=final_plan,
    )


@router.post(
    "/groups/{group_id}/lock",
    response_model=GroupResponse,
    summary="Lock the plan explicitly (owner only)",
)
def lock_group(
    group_id: int,
    session: Session = Depends(get_session),
    x_user_id: int = Header(..., alias="X-User-Id"),
):
    """Explicit lock for the owner once a winner exists."""
    group = _group_or_404(session, group_id, x_user_id)
    if group.owner_id != x_user_id:
        raise HTTPException(status_code=403, detail="only the owner can lock the plan")
    if group.status != "collecting_votes":
        raise HTTPException(status_code=409, detail=f"group is '{group.status}'")

    options = session.exec(
        select(GroupOption).where(GroupOption.group_id == group_id)
    ).all()
    winner = next((o for o in options if o.votes > 0), None)
    if winner is None:
        raise HTTPException(status_code=409, detail="no votes cast yet")

    for option in options:
        option.is_winner = option.id == winner.id
        session.add(option)
    group.final_plan = {
        "option_id": winner.id,
        "label": winner.label,
        "stops": list(winner.stops or []),
        "total_minutes": winner.total_minutes,
        "total_cost": winner.total_cost,
        "votes": winner.votes,
    }
    group.status = "locked"
    group.locked_at = utcnow()
    session.add(group)
    session.commit()
    session.refresh(group)
    return _group_payload(session, group)
