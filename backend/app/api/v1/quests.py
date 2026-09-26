"""Journey 5: Hidden Gem Quest.

Flow: select quest -> generate feasible plan -> start -> progress -> complete
-> badge/XP.

The quest plan reuses the existing feasibility engine: a quest's stops are
screened against the traveller's time and budget, and infeasible stops are
dropped with a reason, so a quest can never demand an impossible day.
"""

from __future__ import annotations

import logging

from fastapi import APIRouter, Depends, Header, HTTPException, Query, status
from sqlmodel import Session, select

from app.database import get_session
from app.models import Experience
from app.models_prd import Badge, Quest, QuestRun, QuestStop, UserProgress
from app.schemas_prd import (
    QuestProgressResponse,
    QuestResponse,
    QuestStartRequest,
    UserProgressResponse,
)
from app.services import journey_rules as rules
from app.services import recommender
from app.services.weather import fetch_weather
from app.timeutil import utcnow

logger = logging.getLogger(__name__)
router = APIRouter()

LEVEL_NAMES = {
    1: "Tourist",
    2: "Explorer",
    3: "Local",
    4: "Insider",
    5: "Legend",
    6: "Legend",
}


def _quest_payload(session: Session, quest: Quest, plan: dict | None = None) -> QuestResponse:
    stops = session.exec(
        select(QuestStop)
        .where(QuestStop.quest_id == quest.id)
        .order_by(QuestStop.position)
    ).all()
    out_stops = []
    for stop in stops:
        experience = session.get(Experience, stop.experience_id)
        if experience is None:
            continue
        out_stops.append(
            {
                "position": stop.position,
                "hint": stop.hint,
                "experience": {
                    "id": experience.id,
                    "name": experience.name,
                    "category": experience.category,
                    "lat": experience.lat,
                    "lng": experience.lng,
                    "avg_cost": experience.avg_cost,
                    "duration_min": experience.duration_min,
                    "rating": experience.rating,
                    "image_url": experience.image_url,
                },
            }
        )
    return QuestResponse(
        id=quest.id or 0,
        code=quest.code,
        title=quest.title,
        story=quest.story,
        category=quest.category,
        difficulty=quest.difficulty,
        xp_reward=quest.xp_reward,
        estimated_minutes=quest.estimated_minutes,
        estimated_cost=quest.estimated_cost,
        is_active=quest.is_active,
        stops=out_stops,
    )


def _get_progress(session: Session, user_id: int) -> UserProgress:
    progress = session.exec(
        select(UserProgress).where(UserProgress.user_id == user_id)
    ).first()
    if progress is None:
        progress = UserProgress(user_id=user_id, xp=0, level=rules.level_for_xp(0))
        session.add(progress)
        session.commit()
        session.refresh(progress)
    return progress


@router.get("/quests", response_model=list[QuestResponse], summary="Active quests")
def list_quests(
    session: Session = Depends(get_session),
    category: str | None = Query(default=None),
):
    quests = session.exec(select(Quest).order_by(Quest.id)).all()
    out = [
        _quest_payload(session, q)
        for q in quests
        if q.is_active and (not category or q.category == category)
    ]
    return out


@router.get("/quests/{quest_id}", response_model=QuestResponse, summary="Quest detail")
def get_quest(quest_id: int, session: Session = Depends(get_session)):
    quest = session.get(Quest, quest_id)
    if quest is None:
        raise HTTPException(status_code=404, detail="Quest not found")
    return _quest_payload(session, quest)


@router.post(
    "/quests/{quest_id}/start",
    response_model=QuestProgressResponse,
    status_code=status.HTTP_201_CREATED,
    summary="Start a quest with a feasible plan",
)
async def start_quest(
    quest_id: int,
    payload: QuestStartRequest,
    session: Session = Depends(get_session),
    x_user_id: int = Header(..., alias="X-User-Id"),
):
    """Step 1-2: generate a feasible plan for this quest, then start it."""
    from app.api.v1.journey_deps import enforce_trust

    enforce_trust(session, x_user_id, "start_quest")
    quest = session.get(Quest, quest_id)
    if quest is None:
        raise HTTPException(status_code=404, detail="Quest not found")
    if not quest.is_active:
        raise HTTPException(status_code=409, detail="quest is not active")

    progress = _get_progress(session, x_user_id)
    # One run per quest at a time: a live run must be finished or abandoned
    # first, and a completed quest cannot be restarted.
    live_run = session.exec(
        select(QuestRun).where(
            QuestRun.quest_id == quest_id,
            QuestRun.user_id == x_user_id,
            QuestRun.status == "in_progress",
        )
    ).first()
    if live_run is not None:
        raise HTTPException(
            status_code=409,
            detail=f"quest already in progress (run {live_run.id}); finish it first",
        )
    already_done = session.exec(
        select(QuestRun).where(
            QuestRun.quest_id == quest_id,
            QuestRun.user_id == x_user_id,
            QuestRun.status == "completed",
        )
    ).first()
    if already_done is not None:
        raise HTTPException(status_code=409, detail="quest already completed")

    stops = session.exec(
        select(QuestStop).where(QuestStop.quest_id == quest_id).order_by(QuestStop.position)
    ).all()
    experiences = [
        e for e in (session.get(Experience, s.experience_id) for s in stops) if e is not None
    ]
    if not experiences:
        raise HTTPException(status_code=409, detail="quest has no usable stops")

    time_hours = payload.time_hours or max(1.0, quest.estimated_minutes / 60)
    budget = payload.budget_inr if payload.budget_inr is not None else quest.estimated_cost
    area = payload.area or "Bandra, Mumbai"

    # Reuse the feasibility engine so the quest plan obeys real constraints.
    ranked = recommender.recommend(
        experiences,
        location=area,
        time_hours=time_hours,
        budget_inr=budget,
        interests=[quest.category],
        limit=len(experiences),
    )["results"]
    if not ranked:
        raise HTTPException(
            status_code=409,
            detail=(
                f"no quest stop fits {time_hours}h / ₹{budget}; "
                "give the quest more time or budget"
            ),
        )

    kept_ids = [r.experience.id for r in ranked]
    dropped = [
        session.get(Experience, s.experience_id).name
        for s in stops
        if session.get(Experience, s.experience_id) is not None
        and session.get(Experience, s.experience_id).id not in kept_ids  # type: ignore[union-attr]
    ]

    run = QuestRun(
        quest_id=quest_id,
        user_id=x_user_id,
        status="in_progress",
        time_hours=time_hours,
        budget_inr=budget,
        plan={"stops": kept_ids, "dropped": dropped, "total_minutes": sum(r.experience.duration_min for r in ranked)},
        started_at=utcnow(),
    )
    session.add(run)
    progress.quests_started += 1
    session.add(progress)
    session.commit()
    session.refresh(run)

    logger.info(
        "Quest %s started by user %s: kept %d stops, dropped %s",
        quest_id,
        x_user_id,
        len(kept_ids),
        dropped or "none",
    )
    return _run_payload(session, run, quest)


def _run_payload(session: Session, run, quest: Quest) -> QuestProgressResponse:
    plan = dict(run.plan or {})
    stops = plan.get("stops", [])
    total = len(stops)
    done = len(run.completed_stops or [])
    current = None
    if done < total:
        experience = session.get(Experience, stops[done])
        if experience is not None:
            current = {
                "position": done + 1,
                "experience_id": experience.id,
                "name": experience.name,
                "lat": experience.lat,
                "lng": experience.lng,
                "duration_min": experience.duration_min,
            }
    percent = int(round((done / total) * 100)) if total else 0
    allowed = rules.QUEST_TRANSITIONS.get(run.status, set())
    return QuestProgressResponse(
        run_id=run.id or 0,
        quest_id=run.quest_id,
        quest_code=quest.code,
        quest_title=quest.title,
        status=run.status,
        stops_total=total,
        stops_completed=done,
        progress_percent=percent,
        current_stop=current,
        started_at=run.started_at,
        completed_at=run.completed_at,
        xp_awarded=run.xp_awarded,
        badges_earned=run.badges_earned or [],
        allowed_transitions=sorted(allowed),
    )


@router.get(
    "/quests/runs/{run_id}",
    response_model=QuestProgressResponse,
    summary="Quest run / progress",
)
def get_run(
    run_id: int,
    session: Session = Depends(get_session),
    x_user_id: int = Header(..., alias="X-User-Id"),
):
    run = session.get(QuestRun, run_id)
    if run is None or run.user_id != x_user_id:
        raise HTTPException(status_code=404, detail="Quest run not found")
    quest = session.get(Quest, run.quest_id)
    return _run_payload(session, run, quest)


@router.post(
    "/quests/runs/{run_id}/stops/{position}",
    response_model=QuestProgressResponse,
    summary="Mark a quest stop visited (progress)",
)
def visit_stop(
    run_id: int,
    position: int,
    session: Session = Depends(get_session),
    x_user_id: int = Header(..., alias="X-User-Id"),
):
    """Step 3: record progress. Stops must be visited in order."""
    run = session.get(QuestRun, run_id)
    if run is None or run.user_id != x_user_id:
        raise HTTPException(status_code=404, detail="Quest run not found")
    if run.status != "in_progress":
        raise HTTPException(
            status_code=409, detail=f"quest run is '{run.status}', not in progress"
        )
    stops = list((run.plan or {}).get("stops", []))
    expected = len(run.completed_stops or []) + 1
    if position != expected:
        raise HTTPException(
            status_code=409, detail=f"visit stops in order: expected stop {expected}"
        )
    if position > len(stops):
        raise HTTPException(status_code=400, detail="position beyond the plan")

    completed = list(run.completed_stops or [])
    completed.append(position)
    run.completed_stops = completed
    session.add(run)
    session.commit()
    session.refresh(run)
    quest = session.get(Quest, run.quest_id)
    return _run_payload(session, run, quest)


@router.post(
    "/quests/runs/{run_id}/complete",
    response_model=QuestProgressResponse,
    summary="Complete a quest and award XP + badges",
)
async def complete_quest(
    run_id: int,
    session: Session = Depends(get_session),
    x_user_id: int = Header(..., alias="X-User-Id"),
):
    """Step 4: completion -> badge + XP."""
    run = session.get(QuestRun, run_id)
    if run is None or run.user_id != x_user_id:
        raise HTTPException(status_code=404, detail="Quest run not found")
    ok, reason = rules.can_transition_quest(run.status, "completed")
    if not ok:
        raise HTTPException(status_code=409, detail=reason)
    stops = list((run.plan or {}).get("stops", []))
    if len(run.completed_stops or []) < len(stops):
        raise HTTPException(
            status_code=409,
            detail=(
                f"finish all stops first: {len(run.completed_stops or [])}/{len(stops)}"
            ),
        )

    quest = session.get(Quest, run.quest_id)
    progress = _get_progress(session, x_user_id)
    weather = await fetch_weather()

    prior_runs = session.exec(
        select(QuestRun).where(
            QuestRun.user_id == x_user_id, QuestRun.status == "completed"
        )
    ).all()
    completed_codes: list[str] = []
    for prior in [run, *prior_runs]:
        prior_quest = session.get(Quest, prior.quest_id)
        if prior_quest is not None:
            completed_codes.append(prior_quest.code)

    earned = rules.evaluate_badges(
        completed_codes=completed_codes,
        weather=weather,
        categories=[quest.category],
    )
    catalogue = {b.code: b for b in session.exec(select(Badge)).all()}
    new_badges = [c for c in earned if c not in (progress.badges or [])]

    badge_rows = []
    xp_total = quest.xp_reward
    for code in new_badges:
        if code not in catalogue:
            catalogue[code] = _ensure_badge(session, code)
        badge = catalogue[code]
        xp_total += badge.xp_bonus
        badge_rows.append({"code": code, "name": badge.name, "description": badge.description})

    progress.badges = sorted(set((progress.badges or []) + earned))
    progress.xp += xp_total
    progress.level = rules.level_for_xp(progress.xp)
    progress.quests_completed += 1
    session.add(progress)

    run.status = "completed"
    run.completed_at = utcnow()
    run.xp_awarded = xp_total
    run.badges_earned = badge_rows
    session.add(run)
    session.commit()
    session.refresh(run)

    logger.info(
        "Quest run %s completed: +%s xp, badges=%s", run_id, xp_total, [b["code"] for b in badge_rows]
    )
    return _run_payload(session, run, quest)


@router.get(
    "/progress", response_model=UserProgressResponse, summary="My XP, level and badges"
)
def my_progress(
    session: Session = Depends(get_session),
    x_user_id: int = Header(..., alias="X-User-Id"),
):
    progress = _get_progress(session, x_user_id)
    catalogue = {b.code: b for b in session.exec(select(Badge)).all()}
    badges = [
        {
            "code": code,
            "name": catalogue[code].name if code in catalogue else code,
            "description": catalogue[code].description if code in catalogue else "",
            "xp_bonus": catalogue[code].xp_bonus if code in catalogue else 0,
        }
        for code in (progress.badges or [])
    ]
    return UserProgressResponse(
        user_id=x_user_id,
        xp=progress.xp,
        level=progress.level,
        level_name=LEVEL_NAMES.get(progress.level, f"Level {progress.level}"),
        badges=badges,
        quests_started=progress.quests_started,
        quests_completed=progress.quests_completed,
    )


def _ensure_badge(session: Session, code: str) -> Badge:
    rule = rules.BADGE_RULES.get(code)
    badge = Badge(
        code=code,
        name=rule["name"] if rule else code,
        description=rule["description"] if rule else "",
        xp_bonus=rule["xp"] if rule else 0,
    )
    session.add(badge)
    session.commit()
    session.refresh(badge)
    return badge
