"""Natural-language constraint parser (Ollama strict JSON + heuristic fallback)."""

import logging
import re

from fastapi import APIRouter, Request, Response
from pydantic import ValidationError

from app.config import get_settings
from app.rate_limit import LLM_LIMIT, limiter
from app.schemas import ParsedConstraints, ParseRequest, ParseResponse
from app.services import nugen
from app.services.llm import get_client
from app.services.recommender import KNOWN_AREAS

logger = logging.getLogger(__name__)
router = APIRouter()

INTEREST_KEYWORDS: dict[str, list[str]] = {
    "food": ["food", "eat", "eating", "hungry", "restaurant", "cafe", "dinner", "lunch", "breakfast",
             "chaat", "pani puri", "kebab", "street food", "thali", "misal", "vada pav", "pav bhaji", "biryani"],
    "culture": ["culture", "cultural", "heritage", "history", "historic", "temple", "shrine", "dargah",
                "church", "unesco", "museum", "fort", "old city", "spiritual"],
    "shopping": ["shop", "shopping", "market", "bazaar", "mall", "boutique", "souvenir", "bargain", "antique"],
    "art": ["art", "gallery", "galleries", "museum", "painting", "street art", "mural", "theatre",
            "theater", "music", "performance", "opera", "exhibition", "craft"],
    "nightlife": ["nightlife", "night", "bar", "bars", "pub", "club", "party", "beer", "cocktail",
                  "brewery", "lounge", "late night", "karaoke"],
    "outdoor": ["outdoor", "outside", "beach", "sea", "walk", "walking", "hike", "hiking", "park",
                "garden", "trail", "sunset", "sunrise", "nature", "cycling", "promenade", "lake", "forest"],
}

GROUP_KEYWORDS = ["friends", "family", "couple", "solo", "alone", "kids", "children", "colleagues", "date"]

PARSE_SYSTEM = (
    "You extract trip constraints from a user message. "
    "Output ONLY valid JSON with exactly these keys: "
    '{"location": string|null, "time_hours": number|null, "budget_inr": integer|null, '
    '"group_type": string|null, "interests": string[], "accessibility": string|null, "start_time": string|null}. '
    "location is a Mumbai area like Bandra, Colaba, Juhu. "
    "time_hours is available hours as a number. budget_inr is budget in INR as integer. "
    "interests use only: food, culture, shopping, art, nightlife, outdoor. "
    "group_type is one of solo, couple, family, friends. "
    "start_time is HH:MM 24h. "
    'Use real JSON null (never the string "null") and an empty array when unknown. '
    "No extra text.\n"
    "Examples:\n"
    'Input: "4 hours in Bandra with 1500 rupees for food and art"\n'
    'Output: {"location":"Bandra","time_hours":4,"budget_inr":1500,"group_type":null,'
    '"interests":["food","art"],"accessibility":null,"start_time":null}\n'
    'Input: "wheelchair friendly museum near Colaba tomorrow morning"\n'
    'Output: {"location":"Colaba","time_hours":null,"budget_inr":null,"group_type":null,'
    '"interests":["culture"],"accessibility":"wheelchair-accessible","start_time":"09:00"}\n'
    'Input: "cheap late night street food for 2 hours"\n'
    'Output: {"location":null,"time_hours":2,"budget_inr":null,"group_type":null,'
    '"interests":["food","nightlife"],"accessibility":null,"start_time":null}'
)


def heuristic_parse(text: str) -> ParsedConstraints:
    """Deterministic fallback: extract obvious numbers/areas/interests."""
    low = text.lower()

    # Budget: ₹1,500 / Rs 1500 / INR 1500 / 1500 rupees / "budget 1500".
    budget = None
    candidates: list[int] = []
    for pat in [
        r"₹\s*([\d,]+)",
        r"(?:rs\.?|inr|rupees)\s*([\d,]+)",
        r"([\d,]+)\s*(?:rupees|rs\.?|inr|budget)",
        r"budget\D{0,6}([\d,]+)",
    ]:
        for mm in re.finditer(pat, text, flags=re.IGNORECASE):
            try:
                candidates.append(int(mm.group(1).replace(",", "")))
            except ValueError:
                pass
    valid = [c for c in candidates if 50 <= c <= 1_000_000]
    if valid:
        budget = min(valid)

    # Time: "4 hours", "4 hrs", "4h", "half day", "full day".
    time_hours = None
    m = re.search(r"(\d+(?:\.\d+)?)\s*(?:hours?|hrs?|h\b)", low)
    if m:
        try:
            time_hours = float(m.group(1))
        except ValueError:
            time_hours = None
    elif "full day" in low or "whole day" in low:
        time_hours = 8.0
    elif "half day" in low or "half-day" in low:
        time_hours = 4.0
    if time_hours is not None:
        time_hours = max(0.5, min(24.0, time_hours))

    # Location: known Mumbai areas mentioned verbatim.
    location = None
    for area in sorted(KNOWN_AREAS.keys(), key=len, reverse=True):
        if re.search(rf"\b{re.escape(area)}\b", low):
            display = " ".join(w.capitalize() for w in area.split())
            location = {"Csm t": "CSMT", "Bkc": "BKC", "Mumbai": "Mumbai"}.get(display, display)
            break

    # Interests.
    interests: list[str] = []
    for cat, keywords in INTEREST_KEYWORDS.items():
        if any(k in low for k in keywords):
            interests.append(cat)

    # Group type.
    group_type = None
    for g in GROUP_KEYWORDS:
        if re.search(rf"\b{re.escape(g)}\b", low):
            group_type = {"colleagues": "friends", "alone": "solo", "children": "kids", "date": "couple"}.get(g, g)
            break

    # Start time: "10am", "10:30pm", "10:00", morning/afternoon/evening.
    start_time = None
    m = re.search(r"\b(\d{1,2})(?::(\d{2}))?\s*(am|pm)\b", low)
    if m:
        h = int(m.group(1))
        mi = int(m.group(2) or 0)
        if m.group(3) == "pm" and h < 12:
            h += 12
        if m.group(3) == "am" and h == 12:
            h = 0
        start_time = f"{h:02d}:{mi:02d}"
    else:
        m2 = re.search(r"\b([01]?\d|2[0-3]):([0-5]\d)\b", low)
        if m2:
            start_time = f"{int(m2.group(1)):02d}:{m2.group(2)}"
        elif "morning" in low:
            start_time = "09:00"
        elif "afternoon" in low:
            start_time = "14:00"
        elif "evening" in low:
            start_time = "18:00"
        elif "night" in low:
            start_time = "20:00"

    # Accessibility.
    accessibility = None
    for key in ("wheelchair", "step-free", "step free", "accessible", "stroller", "elevator"):
        if key in low:
            accessibility = "wheelchair-accessible" if ("wheel" in key or "step" in key) else key
            break

    return ParsedConstraints(
        location=location,
        time_hours=time_hours,
        budget_inr=budget,
        group_type=group_type,
        interests=interests,
        accessibility=accessibility,
        start_time=start_time,
    )


@router.post("/parse", response_model=ParseResponse, summary="Parse natural-language constraints")
@limiter.limit(LLM_LIMIT)
async def parse_constraints(request: Request, response: Response, payload: ParseRequest):
    """Try the Nugen aligned model, then Ollama, then the deterministic heuristic."""
    # 0) Nugen domain-aligned model (only when explicitly enabled).
    if nugen.configured():
        try:
            data = await nugen.extract_constraints(payload.text)
            if data:
                constraints = ParsedConstraints.model_validate(
                    nugen.to_parsed_constraints(data)
                )
                return ParseResponse(constraints=constraints, source="nugen")
        except ValidationError as exc:
            logger.warning("Nugen parse failed validation: %s", exc)
        except Exception as exc:  # noqa: BLE001 - defensive
            logger.warning("Nugen parse raised: %s", exc)

    # 1) Ollama attempt.
    try:
        client = get_client()
        data = await client.generate_json(
            f"User message: {payload.text!r}\nExtract constraints as JSON.",
            system=PARSE_SYSTEM,
            timeout=get_settings().llm_parse_timeout_seconds,
        )
        if data:
            try:
                constraints = ParsedConstraints.model_validate(data)
                return ParseResponse(constraints=constraints, source="ollama")
            except ValidationError as exc:
                logger.warning("Ollama parse failed validation: %s", exc)
    except Exception as exc:  # pragma: no cover - defensive
        logger.warning("Ollama parse raised: %s", exc)

    # 2) Heuristic fallback — always succeeds.
    return ParseResponse(constraints=heuristic_parse(payload.text), source="heuristic")
