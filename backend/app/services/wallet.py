"""Experience Wallet & Passport (PRD 4.9).

Keeps a persistent, per-user record of completed experiences and turns it into
an "experience passport": aggregate stats, a timeline, map pins, and badges.

The wallet owns its own badge catalogue (codes prefixed ``wallet_`` so it can
never collide with the quest badge rules) and keeps ``UserProgress.badges`` /
``xp`` in sync so there is one user-facing badge list.
"""

from __future__ import annotations

import logging
from datetime import datetime, timezone
from typing import Any, Callable

from sqlmodel import Session, select

from app.models import Experience, ExperienceLog, ExperienceWallet, User, UserBadge
from app.models_prd import Badge
from app.services import taste

logger = logging.getLogger(__name__)

#: Threshold quality score at/above which an experience counts as a hidden gem.
HIDDEN_GEM_THRESHOLD = 0.7

_WALLET_BADGE_SPECS: list[dict[str, Any]] = [
    {
        "code": "wallet_first_step",
        "name": "First Step",
        "description": "Logged your first experience.",
        "xp_bonus": 25,
        "tier": "bronze",
    },
    {
        "code": "wallet_hidden_gem_hunter",
        "name": "Hidden Gem Hunter",
        "description": "Visited 5 local hidden gems.",
        "xp_bonus": 60,
        "tier": "silver",
    },
    {
        "code": "wallet_taste_trail",
        "name": "Taste Trail",
        "description": "Completed 5 food or nightlife experiences.",
        "xp_bonus": 50,
        "tier": "silver",
    },
    {
        "code": "wallet_culture_vulture",
        "name": "Culture Vulture",
        "description": "Completed 5 culture or art experiences.",
        "xp_bonus": 50,
        "tier": "silver",
    },
    {
        "code": "wallet_sunrise_specialist",
        "name": "Sunrise Specialist",
        "description": "Caught 3 sunrise or early-morning experiences.",
        "xp_bonus": 50,
        "tier": "silver",
    },
    {
        "code": "wallet_night_owl",
        "name": "Night Owl",
        "description": "Completed 3 nightlife experiences.",
        "xp_bonus": 50,
        "tier": "silver",
    },
    {
        "code": "wallet_monsoon_explorer",
        "name": "Monsoon Explorer",
        "description": "Completed 3 experiences in the rain.",
        "xp_bonus": 60,
        "tier": "silver",
    },
    {
        "code": "wallet_city_explorer",
        "name": "City Explorer",
        "description": "Logged 10 experiences.",
        "xp_bonus": 100,
        "tier": "gold",
    },
]

_BADGE_BY_CODE: dict[str, dict[str, Any]] = {b["code"]: b for b in _WALLET_BADGE_SPECS}

_CRITERIA: dict[str, Callable[[dict[str, int]], bool]] = {
    "wallet_first_step": lambda s: s["total"] >= 1,
    "wallet_hidden_gem_hunter": lambda s: s["hidden_gems"] >= 5,
    "wallet_taste_trail": lambda s: s["food"] >= 5,
    "wallet_culture_vulture": lambda s: s["culture"] >= 5,
    "wallet_sunrise_specialist": lambda s: s["sunrise"] >= 3,
    "wallet_night_owl": lambda s: s["night"] >= 3,
    "wallet_monsoon_explorer": lambda s: s["rainy"] >= 3,
    "wallet_city_explorer": lambda s: s["total"] >= 10,
}

_FOOD_CATEGORIES = {"food", "nightlife"}
_CULTURE_CATEGORIES = {"culture", "art"}
_SUNRISE_TAGS = {"sunrise", "early_morning", "good_for_morning_walk", "morning"}
_NIGHT_TAGS = {"nightlife", "late_night", "night_view"}


# ---------------------------------------------------------------------------
# Loading helpers
# ---------------------------------------------------------------------------


def get_or_create_wallet(session: Session, user_id: int) -> ExperienceWallet:
    wallet = session.exec(
        select(ExperienceWallet).where(ExperienceWallet.user_id == user_id)
    ).first()
    if wallet is None:
        wallet = ExperienceWallet(user_id=user_id)
        session.add(wallet)
        session.commit()
        session.refresh(wallet)
    return wallet


def _load(session: Session, user_id: int) -> tuple[list[ExperienceLog], dict[int, Experience]]:
    logs = list(
        session.exec(
            select(ExperienceLog)
            .where(ExperienceLog.user_id == user_id)
            .order_by(ExperienceLog.completed_at.desc())
        ).all()
    )
    ids = [log.experience_id for log in logs]
    experiences = (
        {e.id: e for e in session.exec(select(Experience).where(Experience.id.in_(ids))).all()}
        if ids
        else {}
    )
    return logs, experiences


def _stats(
    logs: list[ExperienceLog], experiences: dict[int, Experience]
) -> dict[str, int]:
    stats = {
        "total": len(logs),
        "hidden_gems": 0,
        "food": 0,
        "culture": 0,
        "sunrise": 0,
        "night": 0,
        "rainy": 0,
    }
    for log in logs:
        experience = experiences.get(log.experience_id)
        if experience is None:
            continue
        if (experience.local_gem_score or 0.0) >= HIDDEN_GEM_THRESHOLD:
            stats["hidden_gems"] += 1
        if experience.category in _FOOD_CATEGORIES:
            stats["food"] += 1
        if experience.category in _CULTURE_CATEGORIES:
            stats["culture"] += 1
        tags = {t.lower() for t in (experience.tags or [])}
        if tags & _SUNRISE_TAGS:
            stats["sunrise"] += 1
        if experience.category == "nightlife" or tags & _NIGHT_TAGS:
            stats["night"] += 1
        if bool((log.context_json or {}).get("rainy")):
            stats["rainy"] += 1
    return stats


def _recompute_wallet(
    wallet: ExperienceWallet, logs: list[ExperienceLog], experiences: dict[int, Experience]
) -> None:
    categories: dict[str, int] = {}
    cities: dict[str, int] = {}
    spent = 0
    duration = 0
    for log in logs:
        experience = experiences.get(log.experience_id)
        if experience is None:
            continue
        categories[experience.category] = categories.get(experience.category, 0) + 1
        city = str((log.context_json or {}).get("city") or "Mumbai")
        cities[city] = cities.get(city, 0) + 1
        spent += experience.avg_cost
        duration += experience.duration_min
    stats = _stats(logs, experiences)
    wallet.total_experiences = stats["total"]
    wallet.hidden_gem_count = stats["hidden_gems"]
    wallet.total_spent_inr = spent
    wallet.total_duration_min = duration
    wallet.categories_json = categories
    wallet.cities_visited_json = cities


# ---------------------------------------------------------------------------
# Badges
# ---------------------------------------------------------------------------


def ensure_badge_catalogue(session: Session) -> dict[str, Badge]:
    """Create any missing wallet badge rows so they can be referenced by id."""
    existing = {b.code: b for b in session.exec(select(Badge)).all()}
    added = False
    for spec in _WALLET_BADGE_SPECS:
        if spec["code"] not in existing:
            badge = Badge(**spec)
            session.add(badge)
            existing[spec["code"]] = badge
            added = True
    if added:
        session.commit()
        for badge in existing.values():
            session.refresh(badge)
    return existing


def _award_badges(
    session: Session, user: User, stats: dict[str, int]
) -> list[dict[str, Any]]:
    earned_codes = {
        row.badge_code
        for row in session.exec(select(UserBadge).where(UserBadge.user_id == user.id)).all()
    }
    catalogue = ensure_badge_catalogue(session)
    now = datetime.now(timezone.utc)
    newly: list[dict[str, Any]] = []

    for code, spec in _BADGE_BY_CODE.items():
        if code in earned_codes:
            continue
        if not _CRITERIA[code](stats):
            continue
        badge = catalogue.get(code)
        session.add(
            UserBadge(
                user_id=user.id or 0,
                badge_code=code,
                badge_id=badge.id if badge else None,
                earned_at=now,
                context_json={"stats": stats},
            )
        )
        newly.append(
            {
                "code": code,
                "name": spec["name"],
                "description": spec["description"],
                "tier": spec["tier"],
                "xp_bonus": spec["xp_bonus"],
                "earned_at": now,
            }
        )

    if newly:
        session.commit()
    return newly


# ---------------------------------------------------------------------------
# Public API
# ---------------------------------------------------------------------------


def log_experience(
    session: Session,
    user: User,
    experience: Experience,
    *,
    rating: float | None = None,
    notes: str | None = None,
    context: dict[str, Any] | None = None,
    record_taste: bool = True,
) -> dict[str, Any]:
    """Record (or update) a completed experience and refresh wallet + badges."""
    now = datetime.now(timezone.utc)
    existing = session.exec(
        select(ExperienceLog).where(
            ExperienceLog.user_id == user.id,
            ExperienceLog.experience_id == experience.id,
        )
    ).first()

    if existing is not None:
        if rating is not None:
            existing.rating = rating
        if notes is not None:
            existing.notes = notes[:2000]
        existing.completed_at = existing.completed_at or now
        if context:
            existing.context_json = {**(existing.context_json or {}), **context}
        session.add(existing)
        session.commit()
        session.refresh(existing)
        log = existing
    else:
        log = ExperienceLog(
            user_id=user.id or 0,
            experience_id=experience.id or 0,
            completed_at=now,
            rating=rating,
            notes=notes[:2000] if notes else None,
            context_json=context or {},
        )
        session.add(log)
        session.commit()
        session.refresh(log)

    if record_taste:
        # Completing a place is the strongest positive taste signal.
        taste.record_interaction(session, user, experience, "complete")

    wallet, newly = refresh_wallet(session, user)
    return {"log": log, "wallet": wallet, "new_badges": newly}


def refresh_wallet(
    session: Session, user: User
) -> tuple[ExperienceWallet, list[dict[str, Any]]]:
    """Recompute stats and award any newly-earned badges."""
    wallet = get_or_create_wallet(session, user.id or 0)
    logs, experiences = _load(session, user.id or 0)
    _recompute_wallet(wallet, logs, experiences)
    session.add(wallet)
    session.commit()
    session.refresh(wallet)
    newly = _award_badges(session, user, _stats(logs, experiences))
    return wallet, newly


def _badge_views(session: Session, user: User) -> list[dict[str, Any]]:
    catalogue = ensure_badge_catalogue(session)
    earned = {
        row.badge_code: row.earned_at
        for row in session.exec(select(UserBadge).where(UserBadge.user_id == user.id)).all()
    }
    views: list[dict[str, Any]] = []
    for code, spec in _BADGE_BY_CODE.items():
        badge = catalogue.get(code)
        views.append(
            {
                "code": code,
                "name": spec["name"],
                "description": spec["description"],
                "tier": spec["tier"],
                "xp_bonus": spec["xp_bonus"],
                "earned": code in earned,
                "earned_at": earned.get(code),
            }
        )
    # Earned first, then the rest.
    views.sort(key=lambda v: (not v["earned"], v["code"]))
    return views


def _timeline(logs: list[ExperienceLog], experiences: dict[int, Experience]) -> list[dict[str, Any]]:
    items: list[dict[str, Any]] = []
    for log in logs:
        experience = experiences.get(log.experience_id)
        if experience is None:
            continue
        items.append(
            {
                "experience_id": experience.id,
                "name": experience.name,
                "category": experience.category,
                "lat": experience.lat,
                "lng": experience.lng,
                "image_url": experience.image_url,
                "image_key": experience.image_key,
                "completed_at": log.completed_at,
                "rating": log.rating,
                "notes": log.notes,
            }
        )
    return items


def get_passport(
    session: Session, user: User, *, timeline_limit: int = 100
) -> dict[str, Any]:
    wallet = get_or_create_wallet(session, user.id or 0)
    logs, experiences = _load(session, user.id or 0)
    items = _timeline(logs[: max(1, timeline_limit)], experiences)
    pins = [
        {"experience_id": item["experience_id"], "name": item["name"], "lat": item["lat"], "lng": item["lng"], "category": item["category"]}
        for item in items
    ]
    return {
        "stats": {
            "total_experiences": wallet.total_experiences,
            "hidden_gem_count": wallet.hidden_gem_count,
            "total_spent_inr": wallet.total_spent_inr,
            "total_duration_min": wallet.total_duration_min,
            "categories": dict(wallet.categories_json or {}),
            "cities": dict(wallet.cities_visited_json or {}),
        },
        "badges": _badge_views(session, user),
        "timeline": items,
        "pins": pins,
    }


def timeline(session: Session, user: User, *, limit: int = 50) -> list[dict[str, Any]]:
    logs, experiences = _load(session, user.id or 0)
    return _timeline(logs[: max(1, limit)], experiences)


def share_summary(
    session: Session, user: User, *, month: str | None = None
) -> dict[str, Any]:
    """A shareable "My [City] Month" summary for a YYYY-MM period (default: all)."""
    logs, experiences = _load(session, user.id or 0)
    if month:
        logs = [
            log
            for log in logs
            if log.completed_at is not None
            and log.completed_at.strftime("%Y-%m") == month
        ]
        experiences = {i: e for i, e in experiences.items() if any(l.experience_id == i for l in logs)}

    stats = _stats(logs, experiences)
    categories: dict[str, int] = {}
    for log in logs:
        experience = experiences.get(log.experience_id)
        if experience is not None:
            categories[experience.category] = categories.get(experience.category, 0) + 1
    top_categories = [c for c, _ in sorted(categories.items(), key=lambda kv: kv[1], reverse=True)[:3]]

    earned_in_period: list[str] = []
    for row in session.exec(select(UserBadge).where(UserBadge.user_id == user.id)).all():
        if month is None or (
            row.earned_at is not None and row.earned_at.strftime("%Y-%m") == month
        ):
            spec = _BADGE_BY_CODE.get(row.badge_code)
            if spec:
                earned_in_period.append(spec["name"])

    highlights = [item["name"] for item in _timeline(logs[:5], experiences)]
    return {
        "period": month or "all-time",
        "total_experiences": stats["total"],
        "hidden_gem_count": stats["hidden_gems"],
        "total_spent_inr": sum(
            experiences[l.experience_id].avg_cost
            for l in logs
            if l.experience_id in experiences
        ),
        "top_categories": top_categories,
        "highlights": highlights,
        "badges": sorted(set(earned_in_period)),
    }
