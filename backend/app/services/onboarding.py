"""Guided onboarding.

**User flow** (``kind="user"``) — a short, warm conversation in the voice of a
seasoned maître d'. Each answer maps onto real tags from ``data/tag_taxonomy.json``
and is folded straight into the user's taste vector, so recommendations improve
from the very first session. The copy is deliberate: unhurried, specific, a
little theatrical. The LLM is not required — the script is complete on its own.

**Guide flow** is a separate, form-based path (see ``app.api.v1.guide_onboarding``)
because guides want speed, not poetry.
"""

from __future__ import annotations

import logging
from datetime import datetime, timezone
from typing import Any

from sqlmodel import Session, select

from app.models import OnboardingSession, PreferenceSignal, User
from app.services import taste

logger = logging.getLogger(__name__)

#: The taste conversation. Order is the running order.
USER_STEPS: list[dict[str, Any]] = [
    {
        "key": "familiarity",
        "prompt": (
            "Good evening — I'll be looking after you. Tell me, is this your "
            "first time in Mumbai, or do you know her already?"
        ),
        "ack": "Noted.",
        "options": [
            {"label": "First time", "tags": {}},
            {"label": "I know her well", "tags": {"local_favorite": 0.6, "hidden_gem": 0.6, "local": 0.5}},
            {"label": "Somewhere in between", "tags": {"local": 0.3}},
        ],
    },
    {
        "key": "company",
        "prompt": "And who has the pleasure of your company this evening?",
        "ack": "A fine choice.",
        "options": [
            {"label": "Just me", "tags": {"solo_friendly": 1.0, "quiet_retreat": 0.4}},
            {"label": "Someone special", "tags": {"couple_friendly": 1.0, "romantic": 1.0, "good_for_dates": 0.9}},
            {"label": "A few friends", "tags": {"group_friendly": 1.0, "good_for_friends": 1.0, "nightlife": 0.5}},
            {"label": "Family", "tags": {"family_friendly": 1.0, "child_friendly": 0.5, "elderly_friendly": 0.3}},
        ],
    },
    {
        "key": "palate",
        "prompt": (
            "Now the part I enjoy most. What should be on the table? Choose as "
            "many as tempt you."
        ),
        "ack": "Excellent taste.",
        "multi": True,
        "options": [
            {"label": "Street food", "tags": {"street_food": 1.2, "good_for_street_food": 1.0, "chaat": 0.6}},
            {"label": "Fine dining", "tags": {"good_for_fine_dining": 1.2, "premium": 0.7, "mid_range": 0.2}},
            {"label": "Cocktails", "tags": {"cocktails": 1.2, "bars": 0.8, "lounge": 0.5}},
            {"label": "Coffee & desserts", "tags": {"cafe": 1.2, "good_for_coffee": 1.0, "cafe_hopping": 0.6}},
            {"label": "Seafood", "tags": {"seafood": 1.2, "non_veg": 0.4}},
            {"label": "Vegetarian", "tags": {"vegetarian": 1.2}},
            {"label": "Sweets", "tags": {"snacks": 0.9, "good_for_evening_snacks": 0.5}},
        ],
    },
    {
        "key": "pace",
        "prompt": (
            "How do you like to move through a city — lingering over a long "
            "table, or brisk and packed?"
        ),
        "ack": "Understood.",
        "options": [
            {"label": "Slow and lingering", "tags": {"chill": 1.0, "quiet_retreat": 0.5, "peaceful": 0.5}},
            {"label": "Brisk and packed", "tags": {"energetic": 1.0, "high_footfall_area": 0.4}},
            {"label": "One perfect stop", "tags": {"quiet_retreat": 0.6, "chill": 0.6}},
        ],
    },
    {
        "key": "hour",
        "prompt": "And the hour that suits you best?",
        "ack": "Beautiful.",
        "options": [
            {"label": "Sunrise", "tags": {"sunrise": 1.2, "sunrise_view": 1.0, "early_morning_friendly": 1.0, "good_for_morning_walk": 0.8}},
            {"label": "Golden hour", "tags": {"sunset": 1.2, "sunset_view": 1.0, "good_for_photos": 0.8, "photography": 0.5}},
            {"label": "After dark", "tags": {"nightlife": 1.2, "night_view": 1.0, "open_late": 0.8, "late_night": 0.6}},
        ],
    },
    {
        "key": "avoid",
        "prompt": (
            "Is there anything you'd rather I keep off the menu? Allergies, "
            "dislikes, anything at all."
        ),
        "ack": "I'll keep it away.",
        "free_text": True,
        "negative": True,
    },
    {
        "key": "notes",
        "prompt": (
            "Last thing — tell me anything else worth remembering about you. Then "
            "your first recommendations will be waiting."
        ),
        "ack": "Splendid.",
        "free_text": True,
    },
]

_TOTAL = len(USER_STEPS)


def _now() -> datetime:
    return datetime.now(timezone.utc)


def _step_payload(onboarding: OnboardingSession, *, ack: str | None = None) -> dict[str, Any]:
    step = USER_STEPS[min(onboarding.step, _TOTAL - 1)]
    done = onboarding.step >= _TOTAL
    return {
        "session_id": onboarding.id,
        "status": onboarding.status,
        "step": onboarding.step,
        "total_steps": _TOTAL,
        "progress": round(min(onboarding.step, _TOTAL) / _TOTAL, 3),
        "ack": ack,
        "prompt": None if done else step["prompt"],
        "options": [] if done else [o["label"] for o in step.get("options", [])],
        "multi": bool(step.get("multi")) and not done,
        "free_text": bool(step.get("free_text")) and not done,
        "done": done,
    }


def _abandon_in_progress(session: Session, user_id: int, kind: str = "user") -> None:
    rows = session.exec(
        select(OnboardingSession).where(
            OnboardingSession.user_id == user_id,
            OnboardingSession.kind == kind,
            OnboardingSession.status == "in_progress",
        )
    ).all()
    for row in rows:
        row.status = "abandoned"
        session.add(row)
    if rows:
        session.commit()


def _latest(session: Session, user_id: int, kind: str = "user") -> OnboardingSession | None:
    return session.exec(
        select(OnboardingSession)
        .where(OnboardingSession.user_id == user_id, OnboardingSession.kind == kind)
        .order_by(OnboardingSession.id.desc())
    ).first()


def start_user_onboarding(
    session: Session, user: User, *, language: str = "en", restart: bool = False
) -> dict[str, Any]:
    """Begin (or resume) the taste conversation."""
    existing = _latest(session, user.id or 0)
    if existing is not None and existing.status == "in_progress" and not restart:
        return _step_payload(existing)
    if restart:
        _abandon_in_progress(session, user.id or 0)

    onboarding = OnboardingSession(
        user_id=user.id or 0,
        kind="user",
        status="in_progress",
        step=0,
        language=language,
        messages_json=[{"role": "host", "text": USER_STEPS[0]["prompt"]}],
    )
    session.add(onboarding)
    session.commit()
    session.refresh(onboarding)
    return _step_payload(onboarding)


def _tags_from_answer(
    step: dict[str, Any], message: str | None, selections: list[str] | None
) -> tuple[dict[str, float], str]:
    """Resolve the tags for one answer (quick replies win, then free text)."""
    tags: dict[str, float] = {}
    chosen = {s.strip().lower() for s in (selections or [])}
    for option in step.get("options", []):
        if option["label"].strip().lower() in chosen:
            for tag, weight in option["tags"].items():
                tags[tag] = tags.get(tag, 0.0) + float(weight)

    text = (message or "").strip()
    if text and (step.get("free_text") or not tags):
        extracted = taste.extract_tags_from_text(text)
        weight = 1.4 if step.get("negative") else 1.2
        for tag, value in extracted.items():
            # On an "avoid" step every tag is a dislike, whether or not the
            # sentence itself contains a negation word.
            if step.get("negative"):
                signed = -1.0
            else:
                signed = 1.0 if value > 0 else -1.0
            tags[tag] = tags.get(tag, 0.0) + weight * signed
    return tags, text


def _apply_answer(
    session: Session, user: User, step: dict[str, Any], tags: dict[str, float], text: str
) -> None:
    if tags:
        vector = dict(user.taste_profile_vector or {})
        for tag, weight in tags.items():
            vector = taste.apply_tag_weight(vector, [tag], weight)
        user.taste_profile_vector = vector
        session.add(user)
    session.add(
        PreferenceSignal(
            user_id=user.id or 0,
            signal_type="onboarding",
            text=text[:1000] if text else None,
            weight=1.0,
            metadata_json={"step": step["key"], "tags": tags},
        )
    )
    if not user.taste_profile_text:
        user.taste_profile_text = taste.summarize_vector(dict(user.taste_profile_vector or {}))
        session.add(user)
    session.commit()
    session.refresh(user)


async def answer_user_onboarding(
    session: Session,
    user: User,
    session_id: int,
    *,
    message: str | None = None,
    selections: list[str] | None = None,
) -> dict[str, Any]:
    """Record one answer, learn from it, and return the next prompt (or finish)."""
    onboarding = session.get(OnboardingSession, session_id)
    if onboarding is None or onboarding.user_id != user.id or onboarding.kind != "user":
        raise LookupError("onboarding session not found")
    if onboarding.status != "in_progress":
        return _step_payload(onboarding)

    step = USER_STEPS[min(onboarding.step, _TOTAL - 1)]
    tags, text = _tags_from_answer(step, message, selections)

    answers = dict(onboarding.answers_json or {})
    answers[step["key"]] = {
        "message": text,
        "selections": list(selections or []),
        "tags": tags,
    }
    onboarding.answers_json = answers
    extracted = dict(onboarding.extracted_json or {})
    for tag, weight in tags.items():
        extracted[tag] = round(extracted.get(tag, 0.0) + weight, 3)
    onboarding.extracted_json = extracted

    transcript = list(onboarding.messages_json or [])
    if text or selections:
        transcript.append(
            {"role": "guest", "text": text or ", ".join(selections or [])}
        )
    onboarding.step = min(onboarding.step + 1, _TOTAL)

    if onboarding.step < _TOTAL:
        next_prompt = USER_STEPS[onboarding.step]["prompt"]
        transcript.append({"role": "host", "text": next_prompt})
    onboarding.messages_json = transcript
    session.add(onboarding)
    session.commit()

    _apply_answer(session, user, step, tags, text)

    if onboarding.step >= _TOTAL:
        onboarding.status = "completed"
        onboarding.completed_at = _now()
        session.add(onboarding)
        session.commit()
        session.refresh(onboarding)
        await taste.refresh_taste_text(session, user)
        session.add(user)
        session.commit()
        session.refresh(user)
        payload = _step_payload(onboarding, ack=step.get("ack"))
        payload["taste"] = taste.snapshot(user)
        return payload

    session.refresh(onboarding)
    return _step_payload(onboarding, ack=step.get("ack"))


def user_status(session: Session, user: User) -> dict[str, Any]:
    """Current state of the taste conversation for a user."""
    onboarding = _latest(session, user.id or 0)
    if onboarding is None:
        return {
            "status": "not_started",
            "completed": False,
            "step": 0,
            "total_steps": _TOTAL,
            "taste": taste.snapshot(user),
        }
    payload = _step_payload(onboarding)
    payload["completed"] = onboarding.status == "completed"
    payload["taste"] = taste.snapshot(user)
    return payload


def user_onboarding_completed(session: Session, user_id: int) -> bool:
    row = _latest(session, user_id)
    return bool(row is not None and row.status == "completed")
