"""Nugen domain-aligned model client.

LocalIQ aligns one Nugen model (base: ``llama-v3p2-3b-reasoning``) on two tasks:

  * ``extract_constraints`` — free text (English / Hinglish / code-mixed) into
    strict JSON.
  * ``explain`` — a 2-4 line, feasibility-aware "why this fits" in LocalIQ's
    house style.

The integration is **off by default**: it only runs when ``NUGEN_ENABLED=true``
and ``NUGEN_MODEL_ID`` is set. Every call returns ``None`` on any failure, so
callers fall back to the existing Ollama/heuristic path and the app never
regresses.

Aligned models are served by the same OpenAI-shaped chat endpoint as base
models; the only difference is the ``model`` id. Nugen also returns a
``confidence_score`` (0-100) from inference-time alignment.
"""

from __future__ import annotations

import json
import logging
from typing import Any

import httpx

from app.config import get_settings

logger = logging.getLogger(__name__)

_TIMEOUT_CONNECT = 10.0


def configured() -> bool:
    settings = get_settings()
    return bool(
        settings.nugen_enabled
        and settings.nugen_api_key
        and settings.nugen_model_id
    )


def _headers(api_key: str) -> dict[str, str]:
    return {
        "Authorization": f"Bearer {api_key}",
        "Content-Type": "application/json",
    }


async def _chat(
    messages: list[dict[str, Any]],
    *,
    max_tokens: int = 320,
    temperature: float = 0.2,
) -> dict[str, Any] | None:
    """One chat completion against the aligned model. Returns the message dict."""
    settings = get_settings()
    if not configured():
        return None

    payload = {
        "model": settings.nugen_model_id,
        "messages": messages,
        "max_tokens": max_tokens,
        "temperature": temperature,
    }
    try:
        async with httpx.AsyncClient(
            timeout=httpx.Timeout(settings.nugen_timeout_seconds, connect=_TIMEOUT_CONNECT)
        ) as client:
            resp = await client.post(
                f"{settings.nugen_base_url}/api/v3/inference/chat/completions",
                headers=_headers(settings.nugen_api_key),
                json=payload,
            )
            resp.raise_for_status()
            data = resp.json()
    except Exception as exc:  # noqa: BLE001
        logger.warning("Nugen inference failed: %s", exc)
        return None

    choices = data.get("choices") or []
    if not choices:
        return None
    message = choices[0].get("message") or {}
    message["_confidence_score"] = data.get("confidence_score")
    return message


def _strip_code_fence(text: str) -> str:
    text = text.strip()
    if text.startswith("```"):
        text = text.split("\n", 1)[-1]
        if text.endswith("```"):
            text = text[:-3]
    return text.strip()


async def extract_constraints(text: str) -> dict[str, Any] | None:
    """Strict-JSON constraint extraction. ``None`` on any failure."""
    message = await _chat(
        [
            {
                "role": "system",
                "content": (
                    "You are LocalIQ's constraint extractor for Mumbai local "
                    "discovery. Return ONLY a JSON object with keys: location, "
                    "time_minutes, budget_inr, interests, preferences. Omit any "
                    "field the user did not state. Never invent a location or a "
                    "budget."
                ),
            },
            {"role": "user", "content": text},
        ],
        max_tokens=256,
        temperature=0.0,
    )
    if not message:
        return None
    raw = _strip_code_fence(message.get("content") or "")
    try:
        data = json.loads(raw)
    except json.JSONDecodeError:
        logger.warning("Nugen returned non-JSON constraints: %s", raw[:200])
        return None
    return data if isinstance(data, dict) else None


async def explain(
    experience: dict[str, Any],
    constraints: dict[str, Any],
    context: dict[str, Any] | None = None,
) -> str | None:
    """House-style explanation for one recommendation. ``None`` on failure."""
    payload = {
        "experience": experience,
        "constraints": constraints,
        "context": context or {},
    }
    message = await _chat(
        [
            {
                "role": "system",
                "content": (
                    "You are LocalIQ's explanation writer. Given one experience, "
                    "the traveller's constraints and the weather context, write "
                    "2-4 concise lines in LocalIQ's house style. Always reference "
                    "time fit, cost fit, and how it matches a stated preference or "
                    "the weather. Be honest about trade-offs when budget or time "
                    "is tight. No filler, no emoji."
                ),
            },
            {"role": "user", "content": json.dumps(payload, ensure_ascii=False)},
        ],
        max_tokens=220,
        temperature=0.4,
    )
    if not message:
        return None
    text = (message.get("content") or "").strip()
    return text or None


# ---------------------------------------------------------------------------
# Schema bridge
# ---------------------------------------------------------------------------

_INTEREST_MAP = {
    "history": "culture",
    "heritage": "culture",
    "local life": "culture",
    "nature": "outdoor",
    "adventure": "outdoor",
    "wellness": "outdoor",
}
_ALLOWED_INTERESTS = {"food", "culture", "shopping", "art", "nightlife", "outdoor"}
_ACCESSIBILITY_HINTS = {
    "accessible": "wheelchair-accessible",
    "wheelchair": "wheelchair-accessible",
    "step-free": "wheelchair-accessible",
    "low walking": "low-walking",
    "stroller": "stroller-friendly",
}


def to_parsed_constraints(data: dict[str, Any]) -> dict[str, Any]:
    """Map the Nugen schema onto LocalIQ's existing ``ParsedConstraints``.

    Keeps the API contract identical, so this is a drop-in swap.
    """
    interests: list[str] = []
    for item in data.get("interests") or []:
        mapped = _INTEREST_MAP.get(str(item).lower(), str(item).lower())
        if mapped in _ALLOWED_INTERESTS and mapped not in interests:
            interests.append(mapped)

    accessibility = None
    for pref in data.get("preferences") or []:
        key = str(pref).lower()
        if key in _ACCESSIBILITY_HINTS:
            accessibility = _ACCESSIBILITY_HINTS[key]
            break

    minutes = data.get("time_minutes")
    time_hours = round(minutes / 60.0, 2) if isinstance(minutes, (int, float)) else None

    return {
        "location": data.get("location"),
        "time_hours": time_hours,
        "budget_inr": data.get("budget_inr"),
        "group_type": data.get("group_type"),
        "interests": interests,
        "accessibility": accessibility,
        "start_time": data.get("start_time"),
    }
