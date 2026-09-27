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
    image_key: str | None = None
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

    # Live "Right Now" context (PRD 4.8). The raw cached JSON is excluded from
    # the response; label/context are unpacked into friendlier fields.
    right_now_score: float = 50.0
    right_now_context_json: dict[str, Any] | None = Field(default=None, exclude=True)
    right_now_label: str = "Okay right now"
    right_now_context: list[str] = Field(default_factory=list)

    # App-facing mirror of the Flutter `Experience` model, so a client can parse
    # one flat object. Populated from the canonical fields below.
    title: str = ""
    place_id: str = ""
    tagline: str = ""
    activity_minutes: int = 0
    minimum_minutes: int = 0
    flexible_timing: bool = True
    typical_spend: int = 0
    weather_suitability: str = "allWeather"
    booking_note: str = "Walk-in"
    local_score: float = 0.0
    tourist_score: float = 0.0
    secondary_category: str = ""
    highlights: list[str] = Field(default_factory=list)
    practical_tip: str | None = None

    model_config = {"from_attributes": True}

    @model_validator(mode="after")
    def _fill_app_mirror(self) -> "ExperienceResponse":
        """Populate the app-facing Experience fields from our canonical ones."""
        self.title = self.title or self.name
        self.place_id = self.place_id or str(self.id)
        if not self.tagline:
            text = (self.description or "").strip()
            self.tagline = self.best_visit_time or (text[:90] if text else "")
        self.activity_minutes = self.activity_minutes or self.duration_min
        self.minimum_minutes = self.minimum_minutes or max(15, min(30, self.duration_min))
        self.typical_spend = self.typical_spend or self.avg_cost
        self.local_score = self.local_score or round((self.local_gem_score or 0.0) * 100, 1)
        self.tourist_score = self.tourist_score or round(
            (1.0 - (self.local_gem_score or 0.0)) * 100, 1
        )
        self.highlights = self.highlights or list(self.tags or [])[:5]
        self.practical_tip = self.practical_tip or self.best_visit_time
        self.secondary_category = self.secondary_category or (
            (self.tags or [""])[0] if self.tags else ""
        )
        tags = {str(t).lower() for t in (self.tags or [])}
        if tags & {"rooftop", "sheltered", "covered", "indoor"}:
            self.weather_suitability = "sheltered"
        elif (self.indoor_outdoor or "").lower() == "indoor":
            self.weather_suitability = "indoorOnly"
        elif (self.indoor_outdoor or "").lower() == "outdoor":
            self.weather_suitability = "weatherSensitive"
        else:
            self.weather_suitability = "allWeather"
        return self

    @model_validator(mode="after")
    def _fill_image_placeholder(self) -> "ExperienceResponse":
        """Guarantee an image so the UI never shows an empty card.

        A self-hosted ``image_key`` (object storage) wins by being turned into
        the media URL; then a curated ``image_url``; otherwise a deterministic
        placeholder is generated from the venue name.
        """
        if not self.image_url and self.image_key:
            base = get_settings().s3_public_base_url.strip().rstrip("/")
            self.image_url = f"{base}/{self.image_key}" if base else f"/media/{self.image_key}"
        if not self.image_url:
            template = get_settings().image_placeholder_url_template
            if template:
                slug = re.sub(r"[^a-z0-9]+", "-", self.name.lower()).strip("-")[:40]
                self.image_url = template.format(seed=f"localiq-{slug}")
        return self

    @model_validator(mode="after")
    def _unpack_right_now(self) -> "ExperienceResponse":
        """Expose the Right Now label/context without leaking the raw cache."""
        raw = self.right_now_context_json or {}
        from app.services.right_now import label_for_score

        self.right_now_label = str(raw.get("label") or label_for_score(self.right_now_score))
        context = raw.get("context")
        self.right_now_context = [str(c) for c in context] if isinstance(context, list) else []
        return self


class ExperienceListResponse(BaseModel):
    total: int
    items: list[ExperienceResponse]


# --------------------------------------------------------------------------
# Right Now Engine (PRD 4.8)
# --------------------------------------------------------------------------


class RightNowRequest(BaseModel):
    location: str | None = Field(default=None, max_length=100)
    origin_lat: float | None = None
    origin_lng: float | None = None
    time_hours: float | None = Field(default=None, ge=0.5, le=24)
    budget_inr: int | None = Field(default=None, ge=0)
    start_time: str | None = Field(default=None, max_length=20)
    limit: int = Field(default=10, ge=1, le=30)


class RightNowItem(BaseModel):
    experience: ExperienceResponse
    right_now_score: float
    right_now_label: str
    context: list[str] = Field(default_factory=list)
    components: dict[str, float] = Field(default_factory=dict)
    rerank_score: float
    final_score: float
    distance_km: float
    travel_time_min: int
    why: list[str] = Field(default_factory=list)


class RightNowDetail(BaseModel):
    experience_id: int
    name: str
    right_now_score: float
    right_now_label: str
    components: dict[str, float] = Field(default_factory=dict)
    context: list[str] = Field(default_factory=list)
    computed_at: str | None = None



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
    #: Mirrors ``GuideRequest.status``. Requests start as ``requested``; the
    #: guide-package booking state machine advances them from there.
    status: Literal["requested", "confirmed", "declined", "cancelled", "completed"] = "requested"
    guide_id: int
    experience_id: int | None = None
    message: str
    booking_ref: str
    booking_id: int | None = None
    created_at: datetime | None = None


class NotificationResponse(BaseModel):
    """One in-app notification."""

    id: int
    kind: str = "system"
    title: str
    body: str
    data: dict[str, Any] = Field(default_factory=dict)
    read_at: datetime | None = None
    created_at: datetime

    model_config = {"from_attributes": True}


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
    terms_accepted: bool | None = Field(default=None)

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
    # App-facing mirror of the Flutter `LocalIqUser` model so the client can
    # parse one flat object without a translation layer.
    display_name: str = ""
    avatar_url: str | None = None
    provider: str = "email"
    tier: str = "free"
    home_city: str = "Mumbai"
    is_anonymous: bool = False
    #: True once the address is confirmed (Resend verification link, or a
    #: provider that vouches for it).
    email_verified: bool = False
    #: True once the user has completed the taste-onboarding conversation.
    onboarding_completed: bool = False

    model_config = {"from_attributes": True}

    @model_validator(mode="after")
    def _fill_display_name(self) -> "UserResponse":
        if not self.display_name:
            self.display_name = self.name
        return self


class TokenResponse(BaseModel):
    access_token: str
    refresh_token: str = ""
    token_type: str = "bearer"
    expires_in: int
    user: UserResponse


class RefreshRequest(BaseModel):
    refresh_token: str = Field(..., min_length=10)


class ForgotPasswordRequest(BaseModel):
    email: str = Field(..., min_length=5, max_length=200)


class VerifyEmailRequest(BaseModel):
    token: str = Field(..., min_length=10, max_length=512)


class GoogleAuthRequest(BaseModel):
    id_token: str = Field(..., min_length=10)


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
    # App-facing mirror of the Flutter `WeatherSnapshot`. Shipped snake_case;
    # the Dart `json_map_x.pick` accepts snake_case for its camelCase lookups.
    temperature_c: float | None = None
    apparent_temperature_c: float | None = None
    humidity: int | None = None
    precipitation_chance: int | None = None
    wind_kph: float | None = None
    uv_index: float | None = None
    observed_at: datetime | None = None
    sunrise: datetime | None = None
    sunset: datetime | None = None


class TrafficResponse(BaseModel):
    level: str = "moderate"
    speedMultiplier: float = 1.15
    updatedAt: datetime | None = None


class LiveContextResponse(BaseModel):
    weather: WeatherResponse
    traffic: TrafficResponse


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


class ItineraryGenerateRequest(BaseModel):
    """Inputs for the A-to-Z day planner."""

    name: str = Field(default="My Mumbai Day", max_length=120)
    start_location: str | None = Field(default=None, max_length=100)
    start_time: str = Field(default="10:00", max_length=20)
    duration_hours: float = Field(default=8.0, ge=1.0, le=16.0)
    budget_inr: int | None = Field(default=None, ge=0)
    travel_mode: str = Field(default="WALK", max_length=20)
    interests: list[str] = Field(default_factory=list, max_length=20)
    include_food: bool = True
    max_stops: int = Field(default=5, ge=1, le=10)
    semantic_query: str | None = Field(default=None, max_length=300)


class ItineraryImportStop(BaseModel):
    """One imported row: link by id, or by name (fuzzy matched)."""

    experience_id: int | None = None
    name: str | None = Field(default=None, max_length=200)
    start_time: str | None = Field(default=None, max_length=20)


class ItineraryImportRequest(BaseModel):
    name: str = Field(default="Imported plan", max_length=120)
    format: Literal["json", "text"] = "json"
    stops: list[ItineraryImportStop] = Field(default_factory=list, max_length=30)
    text: str | None = Field(default=None, max_length=5000)
    optimize: bool = True


class ItineraryImportResponse(BaseModel):
    itinerary: ItineraryResponse
    unresolved: list[str] = Field(default_factory=list)


class ItineraryShareResponse(BaseModel):
    share_token: str
    url: str
    itinerary: ItineraryResponse


# --------------------------------------------------------------------------
# Experience Wallet & Passport (PRD 4.9)
# --------------------------------------------------------------------------


class WalletLogRequest(BaseModel):
    experience_id: int
    rating: float | None = Field(default=None, ge=0.0, le=5.0)
    notes: str | None = Field(default=None, max_length=2000)
    context: dict[str, Any] = Field(default_factory=dict)


class WalletStats(BaseModel):
    total_experiences: int = 0
    hidden_gem_count: int = 0
    total_spent_inr: int = 0
    total_duration_min: int = 0
    categories: dict[str, int] = Field(default_factory=dict)
    cities: dict[str, int] = Field(default_factory=dict)


class WalletBadge(BaseModel):
    code: str
    name: str
    description: str = ""
    tier: str = "bronze"
    xp_bonus: int = 0
    earned: bool = False
    earned_at: datetime | None = None


class WalletTimelineItem(BaseModel):
    experience_id: int
    name: str
    category: str
    lat: float
    lng: float
    image_url: str | None = None
    image_key: str | None = None
    completed_at: datetime | None = None
    rating: float | None = None
    notes: str | None = None

    @model_validator(mode="after")
    def _resolve_image(self) -> "WalletTimelineItem":
        if not self.image_url and self.image_key:
            base = get_settings().s3_public_base_url.strip().rstrip("/")
            self.image_url = f"{base}/{self.image_key}" if base else f"/media/{self.image_key}"
        return self


class WalletPassport(BaseModel):
    stats: WalletStats
    badges: list[WalletBadge] = Field(default_factory=list)
    timeline: list[WalletTimelineItem] = Field(default_factory=list)
    pins: list[dict[str, Any]] = Field(default_factory=list)


class WalletLogResponse(BaseModel):
    experience_id: int
    completed_at: datetime | None = None
    new_badges: list[WalletBadge] = Field(default_factory=list)
    stats: WalletStats


class WalletShareSummary(BaseModel):
    period: str
    total_experiences: int
    hidden_gem_count: int
    total_spent_inr: int
    top_categories: list[str] = Field(default_factory=list)
    highlights: list[str] = Field(default_factory=list)
    badges: list[str] = Field(default_factory=list)


# --------------------------------------------------------------------------
# AI Experience Director — live companion (PRD 4.10)
# --------------------------------------------------------------------------


class DirectorStartRequest(BaseModel):
    experience_id: int | None = None
    itinerary_id: int | None = None
    language: str = Field(default="en", max_length=8)


class DirectorCheckInRequest(BaseModel):
    lat: float | None = None
    lng: float | None = None


class DirectorEndRequest(BaseModel):
    rating: float | None = Field(default=None, ge=0.0, le=5.0)
    notes: str | None = Field(default=None, max_length=2000)


class AITipView(BaseModel):
    id: int
    category: str
    message: str
    language: str = "en"


class DirectorSessionView(BaseModel):
    id: int
    status: str
    language: str
    experience_id: int | None = None
    itinerary_id: int | None = None
    start_time: datetime | None = None
    end_time: datetime | None = None
    stops: list[dict[str, Any]] = Field(default_factory=list)
    summary: dict[str, Any] = Field(default_factory=dict)
    shown_tip_ids: list[int] = Field(default_factory=list)


class DirectorTipResponse(BaseModel):
    session_id: int
    tip: AITipView | None = None
    remaining: int = 0
    message: str = ""


class DirectorAdaptResponse(BaseModel):
    session_id: int
    adaptation_needed: bool
    message: str
    suggestion: ExperienceResponse | None = None
    travel_time_min: int = 0
    why: list[str] = Field(default_factory=list)


class DirectorEndResponse(BaseModel):
    session_id: int
    status: str
    summary: dict[str, Any]
    new_badges: list[dict[str, Any]] = Field(default_factory=list)


# --------------------------------------------------------------------------
# Guided onboarding (taste capture)
# --------------------------------------------------------------------------


class OnboardingStartRequest(BaseModel):
    language: str = Field(default="en", max_length=8)
    restart: bool = False


class OnboardingAnswerRequest(BaseModel):
    message: str | None = Field(default=None, max_length=1000)
    selections: list[str] = Field(default_factory=list)


class OnboardingStep(BaseModel):
    session_id: int | None = None
    status: str = "in_progress"
    step: int = 0
    total_steps: int = 0
    progress: float = 0.0
    ack: str | None = None
    prompt: str | None = None
    options: list[str] = Field(default_factory=list)
    multi: bool = False
    free_text: bool = False
    done: bool = False
    completed: bool = False
    taste: dict[str, Any] | None = None


# --------------------------------------------------------------------------
# Fast guide onboarding
# --------------------------------------------------------------------------


class GuideOnboardingStartRequest(BaseModel):
    name: str | None = Field(default=None, max_length=120)
    languages: list[str] = Field(default_factory=list)
    city: str = Field(default="Mumbai", max_length=80)
    bio: str = Field(default="", max_length=2000)


class GuideOnboardingApplyRequest(BaseModel):
    areas: list[str] = Field(default_factory=list)
    niches: list[str] = Field(default_factory=list)
    rate_per_hour: int | None = Field(default=None, ge=0, le=100000)
    bio: str | None = Field(default=None, max_length=2000)
    languages: list[str] = Field(default_factory=list)


class GuideDocumentResponse(BaseModel):
    kind: str
    key: str
    content_type: str
    size: int


class GuideOnboardingStatus(BaseModel):
    guide_id: int | None = None
    state: str = "not_started"
    verification_status: str = "unverified"
    verification_tier: str = "basic"
    required_documents: list[str] = Field(default_factory=list)
    documents: dict[str, Any] = Field(default_factory=dict)
    has_driver_license: bool = False
    has_guide_license: bool = False
    areas: list[str] = Field(default_factory=list)
    niches: list[str] = Field(default_factory=list)
    can_submit: bool = False
    is_published: bool = False
    submitted_at: str | None = None
    admin_notes: str | None = None


class GuideVerifyRequest(BaseModel):
    approve: bool = True
    notes: str | None = Field(default=None, max_length=1000)
    tier: str = Field(default="standard", max_length=20)


class GuideOptionsResponse(BaseModel):
    areas: list[str] = Field(default_factory=list)
    niches: list[str] = Field(default_factory=list)
    document_kinds: list[str] = Field(default_factory=list)


# --------------------------------------------------------------------------
# Driver trips (pickup -> stops -> drop, with route geometry)
# --------------------------------------------------------------------------


class TripPoint(BaseModel):
    lat: float
    lng: float
    label: str | None = None
    address: str | None = None


class TripStop(BaseModel):
    sequence: int
    name: str | None = None
    lat: float | None = None
    lng: float | None = None
    duration_min: int = 0
    travel_time_min: int = 0
    segment_type: str = "experience"
    guide_notes: str | None = None


class TripRemaining(BaseModel):
    distance_km: float
    duration_min: int


class DriverTripSummary(BaseModel):
    id: int
    booking_ref: str
    status: str
    date: str | None = None
    start_time: str | None = None
    group_size: int = 1
    guest_name: str | None = None
    package_title: str | None = None
    pickup_address: str | None = None
    pickup: TripPoint | None = None
    has_driver_location: bool = False


class DriverTripDetail(BaseModel):
    id: int
    booking_ref: str
    status: str
    allowed_transitions: list[str] = Field(default_factory=list)
    date: str | None = None
    start_time: str | None = None
    hours: int = 2
    group_size: int = 1
    guest_name: str | None = None
    guest_phone: str | None = None
    note: str | None = None
    package_id: int | None = None
    package_title: str | None = None
    guide_id: int
    guide_name: str | None = None
    pickup: TripPoint | None = None
    drop: TripPoint | None = None
    stops: list[TripStop] = Field(default_factory=list)
    route: list[dict[str, float]] = Field(default_factory=list)
    distance_km: float = 0.0
    duration_min: int = 0
    route_source: str = "local"
    driver_location: TripPoint | None = None
    remaining: TripRemaining | None = None


class DriverTripStatusUpdate(BaseModel):
    status: Literal["confirmed", "in_progress", "completed", "cancelled"]
    note: str | None = Field(default=None, max_length=300)


class DriverLocationUpdate(BaseModel):
    lat: float = Field(ge=-90, le=90)
    lng: float = Field(ge=-180, le=180)


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


# --------------------------------------------------------------------------
# Chat, agent and planner
# --------------------------------------------------------------------------


class MessageResponse(BaseModel):
    id: int
    role: str
    content: str
    created_at: datetime
    tool_json: dict[str, Any] = Field(default_factory=dict)


class ConversationResponse(BaseModel):
    id: int
    kind: str
    title: str | None = None
    created_at: datetime
    updated_at: datetime


class ConversationCreateRequest(BaseModel):
    kind: str = Field(default="general", max_length=20)
    title: str | None = Field(default=None, max_length=160)
    data_json: dict[str, Any] = Field(default_factory=dict)


class ChatMessageRequest(BaseModel):
    content: str = Field(..., min_length=1, max_length=2000)


class ChatMessageResponse(BaseModel):
    message: MessageResponse
    assistant: MessageResponse | None = None


class AgentChatRequest(BaseModel):
    conversation_id: int | None = None
    message: str = Field(..., min_length=1, max_length=2000)
    confirm: bool = Field(
        default=False,
        description="Set to true to approve a pending tool-calling turn.",
    )
    lat: float | None = Field(default=None, ge=-90, le=90)
    lng: float | None = Field(default=None, ge=-180, le=180)


class ToolCall(BaseModel):
    id: str
    name: str
    arguments: dict[str, Any] = Field(default_factory=dict)


class AgentPendingAction(BaseModel):
    run_id: int
    conversation_id: int
    message: str
    tool_calls: list[ToolCall] = Field(default_factory=list)


class AgentChatResponse(BaseModel):
    conversation_id: int
    run_id: int
    status: str
    message: MessageResponse
    pending_actions: list[ToolCall] = Field(default_factory=list)


class PlannerCreateRequest(BaseModel):
    """High-level trip request the agent/form can send to the planner."""

    name: str = Field(default="My Mumbai Trip", max_length=120)
    start_location: str | None = Field(default=None, max_length=100)
    start_time: str = Field(default="10:00", max_length=20)
    duration_hours: float = Field(default=8.0, ge=1.0, le=16.0)
    budget_inr: int | None = Field(default=None, ge=0)
    travel_mode: str = Field(default="WALK", max_length=20)
    interests: list[str] = Field(default_factory=list, max_length=20)
    include_food: bool = True
    max_stops: int = Field(default=5, ge=1, le=10)
    semantic_query: str | None = Field(default=None, max_length=300)


