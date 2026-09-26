"""A-to-Z day planner (PRD 4.8 + itinerary section).

Builds a full, time-aware day plan from a user's constraints:

    taste + constraints
      -> taste-aware candidate pool (reranker)
      -> greedy nearest-neighbour walk that respects opening hours, travel time,
         budget and meal windows
      -> ordered stops with concrete start/end times

Also provides route optimisation (for hand-edited plans), text parsing for
imports, and a tiny ICS writer so a plan can leave the app.

Pure Python and deterministic: no network calls, so it is cheap to run on every
request and straightforward to test.
"""

from __future__ import annotations

import logging
import re
from dataclasses import dataclass, field
from datetime import date, datetime, timedelta, timezone
from typing import Any

from sqlmodel import Session

from app.models import Experience, ItineraryStop, User
from app.services import graphs, recommender, taste
from app.services.recommender import (
    estimate_travel_time_min,
    haversine_km,
    is_open_at,
    parse_hhmm,
    resolve_location,
)

logger = logging.getLogger(__name__)

DAY_MINUTES = 24 * 60
DEFAULT_START_MIN = 10 * 60  # 10:00

#: Candidate pool pulled from the reranker before the greedy walk.
POOL_SIZE = 80

#: Greedy utility weights (applied on top of the reranker's 0..1 score).
TRAVEL_PENALTY_PER_HOUR = 0.15
INTEREST_BONUS = 0.15
MEAL_BONUS = 0.30

#: Eating windows, as (start_min, end_min).
MEAL_WINDOWS: tuple[tuple[int, int], ...] = ((12 * 60, 14 * 60 + 30), (19 * 60, 21 * 60 + 30))
FOOD_CATEGORIES = {"food", "nightlife"}


# ---------------------------------------------------------------------------
# Result types
# ---------------------------------------------------------------------------


@dataclass
class PlannedStop:
    experience: Experience
    sequence: int
    start_min: int
    end_min: int
    travel_min: int
    distance_km: float
    why: list[str] = field(default_factory=list)

    @property
    def start_time(self) -> str:
        return fmt_hhmm(self.start_min)

    @property
    def end_time(self) -> str:
        return fmt_hhmm(self.end_min)


@dataclass
class DayPlan:
    stops: list[PlannedStop]
    total_duration_min: int
    total_cost: int
    total_travel_min: int
    notes: list[str] = field(default_factory=list)


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------


def fmt_hhmm(minutes: int) -> str:
    """Minutes since midnight -> 'HH:MM' (wraps past midnight)."""
    minutes %= DAY_MINUTES
    return f"{minutes // 60:02d}:{minutes % 60:02d}"


def _in_meal_window(clock: int) -> bool:
    minute = clock % DAY_MINUTES
    return any(lo <= minute <= hi for lo, hi in MEAL_WINDOWS)


def _tag_set(experience: Experience) -> set[str]:
    return {taste.normalize_tag(t) for t in (experience.tags or [])}


def _interest_bonus(experience: Experience, interests: set[str]) -> float:
    if not interests:
        return 0.0
    if _tag_set(experience) & interests:
        return INTEREST_BONUS
    # Category names count as interests too ("food", "nightlife", "nature"...).
    if experience.category and experience.category.lower() in interests:
        return INTEREST_BONUS
    return 0.0


# ---------------------------------------------------------------------------
# Generation
# ---------------------------------------------------------------------------


def plan_day(
    session: Session,
    user: User | None,
    *,
    start_location: str | None = None,
    start_time: str = "10:00",
    duration_hours: float = 8.0,
    budget_inr: int | None = None,
    travel_mode: str = "WALK",
    interests: list[str] | None = None,
    weather: dict[str, Any] | None = None,
    include_food: bool = True,
    max_stops: int = 5,
    semantic_query: str | None = None,
    candidate_ids: list[int] | None = None,
) -> DayPlan:
    """Produce an ordered, time-aware plan that fits the user's window.

    Returns at least an empty plan (with a note) when nothing fits, rather than
    raising, so the caller can always persist or message the user.
    """
    notes: list[str] = []
    origin = resolve_location(start_location) if start_location else None
    start_min = parse_hhmm(start_time)
    if start_min is None:
        start_min = DEFAULT_START_MIN
        notes.append("We assumed a 10:00 start.")

    duration_hours = max(1.0, min(16.0, float(duration_hours or 8.0)))
    end_min = start_min + int(duration_hours * 60)
    max_stops = max(1, min(10, int(max_stops or 5)))
    interest_set = {taste.normalize_tag(i) for i in (interests or []) if i}

    # 1. Candidate pool, already taste + weather re-ranked.
    pool = graphs.taste_aware_recommend(
        session,
        user,
        lat=origin[0] if origin else None,
        lng=origin[1] if origin else None,
        time_hours=None,  # no per-stop hard drop; the walk enforces the window
        budget_inr=budget_inr,
        start_time=start_time,
        weather=weather or {},
        limit=POOL_SIZE,
        candidate_ids=candidate_ids,
    )
    ranked_by_id: dict[int, Any] = {r.experience.id: r for r in pool if r.experience.id}
    remaining = [r.experience for r in pool if r.experience.id]

    if not remaining:
        notes.append("No experiences matched those constraints — try a wider budget or area.")
        return DayPlan([], 0, 0, 0, notes)

    # 2. Greedy nearest-neighbour walk.
    stops: list[PlannedStop] = []
    cursor = origin
    clock = start_min
    budget_left = budget_inr
    total_travel = 0
    last_food_at: int | None = None

    while remaining and len(stops) < max_stops and clock < end_min:
        best: tuple[float, Experience, int, float] | None = None
        for exp in remaining:
            travel = 0
            distance = 0.0
            if cursor is not None:
                distance = haversine_km(cursor[0], cursor[1], exp.lat, exp.lng)
                travel = estimate_travel_time_min(distance)
            elif stops:
                prev = stops[-1].experience
                distance = haversine_km(prev.lat, prev.lng, exp.lat, exp.lng)
                travel = estimate_travel_time_min(distance)

            arrival = clock + travel
            finish = arrival + exp.duration_min
            if finish > end_min:
                continue  # would overrun the day
            if not is_open_at(exp, arrival, exp.duration_min):
                continue
            if budget_left is not None and exp.avg_cost > budget_left:
                continue

            base = ranked_by_id.get(exp.id).score if exp.id in ranked_by_id else 0.5
            utility = base - (travel / 60.0) * TRAVEL_PENALTY_PER_HOUR
            utility += _interest_bonus(exp, interest_set)
            if (
                include_food
                and _in_meal_window(arrival)
                and (last_food_at is None or arrival - last_food_at > 120)
                and exp.category.lower() in FOOD_CATEGORIES
            ):
                utility += MEAL_BONUS
            # Slight preference for an actual meal venue when it is mealtime.
            if (
                include_food
                and _in_meal_window(arrival)
                and (last_food_at is None or arrival - last_food_at > 120)
                and exp.category.lower() not in FOOD_CATEGORIES
            ):
                utility -= 0.05

            if best is None or utility > best[0]:
                best = (utility, exp, travel, distance)

        if best is None:
            break

        _, exp, travel, distance = best
        arrival = clock + travel
        finish = arrival + exp.duration_min
        ranked = ranked_by_id.get(exp.id)
        why = list(getattr(ranked, "why", []) or [])
        if exp.category.lower() in FOOD_CATEGORIES and _in_meal_window(arrival):
            why.append("Good spot for a meal break")
        if _interest_bonus(exp, interest_set):
            why.append("Matches your interests")
        why.append(f"Arrive ~{fmt_hhmm(arrival)}, open until {exp.close_time}")

        stops.append(
            PlannedStop(
                experience=exp,
                sequence=len(stops),
                start_min=arrival,
                end_min=finish,
                travel_min=travel,
                distance_km=round(distance, 2),
                why=why,
            )
        )
        total_travel += travel
        clock = finish
        cursor = (exp.lat, exp.lng)
        if exp.category.lower() in FOOD_CATEGORIES:
            last_food_at = arrival
        budget_left = None if budget_left is None else budget_left - exp.avg_cost
        remaining = [e for e in remaining if e.id != exp.id]

    if not stops:
        notes.append(
            "Nothing fit inside that time window once travel was counted. "
            "Try more hours or a closer start point."
        )
    elif len(stops) < max_stops and clock >= end_min:
        notes.append("The day is full — I stopped here to keep travel time realistic.")

    total_duration = (stops[-1].end_min - stops[0].start_min) if stops else 0
    total_cost = sum(s.experience.avg_cost for s in stops)
    if budget_inr is not None and total_cost > budget_inr:
        notes.append("Over budget — remove a stop or raise the budget.")
    return DayPlan(stops, total_duration, total_cost, total_travel, notes)


# ---------------------------------------------------------------------------
# Optimisation (for hand-edited plans)
# ---------------------------------------------------------------------------


def optimize_order(
    experiences: list[Experience],
    *,
    origin: tuple[float, float] | None = None,
    start_time: str = "10:00",
) -> list[PlannedStop]:
    """Reorder stops by nearest-neighbour to cut total travel time.

    Keeps the first stop fixed when no origin is supplied (the user chose where
    to begin); otherwise starts from ``origin``.
    """
    if not experiences:
        return []

    remaining = list(experiences)
    ordered: list[Experience] = []
    if origin is None:
        ordered.append(remaining.pop(0))
        cursor = (ordered[0].lat, ordered[0].lng)
    else:
        cursor = origin

    while remaining:
        nearest = min(
            remaining,
            key=lambda e: haversine_km(cursor[0], cursor[1], e.lat, e.lng),
        )
        ordered.append(nearest)
        remaining.remove(nearest)
        cursor = (nearest.lat, nearest.lng)

    # Recompute times along the new order.
    clock = parse_hhmm(start_time) or DEFAULT_START_MIN
    stops: list[PlannedStop] = []
    cursor = origin
    for sequence, exp in enumerate(ordered):
        travel = 0
        distance = 0.0
        if cursor is not None:
            distance = haversine_km(cursor[0], cursor[1], exp.lat, exp.lng)
            travel = estimate_travel_time_min(distance)
        start = clock + travel
        stops.append(
            PlannedStop(
                experience=exp,
                sequence=sequence,
                start_min=start,
                end_min=start + exp.duration_min,
                travel_min=travel,
                distance_km=round(distance, 2),
            )
        )
        clock = start + exp.duration_min
        cursor = (exp.lat, exp.lng)
    return stops


def apply_plan_to_itinerary(itinerary, stops: list[PlannedStop]) -> None:
    """Replace an itinerary's stops with a generated/optimised plan."""
    itinerary.stops.clear()
    for stop in stops:
        itinerary.stops.append(
            ItineraryStop(
                experience_id=stop.experience.id,
                sequence=stop.sequence,
                start_time=stop.start_time,
                end_time=stop.end_time,
                travel_time_min=stop.travel_min,
            )
        )
    itinerary.total_duration_min = (
        stops[-1].end_min - stops[0].start_min if stops else 0
    )
    itinerary.total_cost = sum(s.experience.avg_cost for s in stops)


# ---------------------------------------------------------------------------
# Import parsing
# ---------------------------------------------------------------------------


def parse_itinerary_text(text: str) -> list[dict[str, str]]:
    """Parse a loose, human-written plan into ``{name, start_time}`` rows.

    Understands lines like::

        10:00 Gateway of India
        - 12:30pm Leopold Cafe
        2 PM Marine Drive
        Elephanta Caves

    Order is preserved; a missing time is left blank so the caller can chain it.
    """
    rows: list[dict[str, str]] = []
    # Leading time must be a real clock time: "10:00", "10.30", "2 PM", "14:30".
    # A bare "10" is ignored so lines like "10 places to eat" are not mangled.
    time_pattern = re.compile(
        r"^(\d{1,2}[:.]\d{2}\s*(?:am|pm)?|\d{1,2}\s*(?:am|pm))\s*[-–—:]?\s+(.+)$",
        flags=re.IGNORECASE,
    )
    for raw_line in (text or "").splitlines():
        line = raw_line.strip().lstrip("-*•").strip()
        if not line:
            continue
        name = line
        start_time = ""
        match = time_pattern.match(line)
        if match:
            candidate_time = match.group(1).strip().replace(".", ":")
            rest = match.group(2).strip()
            if parse_hhmm(candidate_time) is not None:
                start_time = candidate_time
                name = rest
        if name:
            rows.append({"name": name, "start_time": start_time})
    return rows


def resolve_import_stops(
    session: Session, rows: list[dict[str, Any]]
) -> tuple[list[tuple[Experience, str | None]], list[str]]:
    """Match imported rows to experiences.

    Each row may carry ``experience_id`` (exact) or ``name`` (fuzzy matched
    against the catalogue). Unmatched names are returned so the caller can tell
    the user what was skipped.
    """
    import difflib

    from sqlmodel import select

    catalogue = list(session.exec(select(Experience)).all())
    by_id = {e.id: e for e in catalogue}
    by_name = {e.name.lower(): e for e in catalogue}
    resolved: list[tuple[Experience, str | None]] = []
    unresolved: list[str] = []

    for row in rows:
        exp_id = row.get("experience_id")
        name = (row.get("name") or "").strip()
        start_time = row.get("start_time") or None
        if exp_id is not None and exp_id in by_id:
            resolved.append((by_id[exp_id], start_time))
            continue
        if not name:
            continue
        if name.lower() in by_name:
            resolved.append((by_name[name.lower()], start_time))
            continue
        close = difflib.get_close_matches(name.lower(), list(by_name), n=1, cutoff=0.72)
        if close:
            resolved.append((by_name[close[0]], start_time))
        else:
            unresolved.append(name)
    return resolved, unresolved


# ---------------------------------------------------------------------------
# Export
# ---------------------------------------------------------------------------


def itinerary_to_ics(
    itinerary,
    stops: list[tuple[Experience, str, str]],
    *,
    on_date: date | None = None,
) -> str:
    """Render stops as an iCalendar document (one VEVENT per stop).

    ``stops`` is a list of ``(experience, start_time, end_time)``.
    """
    on_date = on_date or date.today()
    now = datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%SZ")

    def _stamp(hhmm: str) -> str:
        parsed = parse_hhmm(hhmm)
        if parsed is None:
            parsed = DEFAULT_START_MIN
        start = datetime(on_date.year, on_date.month, on_date.day) + timedelta(minutes=parsed)
        return start.strftime("%Y%m%dT%H%M%S")

    lines = [
        "BEGIN:VCALENDAR",
        "VERSION:2.0",
        "PRODID:-//LocalIQ//Itinerary//EN",
        "CALSCALE:GREGORIAN",
    ]
    for exp, start_time, end_time in stops:
        end = _stamp(end_time) if end_time else _stamp(start_time)
        lines += [
            "BEGIN:VEVENT",
            f"UID:localiq-{itinerary.id}-{exp.id}@localiq",
            f"DTSTAMP:{now}",
            f"DTSTART:{_stamp(start_time)}",
            f"DTEND:{end}",
            f"SUMMARY:{_ics_escape(exp.name)}",
            f"LOCATION:{exp.lat:.5f},{exp.lng:.5f}",
            f"DESCRIPTION:{_ics_escape((exp.description or '')[:400])}",
            "END:VEVENT",
        ]
    lines.append("END:VCALENDAR")
    return "\r\n".join(lines) + "\r\n"


def _ics_escape(text: str) -> str:
    return (
        (text or "")
        .replace("\\", "\\\\")
        .replace(";", "\\;")
        .replace(",", "\\,")
        .replace("\n", "\\n")
    )
