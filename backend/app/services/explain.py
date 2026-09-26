"""Template-based explanations: short, human-readable reasons a pick fits.

Deterministic and instant, so it never blocks the recommendation flow and is
always explainable. The recommender calls ``build_reasons`` per candidate.
"""

from __future__ import annotations

from app.schemas import Constraints, ScoreFactors

BULLET = " \u2022 "


def _fmt_number(value: float) -> str:
    return str(int(value)) if float(value).is_integer() else f"{value:g}"


def _interest_reason(matches: list[str]) -> str | None:
    if not matches:
        return None
    if len(matches) == 1:
        return f"Matches your {matches[0]} interest"
    joined = ", ".join(matches[:-1]) + f" and {matches[-1]}"
    return f"Matches your {joined} interests"


def _time_reason(constraints: Constraints, factors: ScoreFactors) -> str | None:
    window = f"{_fmt_number(constraints.time_hours)}-hour"
    if factors.time_fit >= 0.7:
        return f"Fits your {window} window"
    return f"Just fits your {window} window"


def _budget_reason(constraints: Constraints, factors: ScoreFactors) -> str | None:
    budget = f"\u20b9{constraints.budget_inr:,}"
    if factors.budget_fit >= 0.7:
        return f"Within your {budget} budget"
    return f"Just within your {budget} budget"


def _distance_reason(factors: ScoreFactors) -> str | None:
    if factors.distance_km is not None:
        return f"{factors.distance_km:.1f} km away"
    if factors.travel_minutes is not None:
        return f"{factors.travel_minutes}-min trip"
    return None


def _weather_reason(factors: ScoreFactors, weather: str | None) -> str | None:
    if weather == "wet" and factors.setting == "indoor":
        return "Indoor pick for the rain"
    if weather == "dry" and factors.setting == "outdoor":
        return "Great outdoors in today's weather"
    return None


def _open_reason(factors: ScoreFactors) -> str | None:
    return "Open now" if factors.open_now else None


def _rating_reason(factors: ScoreFactors) -> str | None:
    if factors.rating is not None and factors.rating >= 4.5:
        return f"Highly rated ({factors.rating:.1f}\u2605)"
    return None


def build_reasons(
    constraints: Constraints,
    factors: ScoreFactors,
    *,
    weather: str | None = None,
    limit: int = 3,
) -> list[str]:
    """Return up to ``limit`` reasons, most decision-relevant first."""
    ranked: list[tuple[int, str]] = []

    def add(priority: int, reason: str | None) -> None:
        if reason:
            ranked.append((priority, reason))

    add(1, _interest_reason(factors.interest_matches))
    add(2, _time_reason(constraints, factors))
    add(3, _budget_reason(constraints, factors))
    add(4, _distance_reason(factors))
    add(5, _weather_reason(factors, weather))
    add(6, _open_reason(factors))
    add(7, _rating_reason(factors))

    ranked.sort(key=lambda item: item[0])
    reasons = [reason for _, reason in ranked[:limit]]

    if not reasons:
        reasons = [f"Fits your {_fmt_number(constraints.time_hours)}-hour window"]
    return reasons


def format_reasons(reasons: list[str]) -> str:
    """Join reasons into a single card-friendly line."""
    return BULLET.join(reasons)
