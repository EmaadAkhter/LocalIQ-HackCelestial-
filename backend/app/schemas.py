"""Pydantic schemas shared across the API.

Two layers live here:
  * Request/response contracts used by the routers.
  * ``Constraints`` / ``ScoreFactors`` / ``ExperienceContext`` value objects used
    by the AI service modules (``parser``, ``guide``, ``explain``).
"""

from __future__ import annotations

import enum
import re
from datetime import datetime
from typing import Any, Literal

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
# Shared value objects (used by the ranking/AI service layer)
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

    # Semantic + DNA fields
    vibe_vector: dict[str, Any] = Field(default_factory=dict)
    accessibility_score: float = 0.0
    authenticity_score: float = 0.0
    safety_score: float = 0.0
    crowd_density_level: str = "MEDIUM"
    noise_level: str = "MODERATE"
    best_visit_time: str | None = None
    time_to_spend: str | None = None

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


class GuidePackageStopBase(BaseModel):
    experience_id: int | None = None
    sequence: int = 0
    segment_type: str = "experience"
    location_name: str | None = None
    lat: float | None = None
    lng: float | None = None
    duration_min: int = 60
    note: str | None = None


class GuidePackageStopCreate(GuidePackageStopBase):
    pass


class GuidePackageStopResponse(GuidePackageStopBase):
    id: int
    package_id: int

    model_config = {"from_attributes": True}


class GuidePackageBase(BaseModel):
    title: str = Field(..., min_length=3, max_length=200)
    description: str | None = Field(default=None, max_length=2000)
    pickup_type: str = "fixed_point"
    default_pickup_area: str | None = Field(default=None, max_length=200)
    pickup_lat: float | None = None
    pickup_lng: float | None = None
    drop_off_same_as_pickup: bool = True
    max_pickup_distance_km: float = 10.0
    total_duration_hours: float = 3.0
    inclusions: list[str] = Field(default_factory=list)
    price_per_person: int = 0
    total_price: int | None = None
    max_group_size: int = 6
    languages: list[str] = Field(default_factory=list)
    cancellation_policy: str | None = Field(default=None, max_length=1000)
    is_active: bool = True


class GuidePackageCreate(GuidePackageBase):
    stops: list[GuidePackageStopCreate] = Field(default_factory=list)


class GuidePackageResponse(GuidePackageBase):
    id: int
    guide_id: int
    stops: list[GuidePackageStopResponse] = Field(default_factory=list)
    created_at: datetime | None = None
    updated_at: datetime | None = None

    model_config = {"from_attributes": True}


class GuideAvailabilityBase(BaseModel):
    available_date: datetime | None = Field(default=None, examples=["2026-09-27"])
    start_time: str = Field(default="09:00", max_length=5)
    end_time: str = Field(default="18:00", max_length=5)
    is_available: bool = True


class GuideAvailabilityCreate(BaseModel):
    available_date: str = Field(..., examples=["2026-09-27"])
    start_time: str = Field(default="09:00", max_length=5)
    end_time: str = Field(default="18:00", max_length=5)
    is_available: bool = True


class GuideAvailabilityResponse(GuideAvailabilityBase):
    id: int
    guide_id: int

    model_config = {"from_attributes": True}


class GuideBookingStatus(str, enum.Enum):
    PENDING = "pending"
    CONFIRMED = "confirmed"
    CANCELLED = "cancelled"
    COMPLETED = "completed"


class GuideBookingCreate(BaseModel):
    package_id: int
    date: str = Field(..., examples=["2026-09-27"])
    start_time: str | None = None
    group_size: int = Field(default=2, ge=1, le=50)
    pickup_address: str | None = Field(default=None, max_length=500)
    note: str | None = Field(default=None, max_length=500)


class GuideBookingResponse(GuideBookingCreate):
    id: int
    status: GuideBookingStatus
    booking_ref: str
    created_at: datetime | None = None

    model_config = {"from_attributes": True}


class GuideReviewCreate(BaseModel):
    booking_id: int
    rating: float = Field(..., ge=0.0, le=5.0)
    review_text: str | None = Field(default=None, max_length=2000)


class GuideReviewResponse(BaseModel):
    id: int
    booking_id: int
    guide_id: int
    package_id: int | None = None
    user_id: int | None = None
    rating: float
    review_text: str | None = None
    created_at: datetime | None = None

    model_config = {"from_attributes": True}


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
    origin_lat: float | None = Field(
        default=None,
        ge=-90,
        le=90,
        description="Explicit origin. Falls back to the area anchor for `location`.",
    )
    origin_lng: float | None = Field(default=None, ge=-180, le=180)
    travel_mode: str = Field(
        default="WALK",
        description="Travel mode for the Routes API: WALK, DRIVE, BICYCLE or TRANSIT.",
    )
    include_route: bool = Field(
        default=True,
        description="Enrich each result with Google route metrics when a server key exists.",
    )
    use_semantic: bool = Field(
        default=False,
        description="Use vector semantic search from free-text intent instead of keyword interest matching.",
    )
    semantic_query: str | None = Field(
        default=None,
        max_length=500,
        description="Optional free-text intent for semantic retrieval. Falls back to interests/location description.",
    )
    required_tags: list[str] = Field(default_factory=list, description="Hard-required tags.")
    excluded_tags: list[str] = Field(default_factory=list, description="Excluded tags.")

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



# ---------------------------------------------------------------------------
# Route / weather / opening-hours blocks (used by recommendation + detail)
# --------------------------------------------------------------------------

# Route data (Google Routes API, normalized)
# --------------------------------------------------------------------------


class RouteInfo(BaseModel):
    """Travel metrics for one recommendation."""

    distance_m: int = 0
    duration_s: int = 0
    duration_min: int = 0
    polyline: str | None = None
    travel_mode: str = "WALK"
    source: str = Field(
        default="local", description="'google_routes' or 'local' (Haversine estimate)."
    )


class WeatherContext(BaseModel):
    """Compact weather block embedded in recommendation responses."""

    available: bool = False
    temp_c: float | None = None
    condition: str = "unknown"
    is_rainy: bool = False
    suitable_outdoor: bool = True
    description: str = ""


class OpeningHoursInfo(BaseModel):
    """Frontend-ready opening hours (already evaluated against the visit window)."""

    open_time: str | None = None
    close_time: str | None = None
    is_open: bool = True
    label: str = "Open"


class ExperienceDetailResponse(BaseModel):
    """Detail payload: the experience plus distance, hours, weather and route."""

    experience: ExperienceResponse
    distance_km: float = 0.0
    travel_time_min: int = 0
    total_time_min: int = 0
    opening_hours: OpeningHoursInfo = Field(default_factory=OpeningHoursInfo)
    weather: WeatherContext = Field(default_factory=WeatherContext)
    route: RouteInfo = Field(default_factory=RouteInfo)


class RecommendationItem(BaseModel):
    """One ranked place with everything a client needs to render a card.

    All recommendation logic lives in the backend; the client only renders.
    """

    # Identity + basics
    id: int
    name: str
    category: str
    image: str | None = Field(
        default=None,
        description="Photo URL (LocalIQ proxy or dataset). Null lets the client draw a placeholder.",
    )
    description: str = ""

    # Location
    lat: float
    lng: float
    area: str = ""

    # Money + reputation
    cost: int = Field(default=0, description="Estimated spend per person, INR.")
    estimated_cost: int = Field(
        default=0,
        description="Alias of `cost`, kept for older clients that read `estimated_cost`.",
    )
    rating: float = 0.0
    review_count: int = 0

    # Timing
    opening_hours: OpeningHoursInfo = Field(default_factory=OpeningHoursInfo)
    duration_min: int = 0
    distance_km: float = 0.0
    travel_time_min: int = 0
    total_time_min: int = 0

    # Context
    weather: WeatherContext = Field(default_factory=WeatherContext)
    route: RouteInfo = Field(default_factory=RouteInfo)

    # Why + ranking
    why_this_fits: str = ""
    reasons: list[str] = Field(default_factory=list)
    score: float = 0.0
    score_parts: dict[str, float] = Field(default_factory=dict)
    tags: list[str] = Field(default_factory=list)
    accessibility_flags: list[str] = Field(default_factory=list)
    indoor_outdoor: str = "indoor"
    local_gem_score: float = 0.5
    source: str = Field(default="sqlite", description="'sqlite' curated dataset.")

    # Backwards-compatible nested view of the raw experience row.
    experience: ExperienceResponse


class RecommendationResponse(BaseModel):
    total_candidates: int
    feasible_count: int
    weather_used: bool = False
    weather_summary: str | None = None
    weather: WeatherContext = Field(default_factory=WeatherContext)
    route_source: str = Field(
        default="local", description="'google_routes' when route metrics came from Google."
    )
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


# --------------------------------------------------------------------------
# Itineraries
# --------------------------------------------------------------------------


class ItineraryStopInput(BaseModel):
    experience_id: int
    start_time: str | None = Field(default=None, examples=["10:00"])


class ItineraryCreate(BaseModel):
    name: str = Field(default="My Mumbai Day", max_length=120)
    stops: list[ItineraryStopInput] = Field(default_factory=list, max_length=20)


class ItineraryUpdate(BaseModel):
    name: str | None = Field(default=None, max_length=120)
    stops: list[ItineraryStopInput] | None = Field(default=None, max_length=20)


class ItineraryStopResponse(BaseModel):
    id: int
    experience_id: int
    experience: ExperienceResponse
    sequence: int
    start_time: str = ""
    end_time: str = ""
    travel_time_min: int = 0


class ItineraryResponse(BaseModel):
    id: int
    name: str
    total_duration_min: int
    total_cost: int
    created_at: datetime
    stops: list[ItineraryStopResponse] = Field(default_factory=list)


# --------------------------------------------------------------------------
# Geospatial
# --------------------------------------------------------------------------


class NearbyExperience(ExperienceResponse):
    """A nearby experience: the usual experience fields, plus distance/travel.

    ``/experiences/nearby`` used to nest the experience under
    ``{"experience": {...}, "distance_km": n}``, which was inconsistent with
    every other experience endpoint. The item is now flat (same fields as
    ``/experiences``) with ``distance_km``/``travel_time_min`` added, and
    ``NearbyListResponse.results`` still exposes the legacy nested form so
    older clients keep working.
    """

    distance_km: float = 0.0
    travel_time_min: int = 0


class NearbyListResponse(BaseModel):
    total: int
    radius_km: float
    items: list[NearbyExperience] = Field(default_factory=list)
    #: Legacy shape, kept for backwards compatibility.
    results: list[dict] = Field(default_factory=list)


# --------------------------------------------------------------------------
# Feedback
# --------------------------------------------------------------------------


class FeedbackRequest(BaseModel):
    helpful: bool
    location: str | None = Field(default=None, max_length=100)
    interests: list[str] = Field(default_factory=list)


class FeedbackResponse(BaseModel):
    status: str = "recorded"
    experience_id: int
    helpful: bool


# --------------------------------------------------------------------------
# Admin content management
# --------------------------------------------------------------------------


class ExperienceCreate(BaseModel):
    name: str = Field(..., min_length=2, max_length=200)
    category: str = Field(..., min_length=2, max_length=40)
    lat: float = Field(..., ge=-90, le=90)
    lng: float = Field(..., ge=-180, le=180)
    avg_cost: int = Field(default=0, ge=0)
    duration_min: int = Field(default=60, ge=15)
    open_time: str = Field(default="09:00", max_length=5)
    close_time: str = Field(default="21:00", max_length=5)
    rating: float = Field(default=4.0, ge=0.0, le=5.0)
    description: str = Field(default="", max_length=2000)
    image_url: str | None = Field(default=None, max_length=500)
    tags: list[str] = Field(default_factory=list)
    accessibility_flags: list[str] = Field(default_factory=list)
    indoor_outdoor: str = Field(default="indoor", max_length=20)
    local_gem_score: float = Field(default=0.5, ge=0.0, le=1.0)


class ExperienceUpdate(BaseModel):
    name: str | None = Field(default=None, min_length=2, max_length=200)
    category: str | None = Field(default=None, min_length=2, max_length=40)
    lat: float | None = Field(default=None, ge=-90, le=90)
    lng: float | None = Field(default=None, ge=-180, le=180)
    avg_cost: int | None = Field(default=None, ge=0)
    duration_min: int | None = Field(default=None, ge=15)
    open_time: str | None = Field(default=None, max_length=5)
    close_time: str | None = Field(default=None, max_length=5)
    rating: float | None = Field(default=None, ge=0.0, le=5.0)
    description: str | None = Field(default=None, max_length=2000)
    image_url: str | None = Field(default=None, max_length=500)
    tags: list[str] | None = None
    accessibility_flags: list[str] | None = None
    indoor_outdoor: str | None = Field(default=None, max_length=20)
    local_gem_score: float | None = Field(default=None, ge=0.0, le=1.0)
# Places (Google Places API normalized into LocalIQ models)
# --------------------------------------------------------------------------


class PlaceSearchResult(BaseModel):
    """Client-facing place shape. Identical whether it came from Google or SQLite."""

    id: str
    name: str
    category: str
    address: str = ""
    description: str = ""
    lat: float
    lng: float
    rating: float = 0.0
    review_count: int = 0
    avg_cost: int = 0
    image_url: str | None = Field(
        default=None,
        description="LocalIQ proxy URL for Google photos. Never contains a Google key.",
    )
    open_time: str | None = None
    close_time: str | None = None
    open_now: bool | None = None
    distance_km: float | None = None
    travel_minutes: int | None = None
    maps_url: str | None = None
    source: str = Field(default="sqlite", description="'google_places' or 'sqlite'.")


class PlaceSearchResponse(BaseModel):
    query: str
    source: str = Field(default="sqlite", description="Which backend served the data.")
    count: int = 0
    items: list[PlaceSearchResult] = Field(default_factory=list)
    fallback: bool = Field(
        default=True,
        description="True when Google was unavailable and SQLite answered instead.",
    )


