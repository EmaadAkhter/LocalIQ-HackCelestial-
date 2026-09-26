"""Database models for LocalIQ.

All tables carry ``created_at`` / ``updated_at`` (naive UTC) via
``TimestampMixin``. Composite indexes cover the common query shapes.
"""

from datetime import datetime
from typing import Optional

from sqlalchemy import JSON, Column, DateTime, Index
from sqlmodel import Field, Relationship, SQLModel

from app.timeutil import utcnow


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


class Experience(TimestampMixin, table=True):
    """Mumbai experience model."""

    __tablename__ = "experiences"  # type: ignore[assignment]
    __table_args__ = (
        Index("ix_experiences_category_rating", "category", "rating"),
        Index("ix_experiences_lat_lng", "lat", "lng"),
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
    tags: list[str] = Field(default_factory=list, sa_column=Column(JSON))
    accessibility_flags: list[str] = Field(default_factory=list, sa_column=Column(JSON))
    indoor_outdoor: str = Field(default="indoor")
    local_gem_score: float = Field(default=0.5, ge=0.0, le=1.0)

    guides: list["Guide"] = Relationship(back_populates="experience")


class Guide(TimestampMixin, table=True):
    """Local guide model."""

    __tablename__ = "guides"  # type: ignore[assignment]
    __table_args__ = (Index("ix_guides_experience_rating", "experience_id", "rating"),)

    id: Optional[int] = Field(default=None, primary_key=True)
    experience_id: Optional[int] = Field(default=None, foreign_key="experiences.id", index=True)
    name: str
    photo: Optional[str] = Field(default=None)
    languages: list[str] = Field(default_factory=list, sa_column=Column(JSON))
    specialty: str = Field(default="local culture")
    rate_per_hour: int = Field(default=800, ge=0)
    rating: float = Field(default=4.5, ge=0.0, le=5.0)

    experience: Optional["Experience"] = Relationship(back_populates="guides")


class User(TimestampMixin, table=True):
    """Local account. Password is stored only as a PBKDF2 hash."""

    __tablename__ = "users"  # type: ignore[assignment]

    id: Optional[int] = Field(default=None, primary_key=True)
    name: str = Field(index=True)
    email: str = Field(index=True, unique=True)
    password_hash: str
    group_type: Optional[str] = Field(default=None)

    sessions: list["UserSession"] = Relationship(back_populates="user")


class UserSession(TimestampMixin, table=True):
    """Persisted session. Only the SHA-256 hash of the token is stored."""

    __tablename__ = "user_sessions"  # type: ignore[assignment]
    __table_args__ = (Index("ix_user_sessions_user_expires", "user_id", "expires_at"),)

    id: Optional[int] = Field(default=None, primary_key=True)
    user_id: int = Field(foreign_key="users.id", index=True)
    token_hash: str = Field(index=True, unique=True)
    expires_at: datetime = Field(sa_type=DateTime, sa_column_kwargs={"nullable": False})

    user: Optional["User"] = Relationship(back_populates="sessions")


class GuideRequest(TimestampMixin, table=True):
    """Persisted guide booking request (no payments, demo only)."""

    __tablename__ = "guide_requests"  # type: ignore[assignment]
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
    status: str = Field(default="confirmed_mock")
    booking_ref: str = Field(index=True)


class Itinerary(TimestampMixin, table=True):
    """Optional itinerary container (secondary, hackathon-optional)."""

    __tablename__ = "itineraries"  # type: ignore[assignment]

    id: Optional[int] = Field(default=None, primary_key=True)
    name: str = Field(default="My Mumbai Day")
    total_duration_min: int = Field(default=0)
    total_cost: int = Field(default=0)

    stops: list["ItineraryStop"] = Relationship(back_populates="itinerary")


class ItineraryStop(TimestampMixin, table=True):
    """Optional itinerary stop (secondary, hackathon-optional)."""

    __tablename__ = "itinerary_stops"  # type: ignore[assignment]
    __table_args__ = (Index("ix_itinerary_stops_itinerary_seq", "itinerary_id", "sequence"),)

    id: Optional[int] = Field(default=None, primary_key=True)
    itinerary_id: int = Field(foreign_key="itineraries.id", index=True)
    experience_id: int = Field(foreign_key="experiences.id", index=True)
    sequence: int = Field(default=0)
    start_time: str = Field(default="")
    end_time: str = Field(default="")
    travel_time_min: int = Field(default=0)

    itinerary: Optional["Itinerary"] = Relationship(back_populates="stops")
