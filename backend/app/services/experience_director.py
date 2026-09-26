"""AI Experience Director — the live companion (PRD 4.10).

Extends the planning-stage Companion (PRD 4.7) into a session that spans the
whole outing:

* **start**   — open a session for one experience or a whole itinerary and make
  sure a set of reusable tips exists.
* **check-in** — hand back the next location-aware tip as the user moves.
* **adapt**   — react to a context change (rain, crowd) with a concrete
  alternative.
* **end**     — summarise the outing (time, cost, distance, hidden gems) and
  log every stop into the Experience Wallet.

All LLM work goes through ``companion``, which falls back deterministically, so
the director works with no model running.
"""

from __future__ import annotations

import logging
from datetime import datetime, timezone
from typing import Any

from sqlmodel import Session, select

from app.models import AITip, Experience, ExperienceSession, Itinerary, User
from app.services import companion, graphs, reranker, wallet
from app.services.recommender import haversine_km
from app.services.weather import fetch_weather

logger = logging.getLogger(__name__)

TIP_CATEGORIES = ("history", "photo", "food", "safety")
HIDDEN_GEM_THRESHOLD = 0.7


# ---------------------------------------------------------------------------
# Session helpers
# ---------------------------------------------------------------------------


def session_experiences(session: Session, live: ExperienceSession) -> list[Experience]:
    """Resolve a session's stops (or its single experience) in order."""
    ids: list[int] = []
    for stop in (live.route_json or {}).get("stops") or []:
        if isinstance(stop, dict) and stop.get("experience_id"):
            ids.append(int(stop["experience_id"]))
        elif isinstance(stop, int):
            ids.append(stop)
    if not ids and live.experience_id:
        ids = [live.experience_id]
    if not ids:
        return []
    rows = session.exec(select(Experience).where(Experience.id.in_(ids))).all()
    by_id = {e.id: e for e in rows}
    return [by_id[i] for i in ids if i in by_id]


def build_summary(session: Session, live: ExperienceSession) -> dict[str, Any]:
    """Post-experience summary: stops, time, cost, distance, hidden gems."""
    experiences = session_experiences(session, live)
    cost = sum(e.avg_cost for e in experiences)
    duration = sum(e.duration_min for e in experiences)
    distance = 0.0
    for earlier, later in zip(experiences, experiences[1:]):
        distance += haversine_km(earlier.lat, earlier.lng, later.lat, later.lng)
    hidden = sum(
        1 for e in experiences if (e.local_gem_score or 0.0) >= HIDDEN_GEM_THRESHOLD
    )
    highlights = [e.name for e in experiences]

    if not experiences:
        insight = "No stops were recorded for this outing."
    elif hidden:
        insight = f"You found {hidden} hidden gem{'s' if hidden != 1 else ''} this time."
    elif distance > 3:
        insight = f"You covered about {distance:.1f} km — a proper wander."
    else:
        insight = "A compact outing — nice and easy going."

    return {
        "total_stops": len(experiences),
        "total_cost": cost,
        "duration_min": duration,
        "distance_km": round(distance, 2),
        "hidden_gems": hidden,
        "highlights": highlights,
        "insight": insight,
        "generated_at": datetime.now(timezone.utc).isoformat(),
    }


async def ensure_tips(session: Session, live: ExperienceSession) -> int:
    """Generate and store reusable tips for any stop that has none yet."""
    created = 0
    for experience in session_experiences(session, live):
        existing = session.exec(
            select(AITip).where(AITip.experience_id == experience.id)
        ).first()
        if existing is not None:
            continue
        tips = await companion.compose_guide_tips(
            experience.name,
            category=experience.category,
            description=experience.description or "",
            language=live.language,
        )
        for index, text in enumerate(tips[:4]):
            session.add(
                AITip(
                    experience_id=experience.id or 0,
                    category=TIP_CATEGORIES[index % len(TIP_CATEGORIES)],
                    message_text=str(text)[:1000],
                    language=live.language,
                    location_trigger_json={},
                )
            )
            created += 1
        session.commit()
    return created


async def start_session(
    session: Session,
    user: User,
    *,
    experience_id: int | None = None,
    itinerary_id: int | None = None,
    language: str = "en",
) -> ExperienceSession:
    """Open a live session for an experience and/or itinerary."""
    if experience_id is None and itinerary_id is None:
        raise ValueError("experience_id or itinerary_id is required")
    if experience_id is not None and session.get(Experience, experience_id) is None:
        raise ValueError("experience not found")

    route: dict[str, Any] = {}
    if itinerary_id is not None:
        itinerary = session.get(Itinerary, itinerary_id)
        if itinerary is None:
            raise ValueError("itinerary not found")
        route = {
            "stops": [
                {"experience_id": stop.experience_id, "sequence": stop.sequence}
                for stop in sorted(itinerary.stops, key=lambda s: s.sequence)
            ]
        }

    live = ExperienceSession(
        user_id=user.id or 0,
        experience_id=experience_id,
        itinerary_id=itinerary_id,
        status="active",
        language=language,
        start_time=datetime.now(timezone.utc),
        route_json=route,
        live_context_json={"shown_tip_ids": []},
    )
    session.add(live)
    session.commit()
    session.refresh(live)
    await ensure_tips(session, live)
    return live


def get_owned(session: Session, session_id: int, user: User) -> ExperienceSession:
    live = session.get(ExperienceSession, session_id)
    if live is None or live.user_id != user.id:
        raise LookupError("session not found")
    return live


# ---------------------------------------------------------------------------
# During the experience
# ---------------------------------------------------------------------------


def next_tip(
    session: Session, live: ExperienceSession, *, lat: float | None = None, lng: float | None = None
) -> dict[str, Any]:
    """Return the next unshown tip for this session, marking it as shown."""
    experiences = session_experiences(session, live)
    exp_ids = [e.id for e in experiences if e.id is not None]
    if not exp_ids:
        return {"tip": None, "remaining": 0, "message": "No stops in this session."}
    by_id = {e.id: e for e in experiences}

    shown = set((live.live_context_json or {}).get("shown_tip_ids") or [])
    tips = [
        tip
        for tip in session.exec(
            select(AITip).where(AITip.experience_id.in_(exp_ids)).order_by(AITip.id)
        ).all()
        if tip.id not in shown
    ]
    if not tips:
        return {"tip": None, "remaining": 0, "message": "You're all caught up — enjoy!"}

    # Prefer a tip whose trigger is near the user, else the next in order.
    def _distance(tip: AITip) -> float:
        trigger = tip.location_trigger_json or {}
        if lat is None or lng is None or trigger.get("lat") is None:
            return float("inf")
        return haversine_km(lat, lng, float(trigger["lat"]), float(trigger["lng"]))

    located = [tip for tip in tips if _distance(tip) < 0.25]
    chosen = min(located, key=_distance) if located else tips[0]

    shown.add(chosen.id)
    live.live_context_json = {**(live.live_context_json or {}), "shown_tip_ids": sorted(shown)}
    session.add(live)
    session.commit()
    session.refresh(live)

    experience = by_id.get(chosen.experience_id)
    return {
        "tip": {
            "id": chosen.id,
            "category": chosen.category,
            "message": chosen.message_text,
            "language": chosen.language,
        },
        "remaining": len(tips) - 1,
        "message": f"At {experience.name}" if experience else "",
    }


async def adapt(
    session: Session,
    live: ExperienceSession,
    *,
    lat: float | None = None,
    lng: float | None = None,
    weather: dict[str, Any] | None = None,
) -> dict[str, Any]:
    """Suggest a concrete alternative when the context changes mid-outing."""
    experiences = session_experiences(session, live)
    current = experiences[0] if experiences else None
    anchor_lat = lat if lat is not None else (current.lat if current else None)
    anchor_lng = lng if lng is not None else (current.lng if current else None)

    if weather is None:
        try:
            weather = await fetch_weather(
                anchor_lat if anchor_lat is not None else 19.0760,
                anchor_lng if anchor_lng is not None else 72.8777,
            )
        except Exception as exc:  # pragma: no cover - defensive
            logger.warning("Director weather lookup failed: %s", exc)
            weather = {}

    # Nothing to adapt to.
    if not weather or not weather.get("available") or not weather.get("is_rainy"):
        return {
            "adaptation_needed": False,
            "message": "Conditions look fine — carry on with the plan.",
            "suggestion": None,
            "travel_time_min": 0,
        }
    if current is not None and not reranker.outdoorish(current):
        return {
            "adaptation_needed": False,
            "message": "Rain is around, but this stop is indoors — you're covered.",
            "suggestion": None,
            "travel_time_min": 0,
        }

    user = session.get(User, live.user_id)
    pool = graphs.taste_aware_recommend(
        session,
        user,
        lat=anchor_lat,
        lng=anchor_lng,
        weather=weather,
        limit=12,
    )
    alternative = next(
        (r for r in pool if not reranker.outdoorish(r.experience)), None
    )
    if alternative is None:
        return {
            "adaptation_needed": True,
            "message": "Rain is starting — no close indoor option found, so grab a café nearby.",
            "suggestion": None,
            "travel_time_min": 0,
        }
    return {
        "adaptation_needed": True,
        "message": (
            f"Rain is starting — {alternative.experience.name} is indoors and "
            f"about {alternative.travel_time_min} min away."
        ),
        "suggestion": alternative.experience,
        "travel_time_min": alternative.travel_time_min,
        "why": alternative.why,
    }


def end_session(
    session: Session,
    live: ExperienceSession,
    *,
    rating: float | None = None,
    notes: str | None = None,
) -> dict[str, Any]:
    """Close the session, summarise it, and log every stop into the wallet."""
    summary = build_summary(session, live)
    live.summary_json = summary
    live.status = "completed"
    live.end_time = datetime.now(timezone.utc)
    session.add(live)
    session.commit()
    session.refresh(live)

    user = session.get(User, live.user_id)
    new_badges: list[dict[str, Any]] = []
    if user is not None:
        for experience in session_experiences(session, live):
            result = wallet.log_experience(
                session,
                user,
                experience,
                rating=rating,
                notes=notes,
                context={"city": "Mumbai", "session_id": live.id},
            )
            new_badges.extend(result["new_badges"])
    return {"session": live, "summary": summary, "new_badges": new_badges}
