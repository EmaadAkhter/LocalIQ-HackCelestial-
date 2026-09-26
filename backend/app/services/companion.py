"""LocalIQ Companion / guide agent (PRD 4.7 + 4.10).

Backend-only for now. The agent:
  * extracts structured constraints from natural language (English/Hindi/Marathi
    are handled by the model; the deterministic fallback handles common English),
  * asks a clarifying question when it cannot plan yet,
  * recommends through the taste-aware reranker, and
  * acts as a location guide when the user names an experience.

Every LLM call degrades to a deterministic response, so the agent works with no
Ollama running (tests, offline demo).
"""

from __future__ import annotations

import json
import logging
import re
from typing import Any

from app.api.v1.parse import heuristic_parse
from app.config import get_settings
from app.services.llm import get_client

logger = logging.getLogger(__name__)

#: Fields the agent tries to fill before it can plan.
_PLAN_FIELDS = ("time_hours", "budget_inr", "location")

_RECOMMEND_HINTS = (
    "recommend",
    "suggest",
    "what should",
    "what can",
    "show me",
    "where should",
    "plan",
    "kya kar",
    "kahan",
    "batao",
    "ideas",
    "things to do",
)


def _looks_like_request(message: str) -> bool:
    low = message.lower()
    return any(h in low for h in _RECOMMEND_HINTS)


def llm_ready() -> bool:
    """True when a local LLM should be used (never in tests)."""
    return get_settings().app_env != "test" and get_client().configured


def merge_constraints(state: dict[str, Any], new: dict[str, Any]) -> dict[str, Any]:
    """Merge newly extracted constraints into session state (new wins if set)."""
    out = dict(state or {})
    for key, value in (new or {}).items():
        if value in (None, "", [], {}):
            continue
        out[key] = value
    return out


def _heuristic_constraints(message: str) -> dict[str, Any]:
    parsed = heuristic_parse(message)
    data = parsed.model_dump(exclude_none=True)
    return {k: v for k, v in data.items() if v not in (None, "", [])}


async def extract_constraints(message: str, history: list[dict[str, Any]] | None = None) -> dict[str, Any]:
    """Extract constraints + intent from a user message.

    Returns a dict with any of ``location, time_hours, budget_inr, interests,
    start_time, accessibility, language, wants_recommendations``.
    """
    heuristic = _heuristic_constraints(message)
    heuristic["wants_recommendations"] = _looks_like_request(message) or bool(heuristic)

    if not llm_ready():
        return heuristic
    client = get_client()

    recent = "\n".join(
        f"{m.get('role')}: {m.get('content')}" for m in (history or [])[-6:]
    )
    prompt = f"""Extract the traveller's constraints from the latest message.

Return JSON with any of these keys (omit unknown ones):
  "location" (string), "time_hours" (number), "budget_inr" (integer),
  "interests" (list of short tags), "start_time" ("HH:MM"),
  "accessibility" (string), "language" ("en"|"hi"|"mr"),
  "wants_recommendations" (boolean), "question_about" (string).

Conversation so far:
{recent or "(new conversation)"}

Latest message: {message}
"""
    try:
        data = await client.generate_json(prompt, timeout=15.0, num_predict=220, attempts=1)
    except Exception as exc:  # pragma: no cover - defensive
        logger.warning("Agent constraint extraction failed: %s", exc)
        return heuristic
    if not isinstance(data, dict):
        return heuristic
    # LLM wins for keys it returns; heuristic fills the gaps.
    merged = dict(heuristic)
    for key, value in data.items():
        if value not in (None, "", [], {}):
            merged[key] = value
    return merged


def next_question(state: dict[str, Any], language: str = "en") -> str | None:
    """The one clarifying question to ask next, or None when ready to plan."""
    if state.get("time_hours") is None:
        return "How much time do you have today?"
    if state.get("location") is None:
        return "Which part of Mumbai are you in (or heading to)?"
    if state.get("budget_inr") is None and not state.get("budget_skipped"):
        return "Roughly what's your budget per person? (or say 'any')"
    return None


def compose_fallback_reply(
    state: dict[str, Any],
    recommendations: list[dict[str, Any]],
    *,
    language: str = "en",
    question: str | None = None,
) -> str:
    """Deterministic reply used when the LLM is unavailable."""
    if question:
        return question
    if not recommendations:
        return (
            "I couldn't find a good fit for those constraints — try widening the "
            "time window or budget and I'll look again."
        )
    top = recommendations[:3]
    names = ", ".join(r["experience"].name for r in top)
    reason = ""
    for r in top:
        if r.get("why"):
            reason = r["why"][0]
            break
    tail = f" {reason}." if reason else ""
    return f"Here are {len(top)} picks for right now: {names}.{tail}"


async def compose_reply(
    state: dict[str, Any],
    recommendations: list[dict[str, Any]],
    *,
    language: str = "en",
    question: str | None = None,
    taste_text: str | None = None,
) -> str:
    """Natural-language reply. LLM when available, deterministic otherwise."""
    if question:
        return question
    fallback = compose_fallback_reply(state, recommendations, language=language)
    if not llm_ready() or not recommendations:
        return fallback
    client = get_client()
    listing = "\n".join(
        f"- {r['experience'].name} ({r['experience'].category}, ₹{r['experience'].avg_cost}, "
        f"{r['travel_time_min']} min away): {'; '.join(r.get('why') or [])}"
        for r in recommendations[:5]
    )
    prompt = f"""You are LocalIQ, a warm Mumbai local-guide assistant. Reply in
language code "{language}" in 2-3 sentences. Recommend the best 2-3 options and
say briefly why. Do not invent places beyond the list.

User's taste: {taste_text or "unknown"}
Constraints: {json.dumps(state, ensure_ascii=False)}
Options:
{listing}
"""
    try:
        text = await client.generate(prompt, timeout=25.0, num_predict=220, attempts=1)
        return (text or fallback).strip()
    except Exception as exc:  # pragma: no cover - defensive
        logger.warning("Agent reply generation failed: %s", exc)
        return fallback


_GUIDE_FALLBACK_TEMPLATES = {
    "history": "This place has layers of history — look for the oldest inscription or plaque, most visitors walk right past it.",
    "photo": "Best light is early morning or golden hour; the classic angle is from the far corner looking back.",
    "food": "There's a well-known snack stall just outside — ask for the local speciality, not the tourist menu.",
    "tip": "Go early to beat the crowds, carry water, and keep some cash for the small vendors.",
}


async def compose_guide_tips(
    experience_name: str,
    *,
    category: str = "",
    description: str = "",
    language: str = "en",
) -> list[str]:
    """Location-triggered tips for in-experience guidance (PRD 4.10)."""
    fallback = [
        f"At {experience_name}: {_GUIDE_FALLBACK_TEMPLATES['history']}",
        _GUIDE_FALLBACK_TEMPLATES["photo"],
        _GUIDE_FALLBACK_TEMPLATES["food"],
        _GUIDE_FALLBACK_TEMPLATES["tip"],
    ]
    if not llm_ready():
        return fallback
    client = get_client()
    prompt = f"""Give exactly 3 concise, practical tips for someone visiting
"{experience_name}" ({category}) in Mumbai. One history/culture tip, one photo
tip, one food-or-logistics tip. Reply in language code "{language}". Return
JSON: {{"tips": ["...", "...", "..."]}}.

Context: {description[:600]}
"""
    try:
        data = await client.generate_json(prompt, timeout=20.0, num_predict=260, attempts=1)
        tips = data.get("tips") if isinstance(data, dict) else None
        if isinstance(tips, list) and tips:
            return [str(t).strip() for t in tips if str(t).strip()][:5]
    except Exception as exc:  # pragma: no cover - defensive
        logger.warning("Guide tip generation failed: %s", exc)
    return fallback


def detect_language(message: str, default: str = "en") -> str:
    """Very rough script-based language hint (Devanagari => hi/mr)."""
    if re.search(r"[\u0900-\u097F]", message or ""):
        return "hi"
    return default


settings = get_settings()
