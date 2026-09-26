"""Recommendation engine service for LocalIQ.

Two phases:
  Phase A — Feasibility (hard constraints filter out impossible options)
  Phase B — Ranking (score only feasible options)
"""

import logging
import math
from dataclasses import dataclass, field

from app.config import get_settings
from app.models import Experience

logger = logging.getLogger(__name__)

# Deterministic offline travel heuristic for Mumbai.
AVG_CITY_SPEED_KMPH = 20.0
MIN_TRAVEL_MIN = 10
BUFFER_MIN = 20
MAX_CONSIDER_DISTANCE_KM = 30.0

# Known Mumbai area anchors for natural-language `location` strings.
KNOWN_AREAS: dict[str, tuple[float, float]] = {
    "bandra": (19.0596, 72.8295),
    "bandra west": (19.0596, 72.8295),
    "carter road": (19.0620, 72.8260),
    "bandstand": (19.0500, 72.8200),
    "juhu": (19.1075, 72.8263),
    "versova": (19.1315, 72.8138),
    "andheri": (19.1197, 72.8464),
    "andheri west": (19.1319, 72.8266),
    "powai": (19.1210, 72.9055),
    "goregaon": (19.1647, 72.8725),
    "borivali": (19.2288, 72.9170),
    "dadar": (19.0187, 72.8431),
    "lower parel": (19.0065, 72.8300),
    "parel": (19.0120, 72.8360),
    "worli": (19.0000, 72.8170),
    "prabhadevi": (19.0169, 72.8302),
    "mahim": (19.0360, 72.8390),
    "colaba": (18.9067, 72.8147),
    "gateway": (18.9220, 72.8347),
    "fort": (18.9328, 72.8303),
    "kala ghoda": (18.9279, 72.8300),
    "nariman point": (18.9297, 72.8239),
    "marine drive": (18.9430, 72.8238),
    "churchgate": (18.9350, 72.8270),
    "csmt": (18.9398, 72.8355),
    "ballard estate": (18.9278, 72.8413),
    "malabar hill": (18.9562, 72.8046),
    "walkeshwar": (18.9451, 72.7922),
    "haji ali": (18.9827, 72.8257),
    "mahalaxmi": (18.9800, 72.8250),
    "ghatkopar": (19.0907, 72.9072),
    "kurla": (19.0650, 72.8790),
    "bkc": (19.0650, 72.8700),
    "bandra kurla": (19.0650, 72.8700),
    "chembur": (19.0620, 72.8970),
    "thane": (19.2183, 72.9781),
    "navi mumbai": (19.0330, 73.0297),
    "south mumbai": (18.9270, 72.8330),
    "suburbs": (19.1100, 72.8500),
    "mumbai": (19.0760, 72.8777),
}


def haversine_km(lat1: float, lon1: float, lat2: float, lon2: float) -> float:
    """Great-circle distance in km."""
    r = 6371.0
    dlat = math.radians(lat2 - lat1)
    dlon = math.radians(lon2 - lon1)
    a = (
        math.sin(dlat / 2) ** 2
        + math.cos(math.radians(lat1)) * math.cos(math.radians(lat2)) * math.sin(dlon / 2) ** 2
    )
    return 2 * r * math.asin(math.sqrt(a))


def estimate_travel_time_min(distance_km: float) -> int:
    """Deterministic offline travel estimate (Mumbai traffic heuristic)."""
    if distance_km <= 0:
        return MIN_TRAVEL_MIN
    minutes = (distance_km / AVG_CITY_SPEED_KMPH) * 60.0
    # Short-trip overhead: signals, parking, walking to venue.
    minutes += 8
    return max(MIN_TRAVEL_MIN, int(round(minutes)))


def resolve_location(location: str | None) -> tuple[float, float] | None:
    """Map a free-text location to lat/lng using known anchors."""
    if not location:
        return None
    key = location.strip().lower()
    if key in KNOWN_AREAS:
        return KNOWN_AREAS[key]
    # Substring match: "near Bandra station" -> bandra
    for name, coords in KNOWN_AREAS.items():
        if name in key or key in name:
            return coords
    return None


def parse_hhmm(value: str | None) -> int | None:
    """Parse 'HH:MM' (24h) to minutes since midnight. Returns None if invalid."""
    if not value:
        return None
    text = value.strip()
    # Accept "10:00", "10:00 AM", ISO datetimes (take time part).
    if "T" in text:
        text = text.split("T", 1)[1][:5]
    text = text.upper().replace(" ", "")
    ampm = None
    for suffix in ("AM", "PM"):
        if text.endswith(suffix):
            ampm = suffix
            text = text[: -len(suffix)]
            break
    parts = text.split(":")
    try:
        h = int(parts[0])
        m = int(parts[1]) if len(parts) > 1 else 0
    except (ValueError, IndexError):
        return None
    if ampm == "PM" and h < 12:
        h += 12
    if ampm == "AM" and h == 12:
        h = 0
    if not (0 <= h <= 24 and 0 <= m < 60):
        return None
    if h == 24:
        h = 0
    return h * 60 + m


def is_open_at(exp: Experience, start_min: int | None, total_needed_min: int) -> bool:
    """Check venue opening hours cover [start, start+needed]. Overnight aware."""
    open_min = parse_hhmm(exp.open_time)
    close_min = parse_hhmm(exp.close_time)
    if open_min is None or close_min is None:
        return True  # Unknown hours -> don't block.
    if open_min == 0 and close_min == 0:
        return True  # 00:00-00:00 means 24h in our dataset convention.
    # Overnight venue e.g. 18:00-01:30.
    if close_min <= open_min:
        close_min += 24 * 60
    if start_min is None:
        # Without a start time we only require the visit duration to fit
        # within the open window length.
        return (close_min - open_min) >= min(total_needed_min, exp.duration_min)
    end_min = start_min + total_needed_min
    # Allow visit to roll past midnight for overnight venues.
    s = start_min
    if s < open_min and close_min > 24 * 60:
        s += 24 * 60
    return s >= open_min and end_min <= close_min


@dataclass
class FeasibilityResult:
    feasible: bool
    reasons: list[str] = field(default_factory=list)
    distance_km: float = 0.0
    travel_time_min: int = 0
    total_time_min: int = 0


# ---------------------------------------------------------------------------
# Accessibility capabilities
# ---------------------------------------------------------------------------
# A venue advertises capabilities; a traveller requests them. The match is
# strict and per-capability: asking for "wheelchair-accessible" must NOT be
# satisfied by a venue that only says "step-free", because a step-free entrance
# can still have stairs, narrow doorways or no accessible restroom.

#: Request token -> tokens that satisfy it in a venue's flag list.
ACCESSIBILITY_ALIASES: dict[str, tuple[str, ...]] = {
    "wheelchair-accessible": ("wheelchair-accessible", "wheelchair"),
    "wheelchair": ("wheelchair-accessible", "wheelchair"),
    "step-free": ("step-free", "step free", "stepfree"),
    "accessible": ("wheelchair-accessible", "accessible"),
    "sensory-friendly": ("sensory-friendly", "sensory friendly", "sensory"),
    "stroller-friendly": ("stroller-friendly", "stroller"),
    "elevator": ("elevator", "lift"),
}


def required_accessibility(
    accessibility: str | list[str] | None,
) -> list[str]:
    """Normalise a request into canonical capability tokens."""
    if not accessibility:
        return []
    raw = [accessibility] if isinstance(accessibility, str) else list(accessibility)
    out: list[str] = []
    for item in raw:
        token = (item or "").strip().lower()
        if not token:
            continue
        canonical = token.replace("_", "-").replace(" ", "-")
        for key in ACCESSIBILITY_ALIASES:
            if key in canonical:
                if key not in out:
                    out.append(key)
                break
        else:
            if token not in out:
                out.append(token)
    return out


def venue_capabilities(flags: list[str] | None) -> set[str]:
    """Canonical capabilities a venue claims."""
    caps: set[str] = set()
    for flag in flags or []:
        token = (flag or "").strip().lower()
        if not token:
            continue
        for key, aliases in ACCESSIBILITY_ALIASES.items():
            if any(alias in token for alias in aliases):
                caps.add(key)
    return caps


def missing_capabilities(
    accessibility: str | list[str] | None, flags: list[str] | None
) -> list[str]:
    """Requested capabilities the venue does not advertise (empty == OK)."""
    required = required_accessibility(accessibility)
    if not required:
        return []
    have = venue_capabilities(flags)
    return [cap for cap in required if cap not in have]



def check_feasibility(
    exp: Experience,
    *,
    budget_inr: int | None,
    time_hours: float | None,
    user_coords: tuple[float, float] | None,
    accessibility: str | list[str] | None,
    start_time: str | None,
) -> FeasibilityResult:
    """Phase A — hard-constraint feasibility."""
    reasons: list[str] = []
    distance_km = 0.0
    travel_time_min = 0

    if user_coords is not None:
        distance_km = haversine_km(user_coords[0], user_coords[1], exp.lat, exp.lng)
        travel_time_min = estimate_travel_time_min(distance_km)
        if distance_km > MAX_CONSIDER_DISTANCE_KM:
            return FeasibilityResult(
                False,
                [f"{distance_km:.0f}km away exceeds day-trip range"],
                distance_km,
                travel_time_min,
                0,
            )

    # Round trip travel + visit + buffer.
    total_needed = exp.duration_min + travel_time_min * 2 + BUFFER_MIN

    # 1. Budget (hard).
    if budget_inr is not None and exp.avg_cost > budget_inr:
        return FeasibilityResult(
            False, [f"₹{exp.avg_cost} exceeds ₹{budget_inr} budget"], distance_km, travel_time_min, total_needed
        )

    # 2-5. Time: duration + travel + buffer must fit.
    if time_hours is not None:
        available_min = int(time_hours * 60)
        if total_needed > available_min:
            return FeasibilityResult(
                False,
                [f"needs ~{total_needed}min (visit+travel) but only {available_min}min available"],
                distance_km,
                travel_time_min,
                total_needed,
            )

    # 6. Opening hours.
    start_min = parse_hhmm(start_time)
    if not is_open_at(exp, start_min, exp.duration_min + BUFFER_MIN):
        return FeasibilityResult(
            False,
            [f"closed for requested window ({exp.open_time}-{exp.close_time})"],
            distance_km,
            travel_time_min,
            total_needed,
        )

    # 7. Accessibility (strict, per requested capability).
    missing = missing_capabilities(accessibility, exp.accessibility_flags)
    if missing:
        return FeasibilityResult(
            False,
            [f"missing accessibility: {', '.join(missing)}"],
            distance_km,
            travel_time_min,
            total_needed,
        )

    # 8. Location/distance already handled; near-zero distance venues pass.
    return FeasibilityResult(True, reasons, distance_km, travel_time_min, total_needed)


@dataclass
class ScoredExperience:
    experience: Experience
    score: float
    score_parts: dict
    distance_km: float
    travel_time_min: int
    total_time_min: int
    why_this_fits: str


def build_why_this_fits(
    exp: Experience,
    *,
    budget_inr: int | None,
    time_hours: float | None,
    interests: list[str],
    distance_km: float,
) -> str:
    """Deterministic template explanation (no LLM needed)."""
    bits: list[str] = []
    if budget_inr is not None:
        bits.append(f"₹{exp.avg_cost} fits your ₹{budget_inr} budget")
    else:
        bits.append(f"₹{exp.avg_cost} per person")
    if time_hours is not None:
        bits.append(f"{exp.duration_min}min fits your {time_hours:g}-hour window")
    else:
        bits.append(f"{exp.duration_min}min visit")
    matched = [i for i in (interests or []) if i.lower() == exp.category.lower()]
    if matched:
        bits.append(f"matches your interest in {matched[0]}")
    elif interests:
        bits.append(f"pairs well with {', '.join(interests[:2])}")
    if distance_km < 3:
        bits.append("right in your neighbourhood")
    elif distance_km < 10:
        bits.append(f"just {distance_km:.1f}km away")
    bits.append(f"rated {exp.rating:.1f}/5")
    return (" · ".join(b for b in bits) + ".").replace("..", ".")


def score_experience(
    exp: Experience,
    *,
    interests: list[str] | None,
    budget_inr: int | None,
    time_hours: float | None,
    distance_km: float,
    travel_time_min: int,
    weather_boost: float = 0.0,
    feedback_boost: float = 0.0,
) -> tuple[float, dict]:
    """Phase B — rank feasible experiences. Explicit weighted parts."""
    interests = [i.lower().strip() for i in (interests or []) if i]
    parts: dict[str, float] = {}

    # Interest match (0..30).
    if not interests:
        parts["interest"] = 15.0
    elif exp.category.lower() in interests:
        parts["interest"] = 30.0
    elif any(t.lower() in interests for t in (exp.tags or [])):
        parts["interest"] = 20.0
    else:
        parts["interest"] = 8.0

    # Time fit (0..20): prefer visits using 40-85% of window.
    if time_hours is None:
        parts["time_fit"] = 12.0
    else:
        available = max(1, int(time_hours * 60))
        ratio = exp.duration_min / available
        if 0.3 <= ratio <= 0.85:
            parts["time_fit"] = 20.0
        elif ratio < 0.3:
            parts["time_fit"] = 12.0 + ratio * 20.0  # short visit, still fine
            parts["time_fit"] = min(16.0, parts["time_fit"])
        else:
            parts["time_fit"] = max(4.0, 20.0 - (ratio - 0.85) * 60.0)

    # Budget fit (0..15): cheaper relative to budget scores higher.
    if budget_inr is None or budget_inr <= 0:
        parts["budget_fit"] = 10.0
    else:
        ratio = exp.avg_cost / budget_inr
        if ratio <= 0.3:
            parts["budget_fit"] = 15.0
        elif ratio <= 0.6:
            parts["budget_fit"] = 12.0
        elif ratio <= 0.9:
            parts["budget_fit"] = 9.0
        else:
            parts["budget_fit"] = 6.0

    # Distance (0..15): closer is better, zero-location gets neutral 10.
    # (Distance unknown -> neutral; caller passes distance 0 with flag via user_coords None.)
    parts["distance"] = max(0.0, 15.0 - distance_km * 0.8)

    # Rating (0..12).
    parts["rating"] = max(0.0, min(12.0, (exp.rating - 3.0) * 8.0))

    # Local gem (0..8).
    parts["gem"] = max(0.0, min(8.0, exp.local_gem_score * 8.0))

    # Weather/context boost (-6..+6).
    parts["weather"] = max(-6.0, min(6.0, weather_boost))

    # Aggregated user feedback (-8..+8).
    parts["feedback"] = max(-8.0, min(8.0, feedback_boost))

    total = round(sum(parts.values()), 2)
    return total, {k: round(v, 2) for k, v in parts.items()}


def weather_boost_for(exp: Experience, weather: dict | None) -> float:
    """Deterministic indoor/outdoor adjustment.

    Rainy -> boost indoor, penalize outdoor. Pleasant -> slight outdoor boost.
    Unknown/neutral -> 0.
    """
    if not weather or not weather.get("available", False):
        return 0.0
    kind = (exp.indoor_outdoor or "indoor").lower()
    condition = str(weather.get("condition", "unknown")).lower()
    is_rainy = bool(weather.get("is_rainy", False))
    if is_rainy or "rain" in condition or "storm" in condition or "drizzle" in condition:
        if kind == "indoor":
            return 6.0
        if kind == "mixed":
            return 1.5
        return -6.0
    if "clear" in condition or "sunny" in condition or weather.get("suitable_outdoor"):
        if kind == "outdoor":
            return 4.0
        if kind == "mixed":
            return 2.0
        return 0.0
    return 0.0



@dataclass
class RouteRecheck:
    """Result of re-validating a hard constraint against *real* route data.

    Feasibility (Phase A) runs on a fast local estimate so ranking can happen
    without waiting on the network. When Google Routes returns authoritative
    travel times those can be much longer than the estimate, so anything that
    no longer fits must be dropped rather than shown with a broken promise.
    """

    ok: bool
    total_minutes: int = 0
    reason: str = ""


def recheck_with_route(
    exp: Experience,
    *,
    distance_km: float,
    travel_minutes: int,
    time_hours: float | None,
    max_distance_km: float | None = None,
) -> RouteRecheck:
    """Re-run the distance + time hard constraints using measured values.

    Mirrors Phase A exactly (same buffer, same round-trip assumption) so a
    result that passed with real data is guaranteed to satisfy the same rules.
    """
    limit = MAX_CONSIDER_DISTANCE_KM if max_distance_km is None else max_distance_km
    if distance_km > limit:
        return RouteRecheck(
            ok=False,
            reason=f"{distance_km:.1f}km from the route exceeds the {limit:.0f}km limit",
        )

    total = exp.duration_min + travel_minutes * 2 + BUFFER_MIN
    if time_hours is not None:
        available = int(time_hours * 60)
        if total > available:
            return RouteRecheck(
                ok=False,
                total_minutes=total,
                reason=(
                    f"real travel time makes this {total}min, "
                    f"over the {available}min available"
                ),
            )
    return RouteRecheck(ok=True, total_minutes=total)


def recommend(
    experiences: list[Experience],
    *,
    location: str | None = None,
    time_hours: float | None = None,
    budget_inr: int | None = None,
    interests: list[str] | None = None,
    accessibility: str | list[str] | None = None,
    start_time: str | None = None,
    weather: dict | None = None,
    feedback_scores: dict[int, float] | None = None,
    limit: int = 10,
) -> dict:
    """Run feasibility + ranking. Never raises for bad inputs; returns metadata."""
    user_coords = resolve_location(location)
    total_candidates = len(experiences)
    scored: list[ScoredExperience] = []

    for exp in experiences:
        feas = check_feasibility(
            exp,
            budget_inr=budget_inr,
            time_hours=time_hours,
            user_coords=user_coords,
            accessibility=accessibility,
            start_time=start_time,
        )
        if not feas.feasible:
            continue
        boost = weather_boost_for(exp, weather)
        feedback_boost = get_settings().feedback_weight * float(
            (feedback_scores or {}).get(exp.id or 0, 0.0)
        )
        # When no location given, pass 0 distance but neutralize distance part later.
        score, parts = score_experience(
            exp,
            interests=interests,
            budget_inr=budget_inr,
            time_hours=time_hours,
            distance_km=feas.distance_km,
            travel_time_min=feas.travel_time_min,
            weather_boost=boost,
            feedback_boost=feedback_boost,
        )
        if user_coords is None:
            # Neutral distance when user gave no location.
            score = round(score - parts["distance"] + 10.0, 2)
            parts["distance"] = 10.0
        why = build_why_this_fits(
            exp, budget_inr=budget_inr, time_hours=time_hours, interests=interests or [], distance_km=feas.distance_km
        )
        scored.append(
            ScoredExperience(
                experience=exp,
                score=score,
                score_parts=parts,
                distance_km=round(feas.distance_km, 2),
                travel_time_min=feas.travel_time_min,
                total_time_min=feas.total_time_min,
                why_this_fits=why,
            )
        )

    scored.sort(key=lambda s: s.score, reverse=True)
    top = scored[: max(1, limit)]
    logger.info(
        "Recommend: candidates=%d feasible=%d location=%s interests=%s",
        total_candidates,
        len(scored),
        location,
        interests,
    )
    return {
        "total_candidates": total_candidates,
        "feasible_count": len(scored),
        "results": top,
        "user_coords": user_coords,
        "weather_used": bool(weather and weather.get("available", False)),
    }
