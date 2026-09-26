"""Pydantic schemas shared across the API.

Two layers live here:
  * Request/response contracts used by the routers.
  * ``Constraints`` / ``ScoreFactors`` / ``ExperienceContext`` value objects used
    by the AI service modules (``parser``, ``guide``, ``explain``).
"""

from __future__ import annotations

import re
from datetime import datetime
from typing import Literal

from pydantic import BaseModel, Field, field_validator, model_validator

from app.config import get_settings

GroupType = Literal["solo", "couple", "family", "friends"]
ParseSource = Literal["ollama", "heuristic", "llm", "canned"]


class ErrorResponse(BaseModel):
    """Canonical error payload returned by the API for every failure."""

    error: str
    message: str
    request_id: str = "-"
    path: str = ""
    status_code: int
    details: list = Field(default_factory=list)


# --------------------------------------------------------------------------
# Shared value objects (used by services/parser.py, guide.py, explain.py)
# --------------------------------------------------------------------------


class Constraints(BaseModel):
    """Structured traveller constraints extracted from free text."""

    location: str = "Mumbai"
    time_hours: float = Field(default=2.0, ge=0.5, le=24)
    budget_inr: int = Field(default=1000, ge=0)
    group_type: GroupType = "solo"
    interests: list[str] = Field(default_factory=list)
    accessibility: list[str] = Field(default_factory=list)
    start_time: str | None = None


class ScoreFactors(BaseModel):
    """Per-experience evaluation inputs used to generate 'why this fits' text."""

    interest_matches: list[str] = Field(default_factory=list)
    time_fit: float = Field(default=1.0, ge=0, le=1)
    budget_fit: float = Field(default=1.0, ge=0, le=1)
    distance_km: float | None = None
    travel_minutes: int | None = None
    rating: float | None = None
    open_now: bool | None = None
    setting: Literal["indoor", "outdoor", "either"] | None = None


class ExperienceContext(BaseModel):
    """Minimal experience context used to scope the AI guide chat."""

    id: str | None = None
    name: str
    category: str | None = None
    description: str | None = None
    price_inr: int | None = None
    duration_minutes: int | None = None
    opening_hours: str | None = None
    area: str | None = None
    rating: float | None = None


# --------------------------------------------------------------------------
# Experiences
# --------------------------------------------------------------------------


class ExperienceResponse(BaseModel):
    id: int
    name: str
    category: str
    lat: float
    lng: float
    avg_cost: int
    duration_min: int
    open_time: str
    close_time: str
    rating: float
    description: str
    image_url: str | None = None
    tags: list[str] = Field(default_factory=list)
    accessibility_flags: list[str] = Field(default_factory=list)
    indoor_outdoor: str = "indoor"
    local_gem_score: float = 0.5

    model_config = {"from_attributes": True}

    @model_validator(mode="after")
    def _fill_image_placeholder(self) -> "ExperienceResponse":
        """Guarantee an image so the UI never shows an empty card.

        Curated ``image_url`` values win; otherwise a deterministic placeholder
        is generated from the venue name.
        """
        if not self.image_url:
            template = get_settings().image_placeholder_url_template
            if template:
                slug = re.sub(r"[^a-z0-9]+", "-", self.name.lower()).strip("-")[:40]
                self.image_url = template.format(seed=f"localiq-{slug}")
        return self


class ExperienceListResponse(BaseModel):
    total: int
    items: list[ExperienceResponse]


# --------------------------------------------------------------------------
# Guides
# --------------------------------------------------------------------------


class GuideResponse(BaseModel):
    id: int
    experience_id: int | None = None
    name: str
    photo: str | None = None
    languages: list[str] = Field(default_factory=list)
    specialty: str = ""
    rate_per_hour: int = 0
    rating: float = 0.0

    model_config = {"from_attributes": True}


class GuideRequestPayload(BaseModel):
    name: str | None = Field(default=None, max_length=100)
    date: str | None = Field(default=None, examples=["2026-09-27"])
    hours: int = Field(default=2, ge=1, le=12)
    group_size: int = Field(default=2, ge=1, le=50)
    note: str | None = Field(default=None, max_length=500)


class GuideRequestResponse(BaseModel):
    status: Literal["confirmed_mock", "requested"] = "confirmed_mock"
    guide_id: int
    experience_id: int | None = None
    message: str
    booking_ref: str
    booking_id: int | None = None
    created_at: datetime | None = None


# --------------------------------------------------------------------------
# Auth
# --------------------------------------------------------------------------


class RegisterRequest(BaseModel):
    name: str = Field(..., min_length=2, max_length=80, examples=["Aarav Sharma"])
    email: str = Field(..., min_length=5, max_length=200, examples=["aarav@example.com"])
    password: str = Field(..., min_length=8, max_length=128, examples=["Secret123"])

    model_config = {"json_schema_extra": {"example": {"name": "Aarav Sharma", "email": "aarav@example.com", "password": "Secret123"}}}

    @field_validator("password")
    @classmethod
    def _password_strength(cls, value: str) -> str:
        """Require at least 8 chars with upper, lower and a digit."""
        problems: list[str] = []
        if len(value) < 8:
            problems.append("at least 8 characters")
        if not re.search(r"[A-Z]", value):
            problems.append("an uppercase letter")
        if not re.search(r"[a-z]", value):
            problems.append("a lowercase letter")
        if not re.search(r"\d", value):
            problems.append("a digit")
        if problems:
            raise ValueError("Password must contain " + ", ".join(problems))
        return value


class LoginRequest(BaseModel):
    email: str = Field(..., min_length=5, max_length=200)
    password: str = Field(..., min_length=6, max_length=128)


class UserResponse(BaseModel):
    id: int
    name: str
    email: str
    group_type: str | None = None
    created_at: datetime

    model_config = {"from_attributes": True}


class TokenResponse(BaseModel):
    access_token: str
    token_type: str = "bearer"
    expires_in: int
    user: UserResponse


# --------------------------------------------------------------------------
# Constraints / Recommendations
# --------------------------------------------------------------------------


_NULLISH = {"null", "none", "nil", "n/a", "na", ""}
_KNOWN_GROUPS = {"solo", "couple", "family", "friends"}


class ParsedConstraints(BaseModel):
    location: str | None = None
    time_hours: float | None = None
    budget_inr: int | None = None
    group_type: str | None = None
    interests: list[str] = Field(default_factory=list)
    accessibility: str | None = None
    start_time: str | None = None

    @model_validator(mode="before")
    @classmethod
    def _normalize_llm_output(cls, data: object) -> object:
        """Coerce the loose shapes small models emit.

        Handles string ``"null"``/``"None"``, numeric strings, ``"₹1,500"``,
        comma-separated interests, list accessibility, and group synonyms.
        """
        if not isinstance(data, dict):
            return data

        out: dict = {}
        for key, value in data.items():
            if isinstance(value, str):
                stripped = value.strip()
                value = None if stripped.lower() in _NULLISH else stripped
            out[key] = value

        # Numbers.
        hours = out.get("time_hours")
        if isinstance(hours, str):
            try:
                out["time_hours"] = float(hours)
            except ValueError:
                out["time_hours"] = None
        budget = out.get("budget_inr")
        if isinstance(budget, str):
            digits = re.sub(r"[^\d.]", "", budget)
            try:
                out["budget_inr"] = int(float(digits)) if digits else None
            except ValueError:
                out["budget_inr"] = None

        # Interests: accept "food, art" or a list.
        interests = out.get("interests")
        if interests is None:
            out["interests"] = []
        elif isinstance(interests, str):
            parts = [p.strip().lower() for p in re.split(r"[,/;]", interests) if p.strip()]
            out["interests"] = [p for p in parts if p not in _NULLISH]
        elif isinstance(interests, list):
            cleaned = [str(i).strip().lower() for i in interests if str(i).strip()]
            out["interests"] = [i for i in cleaned if i not in _NULLISH]

        # Group type: only keep a known value.
        group = out.get("group_type")
        if isinstance(group, str):
            group = group.strip().lower()
            out["group_type"] = group if group in _KNOWN_GROUPS else None

        # Accessibility: list -> comma string.
        accessibility = out.get("accessibility")
        if isinstance(accessibility, list):
            out["accessibility"] = ", ".join(str(a) for a in accessibility if a) or None

        # Start time: keep only HH:MM.
        start = out.get("start_time")
        if isinstance(start, str):
            match = re.match(r"^(\d{1,2}):(\d{2})$", start.strip())
            out["start_time"] = f"{int(match.group(1)):02d}:{match.group(2)}" if match else None

        return out


class RecommendationRequest(BaseModel):
    location: str | None = Field(default=None, max_length=100, examples=["Bandra"])
    time_hours: float | None = Field(default=None, ge=0.5, le=24, examples=[4])
    budget_inr: int | None = Field(default=None, ge=0, le=1_000_000, examples=[1500])
    group_type: str | None = Field(default=None, max_length=50, examples=["friends"])
    interests: list[str] = Field(default_factory=list, examples=[["food", "art"]])
    accessibility: str | list[str] | None = Field(default=None, examples=[None])
    start_time: str | None = Field(default=None, examples=["10:00"])
    limit: int = Field(default=10, ge=1, le=30)

    model_config = {
        "json_schema_extra": {
            "example": {
                "location": "Bandra",
                "time_hours": 4,
                "budget_inr": 1500,
                "group_type": "friends",
                "interests": ["food", "art"],
                "accessibility": None,
                "start_time": None,
            }
        }
    }


class RecommendationItem(BaseModel):
    experience: ExperienceResponse
    score: float
    score_parts: dict[str, float] = Field(default_factory=dict)
    distance_km: float
    travel_time_min: int
    total_time_min: int
    estimated_cost: int
    why_this_fits: str


class RecommendationResponse(BaseModel):
    total_candidates: int
    feasible_count: int
    weather_used: bool = False
    weather_summary: str | None = None
    recommendations: list[RecommendationItem]


# --------------------------------------------------------------------------
# Parse
# --------------------------------------------------------------------------


class ParseRequest(BaseModel):
    text: str = Field(
        ...,
        min_length=1,
        max_length=1000,
        examples=["I have 4 hours, ₹1500 and want food and art around Bandra"],
    )


class ParseResponse(BaseModel):
    constraints: ParsedConstraints
    source: ParseSource = "heuristic"


# --------------------------------------------------------------------------
# Chat
# --------------------------------------------------------------------------


class ChatMessage(BaseModel):
    role: Literal["user", "assistant"] = "user"
    content: str = Field(..., max_length=2000)


class ChatRequest(BaseModel):
    experience_id: int | None = Field(default=None)
    experience: ExperienceContext | None = None
    message: str = Field(..., min_length=1, max_length=2000)
    history: list[ChatMessage] = Field(default_factory=list, max_length=10)

    model_config = {
        "json_schema_extra": {"example": {"experience_id": 1, "message": "Is this good for kids?", "history": []}}
    }


class ChatResponse(BaseModel):
    reply: str
    fallback: bool = False
    experience_id: int | None = None
    source: Literal["ollama", "canned"] | None = None


# --------------------------------------------------------------------------
# Weather
# --------------------------------------------------------------------------


class WeatherResponse(BaseModel):
    available: bool
    temp_c: float | None = None
    condition: str = "unknown"
    is_rainy: bool = False
    suitable_outdoor: bool = True
    description: str = ""
