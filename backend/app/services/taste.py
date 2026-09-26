"""LocalIQ Taste Profile (PRD 4.6).

Turns explicit statements and implicit behaviour into a *tag -> weight* taste
vector plus a natural-language summary, and exposes scoring helpers used by the
recommender, the three graphs and the companion agent.

The vector is intentionally interpretable: a plain ``{tag_name: weight}`` map
the user can read, edit and reset, rather than an opaque embedding. Matching
across users (U2U) and experiences (U2A) is a cosine over that shared tag space.
"""

from __future__ import annotations

import json
import logging
import math
import re
from functools import lru_cache
from pathlib import Path
from typing import Any

from sqlmodel import Session, select

from app.config import get_settings
from app.models import (
    INTERACTION_WEIGHTS,
    Experience,
    PreferenceSignal,
    User,
    UserActivityInteraction,
)

logger = logging.getLogger(__name__)

_DATA_DIR = Path(__file__).resolve().parent.parent.parent / "data"
_TAXONOMY_PATH = _DATA_DIR / "tag_taxonomy.json"

# Weights are clamped into this range per tag so a single place cannot dominate.
_MIN_WEIGHT = -3.0
_MAX_WEIGHT = 3.0
# Cap the stored vector so it stays readable and cheap to match.
_MAX_TAGS = 40


@lru_cache(maxsize=1)
def _taxonomy_names() -> frozenset[str]:
    """Canonical tag names, used to keep only real tags in the vector."""
    try:
        with open(_TAXONOMY_PATH, encoding="utf-8") as f:
            taxonomy = json.load(f)
        names = {t["name"] for t in taxonomy.get("tags", []) if t.get("name")}
        if names:
            return frozenset(names)
    except Exception as exc:  # pragma: no cover - defensive
        logger.warning("Could not load tag taxonomy for taste profile: %s", exc)
    return frozenset()


def normalize_tag(tag: str) -> str:
    """Canonical underscore form of a tag name."""
    return re.sub(r"[\s-]+", "_", (tag or "").strip().lower())


# ---------------------------------------------------------------------------
# Vector helpers
# ---------------------------------------------------------------------------


def _clamp(value: float) -> float:
    return max(_MIN_WEIGHT, min(_MAX_WEIGHT, value))


def _prune(vector: dict[str, float]) -> dict[str, float]:
    """Keep the strongest tags, drop noise, and round for readability."""
    items = sorted(vector.items(), key=lambda kv: abs(kv[1]), reverse=True)
    kept = {k: round(v, 3) for k, v in items[:_MAX_TAGS] if abs(v) >= 0.05}
    return kept


def apply_tag_weight(vector: dict[str, float], tags: list[str], delta: float) -> dict[str, float]:
    """Return a new vector with ``delta`` applied to each tag."""
    out = dict(vector or {})
    valid = _taxonomy_names()
    for tag in tags or []:
        key = normalize_tag(tag)
        if valid and key not in valid:
            continue
        out[key] = _clamp(out.get(key, 0.0) + delta)
    return _prune(out)


def extract_tags_from_text(text: str) -> dict[str, float]:
    """Best-effort tag extraction from a free-text statement.

    Matches canonical tag names (and their spaced forms) inside the text, which
    makes the deterministic fallback useful without an LLM. Negations such as
    "not into nightlife" flip the sign so dislikes are learned too.
    """
    lowered = (text or "").lower()
    if not lowered.strip():
        return {}
    hits: dict[str, float] = {}
    for name in _taxonomy_names():
        phrase = name.replace("_", " ")
        if len(name) < 3:
            continue
        idx = lowered.find(phrase)
        if idx < 0 and name != phrase:
            idx = lowered.find(name)
        if idx < 0:
            continue
        window = lowered[max(0, idx - 30) : idx]
        negative = bool(re.search(r"\b(not|no|never|avoid|dislike|hate|n't)\b", window))
        hits[name] = -1.0 if negative else 1.0
    return hits


def vector_cosine(a: dict[str, float], b: dict[str, float]) -> float:
    """Cosine similarity over the shared tag space of two taste vectors."""
    if not a or not b:
        return 0.0
    keys = set(a) | set(b)
    dot = sum(a.get(k, 0.0) * b.get(k, 0.0) for k in keys)
    na = math.sqrt(sum(a.get(k, 0.0) ** 2 for k in keys))
    nb = math.sqrt(sum(b.get(k, 0.0) ** 2 for k in keys))
    if na == 0 or nb == 0:
        return 0.0
    return dot / (na * nb)


def experience_taste_score(experience: Experience, vector: dict[str, float]) -> float:
    """Similarity between an experience's tags and a taste vector, in [-1, 1]."""
    if not vector:
        return 0.0
    tags = [normalize_tag(t) for t in (experience.tags or [])]
    if not tags:
        return 0.0
    weights = {t: 1.0 for t in tags}
    return vector_cosine(weights, vector)


# ---------------------------------------------------------------------------
# Summaries
# ---------------------------------------------------------------------------


def _top_tags(vector: dict[str, float], *, positive: bool = True, limit: int = 5) -> list[str]:
    items = [(k, v) for k, v in (vector or {}).items() if (v > 0) == positive]
    items.sort(key=lambda kv: abs(kv[1]), reverse=True)
    return [k.replace("_", " ") for k, _ in items[:limit]]


def summarize_vector(vector: dict[str, float], language: str = "en") -> str:
    """Deterministic natural-language summary (used as an LLM fallback)."""
    likes = _top_tags(vector, positive=True)
    dislikes = _top_tags(vector, positive=False, limit=3)
    if not likes and not dislikes:
        return "We don't know your taste yet. Explore a few experiences and we'll learn."
    parts = []
    if likes:
        parts.append("Likes " + ", ".join(likes))
    if dislikes:
        parts.append("avoids " + ", ".join(dislikes))
    return ". ".join(parts) + "."


async def refresh_taste_text(session: Session, user: User) -> str:
    """Regenerate the LLM taste summary, falling back to a deterministic one.

    Kept separate (and async) so callers control when to spend an LLM call; the
    implicit-signal path only updates the vector, never the summary.
    """
    vector = dict(user.taste_profile_vector or {})
    fallback = summarize_vector(vector, user.preferred_language or "en")
    if get_settings().app_env == "test":
        user.taste_profile_text = fallback
        return fallback
    try:
        from app.services.llm import get_client

        client = get_client()
        if not client.configured:
            user.taste_profile_text = fallback
            return fallback
        prompt = (
            "Write a short, second-person taste summary (max 2 sentences) for a "
            "Mumbai explorer based on these learned preferences. Be concrete and "
            "mention what they like and avoid.\n\n"
            f"Tag weights: {json.dumps(vector, sort_keys=True)}"
        )
        text = await client.generate(prompt, timeout=20.0, num_predict=160, attempts=1)
        user.taste_profile_text = (text or fallback).strip()
        return user.taste_profile_text
    except Exception as exc:  # pragma: no cover - defensive
        logger.warning("Taste summary generation failed: %s", exc)
        user.taste_profile_text = fallback
        return fallback


# ---------------------------------------------------------------------------
# Signals + interactions
# ---------------------------------------------------------------------------


def record_interaction(
    session: Session,
    user: User,
    experience: Experience,
    action: str,
    *,
    metadata: dict[str, Any] | None = None,
) -> dict[str, Any]:
    """Log an interaction and nudge the taste vector. Idempotent-ish and sync.

    Returns the updated taste snapshot so the caller can echo it back.
    """
    action = normalize_tag(action or "view")
    weight = INTERACTION_WEIGHTS.get(action, 0.0)
    tags = [normalize_tag(t) for t in (experience.tags or [])]

    session.add(
        UserActivityInteraction(
            user_id=user.id or 0,
            experience_id=experience.id or 0,
            action=action,
            weight=weight,
            metadata_json=metadata or {},
        )
    )
    # Every interaction is also an implicit taste signal (PRD 4.6).
    user.taste_profile_vector = apply_tag_weight(
        dict(user.taste_profile_vector or {}), tags, weight
    )
    session.add(
        PreferenceSignal(
            user_id=user.id or 0,
            signal_type="implicit",
            experience_id=experience.id,
            text=None,
            weight=weight,
            metadata_json={"action": action, **(metadata or {})},
        )
    )
    if not user.taste_profile_text:
        user.taste_profile_text = summarize_vector(dict(user.taste_profile_vector))
    session.add(user)
    session.commit()
    session.refresh(user)
    return snapshot(user)


def apply_explicit_text(
    session: Session,
    user: User,
    text: str,
    *,
    weight: float = 1.5,
    signal_type: str = "explicit",
) -> dict[str, Any]:
    """Learn from a free-text statement ("I love sunrise walks and coffee")."""
    hits = extract_tags_from_text(text)
    vector = dict(user.taste_profile_vector or {})
    for tag, sign in hits.items():
        vector = apply_tag_weight(vector, [tag], weight * sign)
    user.taste_profile_vector = vector
    session.add(
        PreferenceSignal(
            user_id=user.id or 0,
            signal_type=signal_type,
            text=text[:1000],
            weight=weight,
            metadata_json={"tags": sorted(hits)},
        )
    )
    if not user.taste_profile_text:
        user.taste_profile_text = summarize_vector(vector)
    session.add(user)
    session.commit()
    session.refresh(user)
    return snapshot(user)


def set_manual_vector(session: Session, user: User, vector: dict[str, float]) -> dict[str, Any]:
    """Replace the taste vector from a user edit in the "Your Taste" screen."""
    cleaned: dict[str, float] = {}
    valid = _taxonomy_names()
    for tag, value in (vector or {}).items():
        key = normalize_tag(tag)
        if valid and key not in valid:
            continue
        cleaned[key] = _clamp(float(value))
    user.taste_profile_vector = _prune(cleaned)
    session.add(user)
    session.commit()
    session.refresh(user)
    return snapshot(user)


def snapshot(user: User) -> dict[str, Any]:
    """Serialisable view of a user's taste profile."""
    vector = dict(user.taste_profile_vector or {})
    return {
        "text": user.taste_profile_text or summarize_vector(vector),
        "vector": vector,
        "likes": _top_tags(vector, positive=True),
        "avoids": _top_tags(vector, positive=False, limit=3),
        "personalization_enabled": user.personalization_enabled,
        "preferred_language": user.preferred_language,
    }


def interaction_counts(session: Session, user_id: int) -> dict[str, int]:
    """Count of interactions by action, for the profile screen."""
    rows = session.exec(
        select(UserActivityInteraction).where(UserActivityInteraction.user_id == user_id)
    ).all()
    counts: dict[str, int] = {}
    for row in rows:
        counts[row.action] = counts.get(row.action, 0) + 1
    return counts
