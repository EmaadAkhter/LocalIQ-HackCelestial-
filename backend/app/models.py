"""Database models for LocalIQ.

All tables carry ``created_at`` / ``updated_at`` (naive UTC) via
``TimestampMixin``. Composite indexes cover the common query shapes.

Relationship notes:
- SQLModel 0.0.47 + SQLAlchemy 2.0 is strict about forward references. Keep
  bidirectional relationships only between classes where the referenced class is
  defined *after* the relationship owner, and avoid generic wrappers like
  ``List``/``Optional`` in relationship annotations.
- Association tables and new feature tables use explicit queries instead of
  relationships to keep mapper configuration stable.
"""

import enum
from datetime import date, datetime
from typing import Any, List, Optional

from sqlalchemy import JSON, Column, Date, DateTime, Index, UniqueConstraint
from sqlmodel import Field, Relationship, SQLModel

from app.timeutil import utcnow
from app.vector import Vector


class TimestampMixin(SQLModel):
    """Created/updated bookkeeping, populated automatically."""

    created_at: datetime = Field(
        default_factory=utcnow,
        sa_type=DateTime,
        sa_column_kwargs={"nullable": False},
    )
    updated_at: datetime = Field(
        default_factory=utcnow,
        sa_type=DateTime,
        sa_column_kwargs={"nullable": False, "onupdate": utcnow},
    )


# -----------------------------------------------------------------------------
# Original core tables (keep relationships stable)
# -----------------------------------------------------------------------------


class Experience(TimestampMixin, table=True):
    """Mumbai experience model."""

    __tablename__ = "experiences"
    __table_args__ = (
        Index("ix_experiences_category_rating", "category", "rating"),
        Index("ix_experiences_lat_lng", "lat", "lng"),
        Index("ix_experiences_avg_cost", "avg_cost"),
    )

    id: Optional[int] = Field(default=None, primary_key=True)
    name: str = Field(index=True)
    category: str = Field(index=True)
    lat: float
    lng: float
    avg_cost: int = Field(default=0, ge=0)
    duration_min: int = Field(default=60, ge=15)
    open_time: str = Field(default="09:00")
    close_time: str = Field(default="21:00")
    rating: float = Field(default=4.0, ge=0.0, le=5.0)
    description: str = Field(default="")
    image_url: Optional[str] = Field(default=None)
    #: Object-storage key for the self-hosted photo (S3/MinIO). Preferred over
    #: ``image_url`` so images survive a change of CDN/base URL.
    image_key: Optional[str] = Field(default=None, max_length=500)
    tags: list[str] = Field(default_factory=list, sa_column=Column(JSON))
    accessibility_flags: list[str] = Field(default_factory=list, sa_column=Column(JSON))
    indoor_outdoor: str = Field(default="indoor")
    local_gem_score: float = Field(default=0.5, ge=0.0, le=1.0)

    # Semantic + DNA fields
    embedding: Optional[list[float]] = Field(
        default=None,
        sa_column=Column(Vector(dimensions=768), nullable=True),
    )
    vibe_vector: dict[str, Any] = Field(default_factory=dict, sa_column=Column(JSON))
    weather_suitability_score: dict[str, Any] = Field(default_factory=dict, sa_column=Column(JSON))

    # Internal scores
    accessibility_score: float = Field(default=0.0, ge=0.0, le=100.0)
    authenticity_score: float = Field(default=0.0, ge=0.0, le=100.0)
    safety_score: float = Field(default=0.0, ge=0.0, le=100.0)
    crowd_density_level: str = Field(default="MEDIUM", max_length=20)
    noise_level: str = Field(default="MODERATE", max_length=20)

    # Rich scheduling metadata
    opening_hours_json: dict[str, Any] = Field(default_factory=dict, sa_column=Column(JSON))
    peak_times_json: dict[str, Any] = Field(default_factory=dict, sa_column=Column(JSON))
    best_visit_time: Optional[str] = Field(default=None, max_length=200)
    time_to_spend: Optional[str] = Field(default=None, max_length=100)

    # Live context (PRD 4.8 "Right Now" Engine). ``right_now_score`` is a 0-100
    # badge kept warm by the refresh job; ``right_now_context_json`` caches the
    # human-readable reasons behind the current score.
    right_now_score: float = Field(default=50.0, ge=0.0, le=100.0)
    right_now_context_json: dict[str, Any] = Field(default_factory=dict, sa_column=Column(JSON))
    right_now_updated_at: Optional[datetime] = Field(default=None)

    guides: list["Guide"] = Relationship(back_populates="experience")


class Guide(TimestampMixin, table=True):
    """Local guide model."""

    __tablename__ = "guides"
    __table_args__ = (Index("ix_guides_experience_rating", "experience_id", "rating"),)

    id: Optional[int] = Field(default=None, primary_key=True)
    experience_id: Optional[int] = Field(default=None, foreign_key="experiences.id", index=True)
    name: str
    photo: Optional[str] = Field(default=None)
    languages: list[str] = Field(default_factory=list, sa_column=Column(JSON))
    specialty: str = Field(default="local culture")
    rate_per_hour: int = Field(default=800, ge=0)
    rating: float = Field(default=4.5, ge=0.0, le=5.0)

    # Verification & profile
    verification_status: str = Field(default="unverified", max_length=20)
    background_checked: bool = Field(default=False)
    uin: Optional[str] = Field(default=None, max_length=50)
    areas_covered: list[str] = Field(default_factory=list, sa_column=Column(JSON))
    energy_level: str = Field(default="relaxed", max_length=20)
    storytelling_style: str = Field(default="casual", max_length=40)
    max_group_size: int = Field(default=6, ge=1)
    bio: Optional[str] = Field(default=None, max_length=2000)

    experience: Optional["Experience"] = Relationship(back_populates="guides")


class User(TimestampMixin, table=True):
    """Local account. Password is stored only as a PBKDF2 hash."""

    __tablename__ = "users"

    id: Optional[int] = Field(default=None, primary_key=True)
    name: str = Field(index=True)
    email: str = Field(index=True, unique=True)
    password_hash: str
    group_type: Optional[str] = Field(default=None)
    # PRD v2 trust tier: "basic" -> "standard" -> "trusted". Raised only by the
    # simulated verification endpoint; never from a client-supplied value.
    trust_tier: str = Field(default="basic", max_length=20, index=True)
    # sa_type is explicit so the column stays naive UTC like every other
    # timestamp in this codebase (see app/timeutil.py).
    trust_verified_at: Optional[datetime] = Field(default=None, sa_type=DateTime)

    # Trust / verification
    id_verification_status: str = Field(default="unverified", max_length=20)
    id_verified_at: Optional[datetime] = Field(default=None)
    kyc_provider_ref: Optional[str] = Field(default=None, max_length=200)

    # Taste profile (PRD 4.6). ``taste_profile_text`` is the LLM summary the user
    # can read and edit; ``taste_profile_vector`` is a tag -> weight map learned
    # from explicit + implicit signals and used to re-rank recommendations.
    taste_profile_text: Optional[str] = Field(default=None, max_length=2000)
    taste_profile_vector: dict[str, Any] = Field(default_factory=dict, sa_column=Column(JSON))
    personalization_enabled: bool = Field(default=True)
    preferred_language: str = Field(default="en", max_length=8)

    # App-facing account metadata, mirroring the Flutter `LocalIqUser` model.
    # ``provider`` is how the account was created; ``tier`` is the subscription
    # level (guest/free/plus/pro) — distinct from the PRD ``trust_tier``.
    provider: str = Field(default="email", max_length=20)
    tier: str = Field(default="free", max_length=20)
    home_city: str = Field(default="Mumbai", max_length=80)
    is_anonymous: bool = Field(default=False)

    # Email verification (Resend). Marks the address as confirmed and remembers
    # when the last verification email went out so resends can be throttled.
    email_verified: bool = Field(default=False)
    email_verified_at: Optional[datetime] = Field(default=None, sa_type=DateTime)
    email_verification_sent_at: Optional[datetime] = Field(default=None, sa_type=DateTime)

    sessions: list["UserSession"] = Relationship(back_populates="user")


class UserSession(TimestampMixin, table=True):
    """Persisted session. Only the SHA-256 hash of the token is stored."""

    __tablename__ = "user_sessions"
    __table_args__ = (Index("ix_user_sessions_user_expires", "user_id", "expires_at"),)

    id: Optional[int] = Field(default=None, primary_key=True)
    user_id: int = Field(foreign_key="users.id", index=True)
    token_hash: str = Field(index=True, unique=True)
    expires_at: datetime = Field(sa_type=DateTime, sa_column_kwargs={"nullable": False})
    # Long-lived refresh token paired with this session, so ``/auth/refresh``
    # can mint a new access token without a password.
    refresh_token_hash: Optional[str] = Field(default=None, index=True, unique=True)
    refresh_expires_at: Optional[datetime] = Field(default=None, sa_type=DateTime)

    user: Optional["User"] = Relationship(back_populates="sessions")


class EmailVerificationToken(TimestampMixin, table=True):
    """Single-use email verification token.

    Only the hash is stored (same scheme as sessions), so a database leak cannot
    be replayed. Issuing a new token invalidates any earlier unconsumed one.
    """

    __tablename__ = "email_verification_tokens"
    __table_args__ = (
        Index("ix_email_verification_user_expires", "user_id", "expires_at"),
    )

    id: Optional[int] = Field(default=None, primary_key=True)
    user_id: int = Field(foreign_key="users.id", index=True)
    token_hash: str = Field(index=True, unique=True)
    expires_at: datetime = Field(sa_type=DateTime, sa_column_kwargs={"nullable": False})
    consumed_at: Optional[datetime] = Field(default=None, sa_type=DateTime)


class NotificationKind(str, enum.Enum):
    """Category, so the app can pick an icon and a destination."""

    BOOKING = "booking"
    GUIDE = "guide"
    SYSTEM = "system"


class Notification(TimestampMixin, table=True):
    """In-app notification for a user.

    Read with simple ``user_id``-filtered queries, so it carries no relationship
    (see the module docstring). The payload that matters — which booking, which
    guide — travels in ``data`` so the row stays meaningful even if those
    entities change underneath it.
    """

    __tablename__ = "notifications"
    __table_args__ = (
        Index("ix_notifications_user_created", "user_id", "created_at"),
        Index("ix_notifications_user_read", "user_id", "read_at"),
    )

    id: Optional[int] = Field(default=None, primary_key=True)
    user_id: int = Field(foreign_key="users.id", index=True)
    kind: str = Field(default="system", max_length=20)
    title: str = Field(max_length=160)
    body: str = Field(max_length=1000)
    #: Small JSON payload (booking_id, guide_id, status, ...).
    data: dict[str, Any] = Field(default_factory=dict, sa_column=Column(JSON))
    read_at: Optional[datetime] = Field(default=None, sa_type=DateTime)


class GuideRequest(TimestampMixin, table=True):
    """Legacy persisted guide booking request (kept for backwards compatibility)."""

    __tablename__ = "guide_requests"
    __table_args__ = (Index("ix_guide_requests_user_created", "user_id", "created_at"),)

    id: Optional[int] = Field(default=None, primary_key=True)
    user_id: Optional[int] = Field(default=None, foreign_key="users.id", index=True)
    guide_id: int = Field(foreign_key="guides.id", index=True)
    experience_id: Optional[int] = Field(default=None, foreign_key="experiences.id", index=True)
    requester_name: str = Field(default="")
    date: Optional[str] = Field(default=None)
    hours: int = Field(default=2)
    group_size: int = Field(default=2)
    note: Optional[str] = Field(default=None)
    status: str = Field(default="requested")
    booking_ref: str = Field(index=True)


class Itinerary(TimestampMixin, table=True):
    """A saved plan owned by a user."""

    __tablename__ = "itineraries"
    __table_args__ = (Index("ix_itineraries_user_created", "user_id", "created_at"),)

    id: Optional[int] = Field(default=None, primary_key=True)
    user_id: Optional[int] = Field(default=None, foreign_key="users.id", index=True)
    name: str = Field(default="My Mumbai Day")
    total_duration_min: int = Field(default=0)
    total_cost: int = Field(default=0)
    #: Opaque token for a read-only public share link (created on demand).
    share_token: Optional[str] = Field(default=None, max_length=64, index=True)

    stops: list["ItineraryStop"] = Relationship(
        back_populates="itinerary",
        sa_relationship_kwargs={"cascade": "all, delete-orphan"},
    )


class ItineraryStop(TimestampMixin, table=True):
    """Optional itinerary stop (secondary, hackathon-optional)."""

    __tablename__ = "itinerary_stops"
    __table_args__ = (Index("ix_itinerary_stops_itinerary_seq", "itinerary_id", "sequence"),)

    id: Optional[int] = Field(default=None, primary_key=True)
    itinerary_id: int = Field(foreign_key="itineraries.id", index=True)
    experience_id: int = Field(foreign_key="experiences.id", index=True)
    sequence: int = Field(default=0)
    start_time: str = Field(default="")
    end_time: str = Field(default="")
    travel_time_min: int = Field(default=0)

    itinerary: Optional["Itinerary"] = Relationship(back_populates="stops")


class Favorite(TimestampMixin, table=True):
    """A user's saved experience. Unique per (user, experience)."""

    __tablename__ = "favorites"
    __table_args__ = (
        UniqueConstraint("user_id", "experience_id", name="uq_favorite_user_experience"),
        Index("ix_favorites_user_created", "user_id", "created_at"),
    )

    id: Optional[int] = Field(default=None, primary_key=True)
    user_id: int = Field(foreign_key="users.id", index=True)
    experience_id: int = Field(foreign_key="experiences.id", index=True)


class RecommendationFeedback(TimestampMixin, table=True):
    """A thumbs up/down on a recommended experience, used to nudge ranking."""

    __tablename__ = "recommendation_feedback"
    __table_args__ = (Index("ix_feedback_experience_created", "experience_id", "created_at"),)

    id: Optional[int] = Field(default=None, primary_key=True)
    user_id: Optional[int] = Field(default=None, foreign_key="users.id", index=True)
    experience_id: int = Field(foreign_key="experiences.id", index=True)
    helpful: bool = Field(default=True)
    location: Optional[str] = Field(default=None)
    interests: list[str] = Field(default_factory=list, sa_column=Column(JSON))


# -----------------------------------------------------------------------------
# Tag taxonomy
# -----------------------------------------------------------------------------


class TagFacetType(str, enum.Enum):
    USER_FACING = "user_facing"
    INTERNAL = "internal"
    COMPOSITE = "composite"


class Tag(TimestampMixin, table=True):
    """Master taxonomy tag."""

    __tablename__ = "tags"
    # ``category`` is indexed via Field(index=True); only facet_type needs an
    # explicit index here. Defining both would emit duplicate CREATE INDEX
    # statements with the same name on a fresh database.
    __table_args__ = (Index("ix_tags_facet_type", "facet_type"),)

    id: Optional[int] = Field(default=None, primary_key=True)
    name: str = Field(index=True, unique=True, max_length=80)
    category: str = Field(index=True, max_length=40)
    facet_type: str = Field(default=TagFacetType.USER_FACING.value, max_length=20)
    description: Optional[str] = Field(default=None, max_length=500)
    weight: float = Field(default=1.0)


class ExperienceTag(TimestampMixin, table=True):
    """Many-to-many link between experiences and tags with provenance."""

    __tablename__ = "experience_tags"
    __table_args__ = (
        UniqueConstraint("experience_id", "tag_id", name="uq_experience_tag"),
        # Distinct name from the Field(index=True) index; the migration records
        # both, so keep both to avoid model/migration drift.
        Index("ix_experience_tags_tag", "tag_id"),
    )

    id: Optional[int] = Field(default=None, primary_key=True)
    experience_id: int = Field(foreign_key="experiences.id", index=True)
    tag_id: int = Field(foreign_key="tags.id", index=True)
    confidence: float = Field(default=1.0, ge=0.0, le=1.0)
    source: str = Field(default="manual", max_length=20)


class CompositeTag(TimestampMixin, table=True):
    """Smart filter composed of required/optional base tags."""

    __tablename__ = "composite_tags"

    id: Optional[int] = Field(default=None, primary_key=True)
    name: str = Field(index=True, unique=True, max_length=80)
    description: Optional[str] = Field(default=None, max_length=500)
    required_tags: list[str] = Field(default_factory=list, sa_column=Column(JSON))
    optional_tags: list[str] = Field(default_factory=list, sa_column=Column(JSON))


# -----------------------------------------------------------------------------
# Discovery pipeline
# -----------------------------------------------------------------------------


class DiscoverySource(TimestampMixin, table=True):
    """A web source tracked by the SearXNG scraper pipeline."""

    __tablename__ = "discovery_sources"

    id: Optional[int] = Field(default=None, primary_key=True)
    name: str = Field(index=True, max_length=200)
    base_url: Optional[str] = Field(default=None, max_length=500)
    source_type: str = Field(default="blog", max_length=40)
    trust_score: float = Field(default=0.5, ge=0.0, le=1.0)
    last_scraped: Optional[datetime] = Field(default=None)


class CandidateStatus(str, enum.Enum):
    PENDING = "pending"
    APPROVED = "approved"
    REJECTED = "rejected"


class ScrapedCandidate(TimestampMixin, table=True):
    """Raw extracted candidate awaiting curation."""

    __tablename__ = "scraped_candidates"
    __table_args__ = (Index("ix_scraped_candidates_status", "status"),)

    id: Optional[int] = Field(default=None, primary_key=True)
    raw_title: str = Field(max_length=300)
    url: Optional[str] = Field(default=None, max_length=1000)
    area: Optional[str] = Field(default=None, max_length=100)
    extracted_data: dict[str, Any] = Field(default_factory=dict, sa_column=Column(JSON))
    llm_confidence: float = Field(default=0.0, ge=0.0, le=1.0)
    mention_count: int = Field(default=0, ge=0)
    authenticity_signals: dict[str, Any] = Field(default_factory=dict, sa_column=Column(JSON))
    status: str = Field(default=CandidateStatus.PENDING.value, max_length=20)
    reviewed_at: Optional[datetime] = Field(default=None)
    reviewed_by: Optional[int] = Field(default=None, foreign_key="users.id")
    experience_id: Optional[int] = Field(default=None, foreign_key="experiences.id")


class CandidateCitation(TimestampMixin, table=True):
    """A mention of a place found by the scraper."""

    __tablename__ = "candidate_citations"
    __table_args__ = (Index("ix_candidate_citations_candidate_source", "candidate_id", "source_id"),)

    id: Optional[int] = Field(default=None, primary_key=True)
    candidate_id: int = Field(foreign_key="scraped_candidates.id", index=True)
    source_id: Optional[int] = Field(default=None, foreign_key="discovery_sources.id", index=True)
    url: Optional[str] = Field(default=None, max_length=1000)
    quote: Optional[str] = Field(default=None, max_length=2000)
    sentiment: str = Field(default="neutral", max_length=20)
    mention_date: Optional[datetime] = Field(default=None)


# -----------------------------------------------------------------------------
# Guide marketplace
# -----------------------------------------------------------------------------


class GuidePackage(TimestampMixin, table=True):
    """End-to-end guide package: pickup, route, activities, drop-off."""

    __tablename__ = "guide_packages"
    __table_args__ = (Index("ix_guide_packages_guide", "guide_id"),)

    id: Optional[int] = Field(default=None, primary_key=True)
    guide_id: int = Field(foreign_key="guides.id", index=True)
    title: str = Field(max_length=200)
    description: Optional[str] = Field(default=None, max_length=2000)
    pickup_type: str = Field(default="fixed_point", max_length=20)
    default_pickup_area: Optional[str] = Field(default=None, max_length=200)
    pickup_lat: Optional[float] = Field(default=None)
    pickup_lng: Optional[float] = Field(default=None)
    drop_off_same_as_pickup: bool = Field(default=True)
    max_pickup_distance_km: float = Field(default=10.0, ge=0.0)
    total_duration_hours: float = Field(default=3.0, ge=0.5)
    inclusions: list[str] = Field(default_factory=list, sa_column=Column(JSON))
    price_per_person: int = Field(default=0, ge=0)
    total_price: Optional[int] = Field(default=None, ge=0)
    max_group_size: int = Field(default=6, ge=1)
    languages: list[str] = Field(default_factory=list, sa_column=Column(JSON))
    cancellation_policy: Optional[str] = Field(default=None, max_length=1000)
    is_active: bool = Field(default=True)


class GuidePackageStop(TimestampMixin, table=True):
    """One segment of a guide package route."""

    __tablename__ = "guide_package_stops"
    __table_args__ = (Index("ix_guide_package_stops_package_seq", "package_id", "sequence"),)

    id: Optional[int] = Field(default=None, primary_key=True)
    package_id: int = Field(foreign_key="guide_packages.id", index=True)
    experience_id: Optional[int] = Field(default=None, foreign_key="experiences.id", index=True)
    sequence: int = Field(default=0, ge=0)
    segment_type: str = Field(default="experience", max_length=20)
    location_name: Optional[str] = Field(default=None, max_length=200)
    lat: Optional[float] = Field(default=None)
    lng: Optional[float] = Field(default=None)
    duration_min: int = Field(default=60, ge=0)
    travel_time_min: int = Field(default=0, ge=0)
    guide_notes: Optional[str] = Field(default=None, max_length=1000)


class BookingStatus(str, enum.Enum):
    REQUESTED = "requested"
    ACCEPTED = "accepted"
    DECLINED = "declined"
    CONFIRMED = "confirmed"
    COMPLETED = "completed"
    CANCELLED = "cancelled"


class PackageBooking(TimestampMixin, table=True):
    """Guide-package booking lifecycle."""

    __tablename__ = "package_bookings"
    __table_args__ = (Index("ix_package_bookings_user_status", "user_id", "status"),)

    id: Optional[int] = Field(default=None, primary_key=True)
    booking_ref: str = Field(index=True, max_length=32)
    user_id: Optional[int] = Field(default=None, foreign_key="users.id", index=True)
    guide_id: int = Field(foreign_key="guides.id", index=True)
    package_id: Optional[int] = Field(default=None, foreign_key="guide_packages.id", index=True)
    experience_id: Optional[int] = Field(default=None, foreign_key="experiences.id", index=True)
    pickup_address: Optional[str] = Field(default=None, max_length=500)
    pickup_lat: Optional[float] = Field(default=None)
    pickup_lng: Optional[float] = Field(default=None)
    #: Explicit drop point. When unset the trip returns to the pickup.
    drop_address: Optional[str] = Field(default=None, max_length=500)
    drop_lat: Optional[float] = Field(default=None)
    drop_lng: Optional[float] = Field(default=None)
    date: Optional[str] = Field(default=None, max_length=10)
    start_time: Optional[str] = Field(default=None, max_length=5)
    hours: int = Field(default=2, ge=1)
    group_size: int = Field(default=2, ge=1)
    total_price: Optional[int] = Field(default=None, ge=0)
    status: str = Field(default=BookingStatus.REQUESTED.value, max_length=20)
    note: Optional[str] = Field(default=None, max_length=500)
    guest_name: Optional[str] = Field(default=None, max_length=100)
    guest_phone: Optional[str] = Field(default=None, max_length=20)
    #: Last position the driver's device reported, for the live trip map.
    driver_lat: Optional[float] = Field(default=None)
    driver_lng: Optional[float] = Field(default=None)
    driver_updated_at: Optional[datetime] = Field(default=None, sa_type=DateTime)
    started_at: Optional[datetime] = Field(default=None, sa_type=DateTime)
    completed_at: Optional[datetime] = Field(default=None, sa_type=DateTime)


class PackageReview(TimestampMixin, table=True):
    """Review for a guide or package."""

    __tablename__ = "package_reviews"
    __table_args__ = (Index("ix_package_reviews_guide", "guide_id"),)

    id: Optional[int] = Field(default=None, primary_key=True)
    booking_id: int = Field(foreign_key="package_bookings.id", index=True)
    guide_id: int = Field(foreign_key="guides.id", index=True)
    package_id: Optional[int] = Field(default=None, foreign_key="guide_packages.id", index=True)
    user_id: Optional[int] = Field(default=None, foreign_key="users.id", index=True)
    rating: float = Field(ge=0.0, le=5.0)
    review_text: Optional[str] = Field(default=None, max_length=2000)


# -----------------------------------------------------------------------------
# Users & social
# -----------------------------------------------------------------------------


class TrustTier(str, enum.Enum):
    BASIC = "basic"
    ID_VERIFIED = "id_verified"
    ENHANCED = "enhanced"


class UserProfile(TimestampMixin, table=True):
    """Extended user profile for matching and personalization."""

    __tablename__ = "user_profiles"

    id: Optional[int] = Field(default=None, primary_key=True)
    user_id: int = Field(foreign_key="users.id", index=True, unique=True)
    bio: Optional[str] = Field(default=None, max_length=1000)
    photo_url: Optional[str] = Field(default=None, max_length=500)
    home_location: Optional[str] = Field(default=None, max_length=100)
    preferred_languages: list[str] = Field(default_factory=list, sa_column=Column(JSON))
    travel_style: Optional[str] = Field(default=None, max_length=50)


class UserInterest(TimestampMixin, table=True):
    """A user's explicit interest."""

    __tablename__ = "user_interests"
    __table_args__ = (UniqueConstraint("profile_id", "tag_name", name="uq_profile_interest"),)

    id: Optional[int] = Field(default=None, primary_key=True)
    profile_id: int = Field(foreign_key="user_profiles.id", index=True)
    tag_name: str = Field(max_length=80)
    weight: float = Field(default=1.0, ge=0.0, le=5.0)


# -----------------------------------------------------------------------------
# Personalization: taste signals, interactions and companion sessions
# -----------------------------------------------------------------------------

#: Interaction weights used to nudge the taste vector. ``complete`` is the
#: strongest positive; ``skip``/``dismiss`` are explicit negatives.
#:
#: Every meaningful action feeds the profile: a *like* (favourite), an
#: *add_to_itinerary* (intent to actually go), a *click*, a *visit* and a
#: *complete* all pull the taste vector toward that experience's tags, while
#: *unlike*/*remove_from_itinerary*/*skip*/*dismiss* pull it away.
INTERACTION_WEIGHTS: dict[str, float] = {
    "view": 0.1,
    "click": 0.2,
    "unlike": -0.3,
    "remove_from_itinerary": -0.3,
    "save": 0.4,
    "like": 0.5,
    "share": 0.5,
    "add_to_itinerary": 0.6,
    "start": 0.6,
    "visit": 0.8,
    "complete": 1.0,
    "skip": -0.2,
    "dismiss": -0.5,
}


class PreferenceSignal(TimestampMixin, table=True):
    """Explicit or implicit taste signal (PRD 4.6)."""

    __tablename__ = "preference_signals"
    __table_args__ = (Index("ix_preference_signals_user_created", "user_id", "created_at"),)

    id: Optional[int] = Field(default=None, primary_key=True)
    user_id: int = Field(foreign_key="users.id", index=True)
    #: onboarding | explicit | implicit | chat | visit
    signal_type: str = Field(default="implicit", max_length=20)
    experience_id: Optional[int] = Field(default=None, foreign_key="experiences.id", index=True)
    #: Free-text statement, e.g. onboarding or a chat sentence.
    text: Optional[str] = Field(default=None, max_length=1000)
    weight: float = Field(default=1.0)
    metadata_json: dict[str, Any] = Field(default_factory=dict, sa_column=Column(JSON))


class UserActivityInteraction(TimestampMixin, table=True):
    """Append-only record of what a user did with an experience (PRD 4.6)."""

    __tablename__ = "user_activity_interactions"
    __table_args__ = (Index("ix_user_activity_interactions_user_created", "user_id", "created_at"),)

    id: Optional[int] = Field(default=None, primary_key=True)
    user_id: int = Field(foreign_key="users.id", index=True)
    experience_id: int = Field(foreign_key="experiences.id", index=True)
    #: view | click | save | like | share | add_to_itinerary | start | visit |
    #: complete | skip | dismiss | unlike | remove_from_itinerary
    action: str = Field(default="view", max_length=30)
    weight: float = Field(default=0.0)
    metadata_json: dict[str, Any] = Field(default_factory=dict, sa_column=Column(JSON))


class ConversationSession(TimestampMixin, table=True):
    """Per-session state for the LocalIQ Companion / guide agent (PRD 4.7)."""

    __tablename__ = "conversation_sessions"
    __table_args__ = (Index("ix_conversation_sessions_user_active", "user_id", "last_active_at"),)

    id: Optional[int] = Field(default=None, primary_key=True)
    user_id: Optional[int] = Field(default=None, foreign_key="users.id", index=True)
    language: str = Field(default="en", max_length=8)
    messages_json: list[dict[str, Any]] = Field(default_factory=list, sa_column=Column(JSON))
    #: JSON-encoded constraints extracted so far (time, budget, interests...).
    state_json: dict[str, Any] = Field(default_factory=dict, sa_column=Column(JSON))
    last_active_at: Optional[datetime] = Field(default=None)


# -----------------------------------------------------------------------------
# Experience Wallet & Passport (PRD 4.9)
# -----------------------------------------------------------------------------


class ExperienceWallet(TimestampMixin, table=True):
    """Per-user rollup shown on the Passport (PRD 4.9)."""

    __tablename__ = "experience_wallets"

    id: Optional[int] = Field(default=None, primary_key=True)
    user_id: int = Field(foreign_key="users.id", index=True, unique=True)
    total_experiences: int = Field(default=0, ge=0)
    hidden_gem_count: int = Field(default=0, ge=0)
    total_spent_inr: int = Field(default=0, ge=0)
    total_duration_min: int = Field(default=0, ge=0)
    categories_json: dict[str, Any] = Field(default_factory=dict, sa_column=Column(JSON))
    cities_visited_json: dict[str, Any] = Field(default_factory=dict, sa_column=Column(JSON))


class ExperienceLog(TimestampMixin, table=True):
    """Append-only record of a completed experience (PRD 4.9).

    Unique per ``(user, experience)`` so re-marking "Done" updates the existing
    entry instead of double-counting the stats.
    """

    __tablename__ = "experience_logs"
    __table_args__ = (
        UniqueConstraint("user_id", "experience_id", name="uq_experience_log_user_experience"),
        Index("ix_experience_logs_user_completed", "user_id", "completed_at"),
    )

    id: Optional[int] = Field(default=None, primary_key=True)
    user_id: int = Field(foreign_key="users.id", index=True)
    experience_id: int = Field(foreign_key="experiences.id", index=True)
    completed_at: Optional[datetime] = Field(default=None)
    rating: Optional[float] = Field(default=None, ge=0.0, le=5.0)
    notes: Optional[str] = Field(default=None, max_length=2000)
    context_json: dict[str, Any] = Field(default_factory=dict, sa_column=Column(JSON))


class UserBadge(TimestampMixin, table=True):
    """One row per badge a user has earned (PRD 4.9)."""

    __tablename__ = "user_badges"
    __table_args__ = (
        UniqueConstraint("user_id", "badge_code", name="uq_user_badge_code"),
        Index("ix_user_badges_user_earned", "user_id", "earned_at"),
    )

    id: Optional[int] = Field(default=None, primary_key=True)
    user_id: int = Field(foreign_key="users.id", index=True)
    badge_code: str = Field(max_length=60, index=True)
    badge_id: Optional[int] = Field(default=None, foreign_key="badges.id")
    earned_at: Optional[datetime] = Field(default=None)
    context_json: dict[str, Any] = Field(default_factory=dict, sa_column=Column(JSON))


# -----------------------------------------------------------------------------
# AI Experience Director — live companion (PRD 4.10)
# -----------------------------------------------------------------------------


class ExperienceSession(TimestampMixin, table=True):
    """A live AI Director session across pre/during/post experience (PRD 4.10)."""

    __tablename__ = "experience_sessions"
    __table_args__ = (Index("ix_experience_sessions_user_status", "user_id", "status"),)

    id: Optional[int] = Field(default=None, primary_key=True)
    user_id: int = Field(foreign_key="users.id", index=True)
    experience_id: Optional[int] = Field(default=None, foreign_key="experiences.id", index=True)
    itinerary_id: Optional[int] = Field(default=None, foreign_key="itineraries.id", index=True)
    #: planned | active | completed | cancelled
    status: str = Field(default="active", max_length=20, index=True)
    language: str = Field(default="en", max_length=8)
    start_time: Optional[datetime] = Field(default=None)
    end_time: Optional[datetime] = Field(default=None)
    #: {"stops": [{"experience_id": int, "sequence": int}, ...]}
    route_json: dict[str, Any] = Field(default_factory=dict, sa_column=Column(JSON))
    #: {"shown_tip_ids": [...], "last_weather": {...}}
    live_context_json: dict[str, Any] = Field(default_factory=dict, sa_column=Column(JSON))
    summary_json: dict[str, Any] = Field(default_factory=dict, sa_column=Column(JSON))


class AITip(TimestampMixin, table=True):
    """A reusable, location-triggered tip for an experience (PRD 4.10)."""

    __tablename__ = "ai_tips"
    __table_args__ = (Index("ix_ai_tips_experience_category", "experience_id", "category"),)

    id: Optional[int] = Field(default=None, primary_key=True)
    experience_id: int = Field(foreign_key="experiences.id", index=True)
    #: history | photo | food | safety | routing
    category: str = Field(default="history", max_length=20)
    message_text: str = Field(default="", max_length=1000)
    language: str = Field(default="en", max_length=8)
    #: {"lat": float, "lng": float, "radius_m": int} — {} means "always".
    location_trigger_json: dict[str, Any] = Field(default_factory=dict, sa_column=Column(JSON))


# -----------------------------------------------------------------------------
# Guided onboarding (taste capture + guide supply onboarding)
# -----------------------------------------------------------------------------


class OnboardingSession(TimestampMixin, table=True):
    """A scripted onboarding conversation.

    ``kind="user"`` drives the taste-capture conversation (the "maître d'"
    experience); the answers are distilled into the user's taste vector.
    ``kind="guide"`` optionally tracks a guide application.
    """

    __tablename__ = "onboarding_sessions"
    __table_args__ = (
        Index("ix_onboarding_sessions_user_kind", "user_id", "kind", "status"),
    )

    id: Optional[int] = Field(default=None, primary_key=True)
    user_id: int = Field(foreign_key="users.id", index=True)
    #: "user" | "guide"
    kind: str = Field(default="user", max_length=20, index=True)
    #: in_progress | completed | abandoned
    status: str = Field(default="in_progress", max_length=20, index=True)
    step: int = Field(default=0, ge=0)
    language: str = Field(default="en", max_length=8)
    #: [{role, text, at}, ...] — the rendered transcript.
    messages_json: list[dict[str, Any]] = Field(default_factory=list, sa_column=Column(JSON))
    #: {step_key: raw_answer}
    answers_json: dict[str, Any] = Field(default_factory=dict, sa_column=Column(JSON))
    #: Taste signals derived from the conversation.
    extracted_json: dict[str, Any] = Field(default_factory=dict, sa_column=Column(JSON))
    completed_at: Optional[datetime] = Field(default=None)


# -----------------------------------------------------------------------------
# Conversations, chat messages and agent runs
# -----------------------------------------------------------------------------


class ConversationKind(str, enum.Enum):
    """What a conversation thread is for."""

    GENERAL = "general"
    TRAVEL_BUDDY = "travel_buddy"
    GUIDE = "guide"
    MEETUP = "meetup"


class Conversation(TimestampMixin, table=True):
    """A chat thread between a user and another party (agent, guide, meetup)."""

    __tablename__ = "conversations"
    __table_args__ = (
        Index("ix_conversations_user_kind", "user_id", "kind", "created_at"),
    )

    id: Optional[int] = Field(default=None, primary_key=True)
    user_id: int = Field(foreign_key="users.id", index=True)
    #: general | travel_buddy | guide | meetup
    kind: str = Field(default=ConversationKind.GENERAL.value, max_length=20, index=True)
    #: For guide/meetup chats: the foreign entity id lives in data_json.
    data_json: dict[str, Any] = Field(default_factory=dict, sa_column=Column(JSON))
    title: Optional[str] = Field(default=None, max_length=160)

    messages: list["Message"] = Relationship(
        back_populates="conversation",
        sa_relationship_kwargs={"cascade": "all, delete-orphan", "order_by": "Message.created_at"},
    )


class MessageRole(str, enum.Enum):
    """Speaker in a conversation."""

    USER = "user"
    ASSISTANT = "assistant"
    TOOL = "tool"


class Message(TimestampMixin, table=True):
    """A single chat message."""

    __tablename__ = "messages"
    __table_args__ = (
        Index("ix_messages_conversation_created", "conversation_id", "created_at"),
    )

    id: Optional[int] = Field(default=None, primary_key=True)
    conversation_id: int = Field(foreign_key="conversations.id", index=True)
    role: str = Field(default=MessageRole.USER.value, max_length=20, index=True)
    content: str = Field(default="", max_length=4000)
    #: Optional tool call/request metadata for agent messages.
    tool_json: dict[str, Any] = Field(default_factory=dict, sa_column=Column(JSON))

    conversation: Optional["Conversation"] = Relationship(back_populates="messages")


class AgentRun(TimestampMixin, table=True):
    """One agentic turn: the LLM call, any tool calls it made, and the final
    response. Linked to a conversation so the user can review what happened."""

    __tablename__ = "agent_runs"
    __table_args__ = (
        Index("ix_agent_runs_user_created", "user_id", "created_at"),
        Index("ix_agent_runs_conversation", "conversation_id", "created_at"),
    )

    id: Optional[int] = Field(default=None, primary_key=True)
    user_id: int = Field(foreign_key="users.id", index=True)
    conversation_id: Optional[int] = Field(default=None, foreign_key="conversations.id", index=True)
    #: pending | running | completed | failed
    status: str = Field(default="pending", max_length=20, index=True)
    #: The raw tool calls the LLM emitted.
    tool_calls_json: list[dict[str, Any]] = Field(default_factory=list, sa_column=Column(JSON))
    #: The final assistant message (or error string on failure).
    result: Optional[str] = Field(default=None, max_length=4000)

