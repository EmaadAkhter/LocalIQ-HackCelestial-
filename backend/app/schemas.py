"""Pydantic schemas shared across the API.

Two layers live here:
  * Request/response contracts used by the routers.
  * ``Constraints`` / ``ScoreFactors`` / ``ExperienceContext`` value objects used
    by the AI service modules (``parser``, ``guide``, ``explain``).
"""

from __future__ import annotations

from typing import Literal

from pydantic import BaseModel, Field

GroupType = Literal["solo", "couple", "family", "friends"]
ParseSource = Literal["ollama", "heuristic", "llm", "canned"]


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
    created_at: str | None = None


# --------------------------------------------------------------------------
# Auth
# --------------------------------------------------------------------------


class RegisterRequest(BaseModel):
    name: str = Field(..., min_length=2, max_length=80, examples=["Aarav Sharma"])
    email: str = Field(..., min_length=5, max_length=200, examples=["aarav@example.com"])
    password: str = Field(..., min_length=6, max_length=128, examples=["secret123"])

    model_config = {"json_schema_extra": {"example": {"name": "Aarav Sharma", "email": "aarav@example.com", "password": "secret123"}}}


class LoginRequest(BaseModel):
    email: str = Field(..., min_length=5, max_length=200)
    password: str = Field(..., min_length=6, max_length=128)


class UserResponse(BaseModel):
    id: int
    name: str
    email: str
    group_type: str | None = None
    created_at: str

    model_config = {"from_attributes": True}


class TokenResponse(BaseModel):
    access_token: str
    token_type: str = "bearer"
    expires_in: int
    user: UserResponse


# --------------------------------------------------------------------------
# Constraints / Recommendations
# --------------------------------------------------------------------------


class ParsedConstraints(BaseModel):
    location: str | None = None
    time_hours: float | None = None
    budget_inr: int | None = None
    group_type: str | None = None
    interests: list[str] = Field(default_factory=list)
    accessibility: str | None = None
    start_time: str | None = None


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
