"""Constraint extraction: local LLM first, deterministic heuristic fallback."""

from __future__ import annotations

import re
from typing import Any

from pydantic import ValidationError

from app.config import get_settings
from app.schemas import Constraints, ParseResponse
from app.services.llm import LLMError, generate_json

EXTRACTION_SYSTEM_PROMPT = """\
You extract structured trip constraints from a traveller's message.
Return ONLY a JSON object (no markdown, no prose) with exactly these keys:
- "location": string, the city or area mentioned; default "Mumbai"
- "time_hours": hours available as a number; default 2
- "budget_inr": integer budget in Indian rupees; default 1000
- "group_type": one of "solo", "couple", "family", "friends"; default "solo"
- "interests": array drawn from ["food","culture","art","shopping","nightlife","outdoor"]; empty if unknown
- "accessibility": array drawn from ["wheelchair","low_walking","child_friendly"]; empty if none
- "start_time": 24-hour "HH:MM" string if a start time is mentioned, else null
Only use values supported by the message. Never invent details."""

INTEREST_KEYWORDS: dict[str, tuple[str, ...]] = {
    "food": ("food", "eat", "restaurant", "cafe", "street food", "snack", "cuisine", "dinner", "lunch", "breakfast"),
    "culture": ("culture", "cultural", "heritage", "museum", "history", "historic", "temple", "monument"),
    "art": ("art", "gallery", "exhibition", "street art"),
    "shopping": ("shop", "shopping", "market", "bazaar", "mall", "souvenir"),
    "nightlife": ("nightlife", "bar", "pub", "club", "drinks", "night out"),
    "outdoor": ("outdoor", "beach", "park", "walk", "garden", "sunset", "promenade", "marine drive"),
}

GROUP_KEYWORDS: dict[str, tuple[str, ...]] = {
    "family": ("family", "kids", "children", "child"),
    "couple": ("couple", "partner", "date", "romantic", "wife", "husband", "girlfriend", "boyfriend"),
    "friends": ("friends", "buddy", "buddies", "mates", "group of"),
    "solo": ("solo", "alone", "by myself", "just me"),
}

ACCESSIBILITY_KEYWORDS: dict[str, tuple[str, ...]] = {
    "wheelchair": ("wheelchair", "accessible", "accessibility"),
    "low_walking": ("low walking", "less walking", "limited mobility", "not much walking"),
    "child_friendly": ("kid friendly", "child friendly", "kid-friendly", "toddler"),
}

ALLOWED_INTERESTS = {"food", "culture", "art", "shopping", "nightlife", "outdoor"}
INTEREST_SYNONYMS = {
    "heritage": "culture",
    "historic": "culture",
    "history": "culture",
    "museum": "culture",
    "temple": "culture",
    "monument": "culture",
    "restaurant": "food",
    "cafe": "food",
    "street food": "food",
    "market": "shopping",
    "bazaar": "shopping",
    "mall": "shopping",
    "bar": "nightlife",
    "club": "nightlife",
    "beach": "outdoor",
    "park": "outdoor",
    "nature": "outdoor",
    "walk": "outdoor",
    "gallery": "art",
}

ALLOWED_ACCESSIBILITY = {"wheelchair", "low_walking", "child_friendly"}
ACCESSIBILITY_SYNONYMS = {
    "accessible": "wheelchair",
    "wheelchair accessible": "wheelchair",
    "mobility": "low_walking",
    "limited mobility": "low_walking",
    "kids": "child_friendly",
    "kid friendly": "child_friendly",
    "child friendly": "child_friendly",
    "children": "child_friendly",
}

LOCATION_PLACEHOLDERS = {
    "near me",
    "nearby",
    "here",
    "around me",
    "my location",
    "current location",
    "me",
}

KNOWN_AREAS: tuple[str, ...] = (
    "Bandra",
    "Colaba",
    "Andheri",
    "Juhu",
    "Powai",
    "Dadar",
    "Fort",
    "Marine Drive",
    "Worli",
    "Lower Parel",
    "Kala Ghoda",
    "Goregaon",
    "Malad",
    "Chembur",
    "Churchgate",
    "Vashi",
    "Thane",
)

# Pre-written parses for the exact sentences we rehearse on stage.
CANNED_RESPONSES: tuple[tuple[str, Constraints], ...] = (
    (
        "find local food near me for 2 hours under 500",
        Constraints(
            location="Mumbai",
            time_hours=2,
            budget_inr=500,
            group_type="solo",
            interests=["food"],
        ),
    ),
    (
        "heritage walk with my family for 3 hours in bandra",
        Constraints(
            location="Bandra",
            time_hours=3,
            budget_inr=1500,
            group_type="family",
            interests=["culture", "outdoor"],
            accessibility=["child_friendly"],
        ),
    ),
)


def _normalise(text: str) -> str:
    return " ".join(text.lower().split())


def _hour_span(text: str) -> float | None:
    match = re.search(r"(\d+(?:\.\d+)?)\s*(?:hours?|hrs?|h)\b", text)
    if match:
        return float(match.group(1))
    match = re.search(r"(\d+)\s*(?:minutes?|mins?)\b", text)
    if match:
        return round(int(match.group(1)) / 60, 2)
    if "half an hour" in text:
        return 0.5
    if "an hour" in text or "one hour" in text:
        return 1.0
    return None


def _budget(text: str) -> int | None:
    patterns = (
        r"(?:\u20b9|rs\.?|inr)\s*(\d{2,6})",
        r"(\d{2,6})\s*(?:rupees|inr|bucks|rs)\b",
        r"(?:under|below|within|up to|upto|max|maximum|budget of|budget)\s*(?:\u20b9|rs\.?|inr)?\s*(\d{2,6})",
    )
    for pattern in patterns:
        match = re.search(pattern, text)
        if match:
            return int(match.group(1))
    return None


def _group(text: str) -> str | None:
    for group, words in GROUP_KEYWORDS.items():
        if any(word in text for word in words):
            return group
    return None


def _interests(text: str) -> list[str]:
    return [name for name, words in INTEREST_KEYWORDS.items() if any(word in text for word in words)]


def _accessibility(text: str) -> list[str]:
    return [name for name, words in ACCESSIBILITY_KEYWORDS.items() if any(word in text for word in words)]


def _location(text: str) -> str | None:
    for area in KNOWN_AREAS:
        if area.lower() in text:
            return area
    if "mumbai" in text:
        return "Mumbai"
    return None


def _start_time(text: str) -> str | None:
    match = re.search(r"\b(?:at\s*)?(\d{1,2})(?::(\d{2}))?\s*(am|pm)\b", text)
    if match:
        hour = int(match.group(1)) % 12
        if match.group(3) == "pm":
            hour += 12
        return f"{hour:02d}:{match.group(2) or '00'}"
    for word, value in (("morning", "09:00"), ("afternoon", "14:00"), ("evening", "18:00"), ("tonight", "20:00")):
        if word in text:
            return value
    return None


def heuristic_extract(text: str) -> Constraints:
    """Best-effort extraction using rules only. Never raises."""
    normalised = _normalise(text)
    return Constraints(
        location=_location(normalised) or "Mumbai",
        time_hours=_hour_span(normalised) or 2.0,
        budget_inr=_budget(normalised) or 1000,
        group_type=_group(normalised) or "solo",
        interests=_interests(normalised),
        accessibility=_accessibility(normalised),
        start_time=_start_time(normalised),
    )


def _match_canned(text: str) -> Constraints | None:
    normalised = _normalise(text)
    for key, constraints in CANNED_RESPONSES:
        if key in normalised:
            return constraints
    return None


def _clean_location(value: str) -> str | None:
    token = value.strip()
    if not token or token.lower() in LOCATION_PLACEHOLDERS:
        return None
    return token


def _clean_interests(values: list[Any]) -> list[str]:
    cleaned: list[str] = []
    for raw in values:
        token = INTEREST_SYNONYMS.get(str(raw).strip().lower(), str(raw).strip().lower())
        if token in ALLOWED_INTERESTS and token not in cleaned:
            cleaned.append(token)
    return cleaned


def _clean_accessibility(values: list[Any]) -> list[str]:
    cleaned: list[str] = []
    for raw in values:
        token = ACCESSIBILITY_SYNONYMS.get(str(raw).strip().lower(), str(raw).strip().lower())
        if token in ALLOWED_ACCESSIBILITY and token not in cleaned:
            cleaned.append(token)
    return cleaned


def _merge_llm(data: dict[str, Any], base: Constraints) -> Constraints:
    """Overlay LLM values onto the heuristic base, ignoring anything invalid."""
    merged = base.model_dump()

    for field in ("location", "group_type", "start_time"):
        value = data.get(field)
        if isinstance(value, str) and value.strip():
            if field == "location":
                cleaned = _clean_location(value)
                if cleaned:
                    merged[field] = cleaned
            else:
                merged[field] = value.strip()

    time_value = data.get("time_hours")
    if isinstance(time_value, (int, float)) and not isinstance(time_value, bool):
        merged["time_hours"] = float(time_value)

    budget_value = data.get("budget_inr")
    if isinstance(budget_value, (int, float)) and not isinstance(budget_value, bool):
        merged["budget_inr"] = int(budget_value)

    interests = data.get("interests")
    if isinstance(interests, list):
        cleaned_interests = _clean_interests(interests)
        if cleaned_interests:
            merged["interests"] = cleaned_interests

    accessibility = data.get("accessibility")
    if isinstance(accessibility, list):
        cleaned_accessibility = _clean_accessibility(accessibility)
        if cleaned_accessibility:
            merged["accessibility"] = cleaned_accessibility

    try:
        return Constraints(**merged)
    except ValidationError:
        return base


async def parse_constraints(text: str) -> ParseResponse:
    """Parse free text into constraints, preferring the local LLM."""
    settings = get_settings()
    base = heuristic_extract(text)

    if settings.demo_mode:
        canned = _match_canned(text)
        if canned is not None:
            return ParseResponse(constraints=canned, source="canned")

    try:
        data = await generate_json(text, system=EXTRACTION_SYSTEM_PROMPT)
    except LLMError:
        return ParseResponse(constraints=base, source="heuristic")

    return ParseResponse(constraints=_merge_llm(data, base), source="llm")
