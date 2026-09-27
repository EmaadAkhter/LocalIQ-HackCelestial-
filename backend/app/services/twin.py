"""Weather Digital Twin: a simulation layer over LocalIQ's experience graph.

Weather is not just a filter here. It changes demand, capacity, movement and
safety across the city. This service computes, for a given weather scenario:

  * a per-experience state (weather suitability, risk flags, demand multiplier)
  * a per-area state (flood risk, movement slowdown, heat stress)
  * a cascading summary the demo can narrate

South Mumbai is the pilot area, but nothing is hard-coded to it: every area in
``recommender.KNOWN_AREAS`` is scored, so Bandra/Colaba already work.

The score model is deliberately a transparent heuristic (hackathon-stage). The
roadmap in the PRD is to replace the multipliers with parameters learned from
historical weather + click/completion data.
"""

from __future__ import annotations

import json
import logging
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

from sqlmodel import Session, select

from app.models import Experience
from app.services.recommender import KNOWN_AREAS, haversine_km

logger = logging.getLogger(__name__)

# ---------------------------------------------------------------------------
# Scenario vocabulary
# ---------------------------------------------------------------------------

#: Rain intensity name -> normalised 0..1 driver.
RAIN_LEVELS: dict[str, float] = {
    "none": 0.0,
    "light": 0.35,
    "heavy": 0.7,
    "storm": 1.0,
}

#: Heat severity name -> normalised 0..1 driver.
HEAT_LEVELS: dict[str, float] = {
    "normal": 0.0,
    "hot": 0.5,
    "extreme": 1.0,
}

#: How sheltered an experience is. 1.0 fully indoor, 0.0 fully outdoor.
INDOOR_RATIO: dict[str, float] = {"indoor": 1.0, "mixed": 0.5, "outdoor": 0.0}

#: Coastal / low-lying propensity to flood, seeded from known Mumbai behaviour.
#: Any area not listed gets ``DEFAULT_FLOOD_PROPENSITY``.
FLOOD_PROPENSITY: dict[str, float] = {
    "marine drive": 0.95, "churchgate": 0.9, "colaba": 0.85, "fort": 0.8,
    "csmt": 0.85, "ballard estate": 0.8, "nariman point": 0.9, "kala ghoda": 0.65,
    "dadar": 0.7, "mahim": 0.65, "worli": 0.6, "lower parel": 0.55, "parel": 0.55,
    "prabhadevi": 0.55, "bandra": 0.6, "bandra west": 0.6, "carter road": 0.65,
    "bandstand": 0.6, "juhu": 0.55, "versova": 0.5, "andheri": 0.5,
    "kurla": 0.75, "sion": 0.7, "chembur": 0.6, "powai": 0.35, "bkc": 0.6,
    "malabar hill": 0.25, "walkeshwar": 0.3, "haji ali": 0.45, "mahalaxmi": 0.5,
}
DEFAULT_FLOOD_PROPENSITY = 0.4

SIGNAL_PATH = Path(__file__).resolve().parents[2] / "data" / "social_signals_demo.json"

#: Suitability below this makes an experience "infeasible right now".
INFEASIBLE_SCORE = 40.0


# ---------------------------------------------------------------------------
# Small helpers
# ---------------------------------------------------------------------------


def _clamp(value: float, low: float = 0.0, high: float = 1.0) -> float:
    return max(low, min(high, value))


def indoor_ratio(experience: Experience) -> float:
    return INDOOR_RATIO.get((experience.indoor_outdoor or "indoor").lower(), 0.5)


def rain_from_weather(weather: dict[str, Any]) -> tuple[str, float]:
    """Map a live weather snapshot to a scenario rain level."""
    if not weather or not weather.get("available"):
        return "none", 0.0
    condition = (weather.get("condition") or "").lower()
    if condition == "storm":
        return "storm", RAIN_LEVELS["storm"]
    if condition == "rain":
        chance = weather.get("precipitation_chance") or 0
        level = "heavy" if chance >= 80 else "light"
        return level, RAIN_LEVELS[level]
    if condition in ("drizzle", "showers"):
        return "light", RAIN_LEVELS["light"]
    return "none", 0.0


def heat_from_weather(weather: dict[str, Any]) -> tuple[str, float]:
    if not weather or not weather.get("available"):
        return "normal", 0.0
    temp = weather.get("temp_c")
    if temp is None:
        return "normal", 0.0
    if temp >= 40:
        return "extreme", HEAT_LEVELS["extreme"]
    if temp >= 34:
        return "hot", HEAT_LEVELS["hot"]
    return "normal", 0.0


# ---------------------------------------------------------------------------
# Social signals (curated demo feed)
# ---------------------------------------------------------------------------

_signals_cache: dict[str, Any] | None = None


def load_social_signals() -> dict[str, Any]:
    """Load the curated demo feed once. Never raises."""
    global _signals_cache
    if _signals_cache is not None:
        return _signals_cache
    try:
        raw = json.loads(SIGNAL_PATH.read_text())
        posts = raw.get("posts", [])
    except Exception as exc:  # noqa: BLE001
        logger.warning("Social signal feed unavailable: %s", exc)
        posts = []
    by_area: dict[str, dict[str, float]] = {}
    for post in posts:
        area = (post.get("area") or "").lower().strip()
        if not area:
            continue
        bucket = by_area.setdefault(area, {"flood": 0.0, "indoor_boost": 0.0, "mentions": 0.0})
        severity = float(post.get("severity", 0.5))
        bucket["mentions"] += 1
        signal = post.get("signal")
        if signal in ("flood", "closed"):
            bucket["flood"] = max(bucket["flood"], severity)
        elif signal in ("indoor_boost", "crowded"):
            bucket["indoor_boost"] = max(bucket["indoor_boost"], severity)
    _signals_cache = {"posts": posts, "by_area": by_area}
    return _signals_cache


def signals_for_area(area: str) -> dict[str, float]:
    return load_social_signals()["by_area"].get(area.lower(), {"flood": 0.0, "indoor_boost": 0.0, "mentions": 0.0})


# ---------------------------------------------------------------------------
# Core scoring
# ---------------------------------------------------------------------------


def experience_state(
    experience: Experience,
    *,
    rain: float,
    heat: float,
    area_flood: float,
    indoor_boost: float = 0.0,
) -> dict[str, Any]:
    """Weather suitability + risk flags + demand multiplier for one experience."""
    io = indoor_ratio(experience)
    outdoor_exposure = 1.0 - io

    score = 78.0
    score -= rain * 65.0 * outdoor_exposure      # outdoor takes the hit
    score += rain * 18.0 * io                    # indoor gains
    score -= heat * 45.0 * outdoor_exposure
    score += heat * 8.0 * io
    score -= area_flood * 25.0                   # everyone nearby suffers
    score += indoor_boost * 10.0 * io            # booked-out indoor venues
    score = max(0.0, min(100.0, score))

    flags: list[str] = []
    if rain >= 0.6:
        flags.append("rain-safe indoor" if io >= 0.5 else "heavy rain exposure")
    elif rain >= 0.3:
        flags.append("light rain")
    if heat >= 0.5 and io < 0.5:
        flags.append("extreme heat")
    if area_flood >= 0.6:
        flags.append("flood risk nearby")
    if not flags:
        flags.append("good conditions")

    demand = 1.0 + rain * 1.3 * io + indoor_boost * 0.4 * io
    return {
        "weather_suitability_score": round(score, 1),
        "risk_flags": flags,
        "demand_multiplier": round(demand, 2),
        "indoor_ratio": io,
        "infeasible": score < INFEASIBLE_SCORE,
    }


def area_state(
    name: str,
    *,
    rain: float,
    heat: float,
    duration_hours: float,
    flood_multiplier: float,
    social: dict[str, float],
) -> dict[str, Any]:
    """Flood / movement / heat state for one area."""
    propensity = FLOOD_PROPENSITY.get(name.lower(), DEFAULT_FLOOD_PROPENSITY)
    duration_factor = _clamp(0.5 + duration_hours / 6.0, 0.5, 1.0)
    flood = _clamp(
        propensity * rain * duration_factor * flood_multiplier + social.get("flood", 0.0) * 0.5
    )
    movement = 1.0 + rain * 0.3 + flood * 0.35

    flood_level = "HIGH" if flood >= 0.6 else "MEDIUM" if flood >= 0.3 else "LOW"
    heat_level = "HIGH" if heat >= 0.75 else "MEDIUM" if heat >= 0.4 else "LOW"

    return {
        "name": " ".join(w.capitalize() for w in name.split()),
        "flood_risk_level": flood_level,
        "flood_risk_score": round(flood, 2),
        "movement_slowdown_factor": round(movement, 2),
        "heat_stress_level": heat_level,
        "social_signal_strength": round(social.get("flood", 0.0), 2),
        "indoor_demand_boost": round(social.get("indoor_boost", 0.0), 2),
        "mentions": int(social.get("mentions", 0)),
    }


# ---------------------------------------------------------------------------
# State assembly
# ---------------------------------------------------------------------------


def _areas_near(lat: float, lng: float, radius_km: float) -> list[str]:
    hits = []
    for name, (alat, alng) in KNOWN_AREAS.items():
        if name in ("mumbai", "suburbs", "south mumbai", "navi mumbai", "thane"):
            continue
        if haversine_km(lat, lng, alat, alng) <= radius_km:
            hits.append(name)
    return hits or ["south mumbai"]


def build_state(
    session: Session,
    *,
    lat: float,
    lng: float,
    radius_km: float = 8.0,
    rain_level: str | None = None,
    duration_hours: float = 2.0,
    flood_multiplier: float = 1.0,
    heat_level: str | None = None,
    weather: dict[str, Any] | None = None,
) -> dict[str, Any]:
    """Compute the twin's state under a scenario.

    ``rain_level`` / ``heat_level`` drive a what-if simulation. When omitted,
    they are derived from the supplied live ``weather`` snapshot.
    """
    if rain_level is None:
        rain_level, rain = rain_from_weather(weather or {})
    else:
        rain = RAIN_LEVELS.get(rain_level, 0.0)
    if heat_level is None:
        _, heat = heat_from_weather(weather or {})
    else:
        heat = HEAT_LEVELS.get(heat_level, 0.0)

    # Which experiences are in play.
    rows = list(session.exec(select(Experience)).all())
    nearby = [
        e for e in rows if haversine_km(lat, lng, e.lat, e.lng) <= radius_km
    ] or rows

    # Area states first: experience risk depends on the local flood picture.
    area_names = _areas_near(lat, lng, radius_km)
    areas = [
        area_state(
            name,
            rain=rain,
            heat=heat,
            duration_hours=duration_hours,
            flood_multiplier=flood_multiplier,
            social=signals_for_area(name),
        )
        for name in area_names
    ]
    # Approximate each experience's local flood by its nearest area.
    def _nearest_area(e: Experience) -> dict[str, Any]:
        best, best_d = None, 1e9
        for name, state in zip(area_names, areas):
            alat, alng = KNOWN_AREAS[name]
            d = haversine_km(e.lat, e.lng, alat, alng)
            if d < best_d:
                best, best_d = state, d
        return best or {"flood_risk_score": 0.0, "indoor_demand_boost": 0.0}

    experiences = []
    for e in nearby:
        local = _nearest_area(e)
        state = experience_state(
            e,
            rain=rain,
            heat=heat,
            area_flood=local["flood_risk_score"],
            indoor_boost=local["indoor_demand_boost"],
        )
        experiences.append(
            {
                "id": e.id,
                "name": e.name,
                "category": e.category,
                "lat": e.lat,
                "lng": e.lng,
                "indoor_outdoor": e.indoor_outdoor,
                **state,
            }
        )

    return {
        "generated_at": datetime.now(timezone.utc).isoformat(),
        "pilot_area": "south mumbai",
        "scenario": {
            "rain_level": rain_level,
            "rain_intensity": round(rain, 2),
            "heat_level": heat_level or "normal",
            "heat_intensity": round(heat, 2),
            "duration_hours": duration_hours,
            "flood_multiplier": flood_multiplier,
        },
        "areas": areas,
        "experiences": experiences,
        "summary": summarize(experiences, areas),
    }


def summarize(
    experiences: list[dict[str, Any]], areas: list[dict[str, Any]]
) -> dict[str, Any]:
    """Cascading effects the demo narrates as a before/after."""
    outdoor = [e for e in experiences if e["indoor_ratio"] < 0.5]
    impacted = [e for e in outdoor if e["infeasible"]]
    pct = round(100.0 * len(impacted) / len(outdoor), 0) if outdoor else 0.0

    indoor = [e for e in experiences if e["indoor_ratio"] >= 0.5]
    peak_demand = max((e["demand_multiplier"] for e in indoor), default=1.0)

    flooded = [a for a in areas if a["flood_risk_level"] == "HIGH"]
    slowdown = (
        round(sum(a["movement_slowdown_factor"] for a in areas) / len(areas), 2)
        if areas else 1.0
    )

    # Best indoor alternative when the outdoors are washed out.
    ranked_indoor = sorted(indoor, key=lambda e: -e["weather_suitability_score"])
    ranked_outdoor = sorted(outdoor, key=lambda e: -e["weather_suitability_score"])
    switch = None
    if impacted and ranked_indoor:
        switch = {
            "from": (ranked_outdoor[0]["name"] if ranked_outdoor else impacted[0]["name"]),
            "to": ranked_indoor[0]["name"],
        }

    lines = [
        f"{pct:.0f}% of outdoor experiences become infeasible."
        if impacted else "Outdoor experiences stay feasible.",
        f"Indoor demand peaks at {peak_demand:.1f}x.",
    ]
    if flooded:
        lines.append(
            "Flood risk is HIGH in " + ", ".join(a["name"] for a in flooded[:3]) + "."
        )
    lines.append(f"Average movement speed reduced by {max(0.0, (slowdown - 1) * 100):.0f}%.")

    return {
        "outdoor_impacted_pct": pct,
        "outdoor_infeasible_count": len(impacted),
        "outdoor_total": len(outdoor),
        "peak_indoor_demand_multiplier": round(peak_demand, 2),
        "high_flood_areas": [a["name"] for a in flooded],
        "avg_movement_slowdown": slowdown,
        "suggested_switch": switch,
        "headline": lines[0],
        "narrative": lines,
    }
