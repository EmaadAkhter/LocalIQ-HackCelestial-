"""Decision logic for the PRD v2 journeys.

Pure functions, no database access, so every rule is unit-testable on its own
and the routers stay thin. All gating that matters (trust tier, state machine
transitions, cost maths) lives here and is enforced server-side.

Phase 1 scope: verification is simulated, matching is deterministic scoring,
payments are a status only.
"""

from __future__ import annotations

from dataclasses import dataclass, field

from app.timeutil import utcnow

# ---------------------------------------------------------------------------
# Trust / verification tiers (simulated)
# ---------------------------------------------------------------------------

#: Ordered so a higher index means more trust.
TRUST_TIERS: tuple[str, ...] = ("unverified", "basic", "standard", "trusted")

#: Minimum tier required for each stranger-facing action.
TRUST_GATES: dict[str, str] = {
    "create_meetup_request": "standard",
    "be_matched": "standard",
    "join_group": "basic",
    "create_group": "basic",
    "book_guide": "basic",
    "leave_review": "standard",
    "start_quest": "basic",
    "promote_gem": "standard",
}


def tier_rank(tier: str) -> int:
    try:
        return TRUST_TIERS.index(tier)
    except ValueError:
        return 0


def meets_trust(user_tier: str, action: str) -> bool:
    """True when ``user_tier`` satisfies the gate required by ``action``."""
    required = TRUST_GATES.get(action)
    if required is None:
        return False
    return tier_rank(user_tier) >= tier_rank(required)


def trust_gate_detail(user_tier: str, action: str) -> dict:
    required = TRUST_GATES.get(action, "unverified")
    return {
        "action": action,
        "required_tier": required,
        "current_tier": user_tier,
        "allowed": meets_trust(user_tier, action),
    }


# ---------------------------------------------------------------------------
# Solo explorer
# ---------------------------------------------------------------------------

#: Venue settings that make an experience work for one traveller.
SOLO_FRIENDLY_TAGS = {
    "solo-friendly", "counter-seating", "daylight", "open-plan", "guided-tour",
    "walking", "sunrise", "sunset", "open-space", "workshop",
}


def solo_friendly_score(place) -> dict:
    """Explainable solo-friendliness for a place.

    Purely local and deterministic: it reuses the curated metadata rather than
    inventing a new ranking, so the solo view stays consistent with
    ``/api/v1/recommend``.
    """
    tags = {t.lower() for t in (getattr(place, "tags", None) or [])}
    flags = {f.lower() for f in (getattr(place, "accessibility_flags", None) or [])}
    reasons: list[str] = []
    score = 50

    solo_hits = tags & SOLO_FRIENDLY_TAGS
    if solo_hits:
        score += min(25, 8 * len(solo_hits))
        reasons.append(f"Solo-friendly: {', '.join(sorted(solo_hits))}")
    else:
        reasons.append("No explicit solo-friendly marker")

    setting = (getattr(place, "indoor_outdoor", "") or "").lower()
    if setting == "outdoor":
        score += 10
        reasons.append("Open-air setting is comfortable alone")
    elif setting == "mixed":
        score += 5
        reasons.append("Mixed indoor/outdoor space")

    if "wheelchair-accessible" in flags or "step-free" in flags:
        score += 8
        reasons.append("Step-free, so navigating solo is easy")

    duration = int(getattr(place, "duration_min", 0) or 0)
    if 30 <= duration <= 150:
        score += 7
        reasons.append("Visit length suits a solo trip")

    # Very high cost is harder to justify alone; very low cost is a plus.
    cost = int(getattr(place, "avg_cost", 0) or 0)
    if cost == 0:
        score += 5
        reasons.append("Free to visit")
    elif cost <= 300:
        score += 5
        reasons.append("Low cost for one person")

    return {
        "score": max(0, min(100, score)),
        "reasons": reasons,
        "solo_friendly": score >= 65,
    }


def solo_summary(params, recommendations: list, companion: bool) -> dict:
    """Render-ready state for the solo journey."""
    solo = [r for r in recommendations if r.get("solo", {}).get("solo_friendly")]
    return {
        "mode": "solo",
        "location": params.get("location"),
        "time_hours": params.get("time_hours"),
        "budget_inr": params.get("budget_inr"),
        "interests": params.get("interests", []),
        "companion_enabled": companion,
        "companion_state": (
            "active_mock" if companion else "off"
        ),
        "companion_personality": "chill_friend" if companion else None,
        "total_recommendations": len(recommendations),
        "solo_friendly_count": len(solo),
        "top_solo_pick": solo[0] if solo else (recommendations[0] if recommendations else None),
    }


# ---------------------------------------------------------------------------
# Meetup compatibility
# ---------------------------------------------------------------------------


def _budget_closeness(a: int, b: int) -> float:
    """0..1, 1 when identical budgets, decaying as they diverge."""
    if a <= 0 and b <= 0:
        return 1.0
    high = max(a, b, 1)
    low = max(0, min(a, b))
    return max(0.0, 1.0 - (high - low) / high)


def _overlap(a: list[str], b: list[str]) -> list[str]:
    sa = {x.lower() for x in (a or [])}
    sb = {x.lower() for x in (b or [])}
    return sorted(sa & sb)


def compatibility_score(
    *,
    request_interests: list[str],
    request_budget: int,
    request_duration: int,
    request_start: str,
    member_interests: list[str],
    member_budget: int,
    member_duration: int,
    member_start: str,
    member_tier: str = "standard",
    blocked_pairs: set[tuple[int, int]] | None = None,
) -> dict:
    """Deterministic 0-100 compatibility between a request and a candidate.

    Weights: shared interests 45, budget closeness 20, schedule alignment 20,
    trust tier 15. The interest term is the headline signal the product
    promises ("you 3 share: food + photography + hidden gems").
    """
    shared = _overlap(request_interests, member_interests)
    if request_interests or member_interests:
        interest_score = 45.0 * min(1.0, len(shared) / 2.0)
    else:
        interest_score = 22.5  # neutral when neither stated preferences

    budget_score = 20.0 * _budget_closeness(request_budget, member_budget)

    same_day = request_start[:2] == member_start[:2]
    duration_gap = abs(request_duration - member_duration)
    duration_score = 10.0 if duration_gap <= 30 else (5.0 if duration_gap <= 90 else 0.0)
    schedule_score = (10.0 if same_day else 0.0) + duration_score

    trust_score = {"unverified": 0.0, "basic": 8.0, "standard": 12.0, "trusted": 15.0}.get(
        member_tier, 8.0
    )

    total = round(
        min(100.0, interest_score + budget_score + schedule_score + trust_score), 1
    )
    return {
        "score": total,
        "shared_interests": shared,
        "components": {
            "interests": round(interest_score, 1),
            "budget": round(budget_score, 1),
            "schedule": round(schedule_score, 1),
            "trust": round(trust_score, 1),
        },
    }


#: Minimum compatibility for a candidate to join a formed group.
MEETUP_MIN_COMPATIBILITY = 45.0


def can_match(score: float, group_size: int, blocked: bool = False) -> tuple[bool, str]:
    if blocked:
        return False, "blocked_or_reported"
    if group_size < 2:
        return False, "group_too_small"
    if group_size > 5:
        return False, "group_full"
    if score < MEETUP_MIN_COMPATIBILITY:
        return False, f"compatibility_below_{int(MEETUP_MIN_COMPATIBILITY)}"
    return True, "eligible"


# ---------------------------------------------------------------------------
# Group decision maths
# ---------------------------------------------------------------------------


def aggregate_group_constraints(members: list[dict], fallback: dict) -> dict:
    """Combine member preferences into one group constraint set.

    Budget uses the **lowest** stated budget (a plan nobody can afford is not a
    group plan); time uses the **median** so one outlier cannot shrink the day.
    """
    if not members:
        return dict(fallback)
    budgets = sorted(int(m.get("budget_inr") or fallback["budget_inr"]) for m in members)
    times = sorted(float(m.get("time_hours") or fallback["time_hours"]) for m in members)
    interests: set[str] = set()
    for m in members:
        interests.update(i.lower() for i in (m.get("interests") or []))

    # Accessibility: required if any member needs it.
    accessibility = any(bool(m.get("accessibility")) for m in members)
    # Time: median, rounded to a sane increment.
    median = times[len(times) // 2]
    median = max(1.0, round(median))

    return {
        "location": fallback.get("location", "Bandra, Mumbai"),
        "budget_inr": budgets[0],
        "time_hours": median,
        "interests": sorted(interests),
        "accessibility": accessibility,
        "member_count": len(members),
    }


def tally_votes(votes: list[dict], option_rank: dict[int, int]) -> dict[int, dict]:
    """First-past-the-post with rank as a tie-break.

    Each voter contributes 1 point to their first choice; options are then
    ordered by (votes, average rank, option id) so the result is stable.
    """
    tally: dict[int, dict] = {}
    for vote in votes:
        option_id = int(vote["option_id"])
        entry = tally.setdefault(
            option_id, {"votes": 0, "rank_sum": 0, "rank_count": 0, "voters": []}
        )
        entry["votes"] += 1
        rank = int(vote.get("rank") or option_rank.get(option_id, 1))
        entry["rank_sum"] += rank
        entry["rank_count"] += 1
        entry["voters"].append(int(vote["user_id"]))
    for entry in tally.values():
        entry["avg_rank"] = round(
            entry["rank_sum"] / entry["rank_count"], 2
        ) if entry["rank_count"] else 0.0
    return tally


def resolve_winner(tally: dict[int, dict], total_votes: int) -> tuple[int | None, bool]:
    """Return ``(winning_option_id, is_tie)``.

    A tie is reported rather than silently broken so the client can ask the
    group to choose again.
    """
    if not tally:
        return None, False
    ordered = sorted(
        tally.items(),
        key=lambda kv: (-kv[1]["votes"], kv[1]["avg_rank"], kv[0]),
    )
    if len(ordered) > 1 and ordered[0][1]["votes"] == ordered[1][1]["votes"]:
        return None, True
    return ordered[0][0], False


def quorum_reached(votes_cast: int, member_count: int) -> bool:
    """A majority of members must vote before a plan can lock."""
    if member_count <= 0:
        return False
    return votes_cast * 2 > member_count


# ---------------------------------------------------------------------------
# Guide booking
# ---------------------------------------------------------------------------


def calculate_booking_cost(
    hourly_rate: int, duration_min: int, group_size: int, extras: int = 0
) -> int:
    """Total = rate x hours (rounded up) + per-head extras.

    ``extras`` is a per-attendee surcharge, so it is charged once for every
    person in the group. The MVP default is 0, which makes the quote simply the
    time charge. The guide's hourly rate is a group rate, not a per-head rate.
    """
    hours = max(1, math_ceil_div(duration_min, 60))
    base = int(hourly_rate) * hours
    return base + max(0, extras) * max(1, group_size)


def math_ceil_div(a: int, b: int) -> int:
    return -(-a // b)


#: Allowed booking transitions. Anything else is rejected server-side.
BOOKING_TRANSITIONS: dict[str, set[str]] = {
    "requested": {"accepted", "declined", "cancelled"},
    "accepted": {"confirmed", "declined", "cancelled"},
    "confirmed": {"in_progress", "cancelled"},
    "in_progress": {"completed"},
    "completed": set(),
    "declined": set(),
    "cancelled": set(),
}

BOOKING_ACTOR: dict[str, str] = {
    "accepted": "guide",
    "declined": "guide",
    "confirmed": "user",
    "cancelled": "user",
    "in_progress": "guide",
    "completed": "guide",
}


def can_transition_booking(current: str, target: str, actor: str) -> tuple[bool, str]:
    """Server-side gate for the booking state machine."""
    if target not in BOOKING_TRANSITIONS.get(current, set()):
        return False, f"cannot go from '{current}' to '{target}'"
    expected_actor = BOOKING_ACTOR.get(target)
    if expected_actor and expected_actor != actor:
        return False, f"only the {expected_actor} may set '{target}'"
    return True, "ok"


def booking_availability_conflict(
    date: str, start_time: str, end_time: str, existing: list[dict]
) -> bool:
    """True when the requested window overlaps an already-booked slot."""
    for slot in existing:
        if slot.get("date") != date:
            continue
        if slot.get("is_booked"):
            return True
        if not (end_time <= slot.get("start_time", "00:00") or start_time >= slot.get("end_time", "23:59")):
            return True
    return False


# ---------------------------------------------------------------------------
# Quests, XP and badges
# ---------------------------------------------------------------------------

LEVEL_THRESHOLDS: tuple[int, ...] = (0, 100, 300, 600, 1000, 1500)


def level_for_xp(xp: int) -> int:
    level = 1
    for index, threshold in enumerate(LEVEL_THRESHOLDS, start=1):
        if xp >= threshold:
            level = index
    return max(1, level)


BADGE_RULES: dict[str, dict] = {
    "first_quest": {"name": "First Steps", "xp": 50, "description": "Completed your first quest"},
    "gem_hunter": {"name": "Hidden Gem Hunter", "xp": 100, "description": "Completed 3 culture/outdoor quests"},
    "rainy_day_warrior": {"name": "Rainy Day Warrior", "xp": 75, "description": "Completed a quest in the rain"},
    "night_owl": {"name": "Night Owl", "xp": 75, "description": "Completed an evening/nightlife quest"},
    "quest_streak_3": {"name": "On a Roll", "xp": 120, "description": "Completed 3 quests"},
}


def evaluate_badges(*, completed_codes: list[str], weather: dict | None, categories: list[str]) -> list[str]:
    """Which badges a just-completed quest earns."""
    earned: list[str] = []
    if completed_codes:
        earned.append("first_quest")
    if len(completed_codes) >= 3:
        earned.extend(["gem_hunter", "quest_streak_3"])
    if any(c in {"culture", "outdoor"} for c in categories):
        if len(completed_codes) >= 1 and "gem_hunter" not in earned:
            earned.append("gem_hunter")
    cond = weather or {}
    if cond.get("available") and cond.get("is_rainy"):
        earned.append("rainy_day_warrior")
    if any(c == "nightlife" for c in categories):
        earned.append("night_owl")
    return sorted(set(earned))


#: Quest lifecycle
QUEST_TRANSITIONS: dict[str, set[str]] = {
    "available": {"in_progress"},
    "in_progress": {"completed", "abandoned"},
    "completed": set(),
    "abandoned": set(),
}


def can_transition_quest(current: str, target: str) -> tuple[bool, str]:
    if target not in QUEST_TRANSITIONS.get(current, set()):
        return False, f"cannot go from '{current}' to '{target}'"
    return True, "ok"


# ---------------------------------------------------------------------------
# Guide growth
# ---------------------------------------------------------------------------

GUIDE_TIERS: tuple[str, ...] = ("bronze", "silver", "gold", "platinum")

#: Features unlocked per tier; used to gate endpoints server-side.
TIER_FEATURES: dict[str, set[str]] = {
    "bronze": {"accept_booking"},
    "silver": {"accept_booking", "custom_itinerary", "priority_search"},
    "gold": {"accept_booking", "custom_itinerary", "priority_search", "premium_listing"},
    "platinum": {
        "accept_booking",
        "custom_itinerary",
        "priority_search",
        "premium_listing",
        "group_leads",
        "api_access",
    },
}

TIER_REQUIREMENTS: dict[str, dict] = {
    "silver": {"completed_tours": 3, "rating": 4.0},
    "gold": {"completed_tours": 10, "rating": 4.3, "certifications": 1},
    "platinum": {"completed_tours": 25, "rating": 4.6, "certifications": 3},
}

GUIDE_TRANSITIONS: dict[str, set[str]] = {
    "signup": {"id_uploaded", "suspended"},
    "id_uploaded": {"verified", "rejected", "suspended"},
    "verified": {"active", "suspended"},
    "active": {"suspended"},
    "rejected": {"id_uploaded"},
    "suspended": set(),
}


def can_transition_guide(current: str, target: str) -> tuple[bool, str]:
    if target not in GUIDE_TRANSITIONS.get(current, set()):
        return False, f"cannot go from '{current}' to '{target}'"
    return True, "ok"


def next_guide_tier(
    *,
    tier: str,
    completed_tours: int,
    average_rating: float,
    certifications: int,
) -> str | None:
    """The highest tier this guide already qualifies for, or None.

    Returns the best tier available rather than the first one that matches, so
    the growth screen does not tell a platinum-ready guide to chase silver.
    """
    try:
        index = GUIDE_TIERS.index(tier)
    except ValueError:
        return None
    best: str | None = None
    for candidate in GUIDE_TIERS[index + 1 :]:
        req = TIER_REQUIREMENTS.get(candidate, {})
        if (
            completed_tours >= req.get("completed_tours", 0)
            and average_rating >= req.get("rating", 0.0)
            and certifications >= req.get("certifications", 0)
        ):
            best = candidate
    return best


def tier_features(tier: str) -> list[str]:
    return sorted(TIER_FEATURES.get(tier, TIER_FEATURES["bronze"]))


def has_feature(tier: str, feature: str) -> bool:
    return feature in TIER_FEATURES.get(tier, set())


def visibility_boost(tier: str) -> float:
    """Ranking multiplier applied to guides in listings."""
    return {"bronze": 1.0, "silver": 1.1, "gold": 1.25, "platinum": 1.4}.get(tier, 1.0)


# ---------------------------------------------------------------------------
# Safety (simulated, deterministic)
# ---------------------------------------------------------------------------

SAFETY_PUBLIC_PLACE_TAGS = {"landmark", "museum", "gallery", "market", "cafe", "heritage"}


def safety_score(place, *, hour: int = 18) -> dict:
    """Deterministic 0-100 safety signal for a plan.

    MVP: derived from curated metadata (venue type + opening hours + capacity
    signal), never from live incident data. Returned with its reasoning so the
    UI can show *why* a plan scored as it did.
    """
    if place is None:
        return {"score": 50, "signals": [], "meeting_point": "Public venue entrance"}

    tags = {t.lower() for t in (getattr(place, "tags", None) or [])}
    flags = {f.lower() for f in (getattr(place, "accessibility_flags", None) or [])}
    score = 55
    signals: list[str] = []

    if tags & SAFETY_PUBLIC_PLACE_TAGS:
        score += 15
        signals.append("Public, well-known venue")
    if "wheelchair-accessible" in flags or "step-free" in flags:
        score += 8
        signals.append("Step-free access, easier to navigate")

    close_h = getattr(place, "close_time", "21:00")
    try:
        closes = int(str(close_h)[:2])
    except (TypeError, ValueError):
        closes = 21
    if hour >= 20 and closes < 24:
        score -= 18
        signals.append("Venue closes early for a late plan")
    elif 7 <= hour <= 20:
        score += 8
        signals.append("Comfortable daylight/evening hours")

    area = (getattr(place, "area", "") or "").lower()
    if any(k in area for k in ("bandra", "colaba", "fort", "juhu", "andheri")):
        score += 10
        signals.append("Well-connected area with transport options")

    return {
        "score": max(0, min(100, score)),
        "signals": signals,
        "meeting_point": f"{getattr(place, 'name', 'Venue')} main entrance (public, lit)",
    }


# ---------------------------------------------------------------------------
# Companion (AI) state
# ---------------------------------------------------------------------------

COMPANION_PERSONALITIES: tuple[str, ...] = ("chill_friend", "history_buff", "foodie")

COMPANION_MODES: dict[str, dict] = {
    "chill_friend": {"label": "Chill Friend", "tone": "relaxed, casual"},
    "history_buff": {"label": "History Buff", "tone": "deep heritage context"},
    "foodie": {"label": "Foodie", "tone": "obsessed with local eats"},
}


def companion_state(enabled: bool, personality: str) -> dict:
    """Server-owned companion state for the solo journey (UI renders this)."""
    if not enabled:
        return {"enabled": False, "state": "off", "personality": None, "greeting": None}
    if personality not in COMPANION_PERSONALITIES:
        personality = "chill_friend"
    return {
        "enabled": True,
        "state": "active_mock",
        "personality": personality,
        "personality_label": COMPANION_MODES[personality]["label"],
        "tone": COMPANION_MODES[personality]["tone"],
        "greeting": "I'm along for the ride — ask me anything as we go.",
    }


# ---------------------------------------------------------------------------
# Misc
# ---------------------------------------------------------------------------


@dataclass
class ExpiryResult:
    expired: bool
    reason: str = ""


def is_expired(expires_at, *, now=None) -> ExpiryResult:
    now = now or utcnow()
    if expires_at is None:
        return ExpiryResult(False)
    return ExpiryResult(bool(expires_at < now), "expired" if expires_at < now else "")
