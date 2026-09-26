"""PRD v2 journey models.

Appended to the LocalIQ schema for the User + Guide journeys (PRD v2 sections
4-6). Everything is Phase 1 / MVP scoped:

* verification is **simulated** (a status field, never a real ID document);
* person-to-person matching is deterministic compatibility scoring over
  preferences, not a live stranger-safety service;
* guide payments are a status field only, no money moves;
* badges/XP are deterministic functions of completed activity.

Every table uses the shared :class:`TimestampMixin`, so `created_at` /
`updated_at` behave exactly like the pre-existing tables.
"""

from __future__ import annotations

from datetime import date as date_type
from datetime import datetime
from typing import Optional

from sqlalchemy import JSON, Column, Date, DateTime, Index, UniqueConstraint
from sqlmodel import Field, SQLModel

from app.models import Experience, Guide, TimestampMixin, User


# ---------------------------------------------------------------------------
# Enums are stored as plain strings so SQLite stays simple and the API can
# return the exact state names. Valid transitions live in
# ``app.services.journey_rules`` and are enforced server-side.
# ---------------------------------------------------------------------------


class GuideProfile(TimestampMixin, table=True):
    """Onboarding + verification + growth state for a guide.

    Separate from :class:`Guide` so the pre-existing guide table and its API
    stay untouched.
    """

    __tablename__ = "guide_profiles"  # type: ignore[assignment]

    id: Optional[int] = Field(default=None, primary_key=True)
    guide_id: int = Field(foreign_key="guides.id", index=True, unique=True)
    user_id: Optional[int] = Field(default=None, foreign_key="users.id", index=True)

    # 1. signup -> 2. id_uploaded -> 3. verified -> 4. active
    onboarding_state: str = Field(default="signup", index=True)
    # simulated: unverified | pending | verified | rejected
    verification_status: str = Field(default="unverified", index=True)
    #: simulated trust tier: basic | standard | trusted
    verification_tier: str = Field(default="basic")
    #: Only metadata, never a document: type + last-4 reference for the demo.
    id_document_type: Optional[str] = Field(default=None)
    id_document_reference: Optional[str] = Field(default=None)
    verified_at: Optional[datetime] = Field(default=None, sa_type=DateTime)

    # Growth
    tier: str = Field(default="bronze", index=True)
    xp: int = Field(default=0)
    completed_tours: int = Field(default=0)
    review_count: int = Field(default=0)
    rating_sum: float = Field(default=0.0)
    bio: str = Field(default="")
    city: str = Field(default="Mumbai")
    #: Visibility multiplier + unlocked features are derived from tier.
    is_published: bool = Field(default=False)


class GuideAvailability(TimestampMixin, table=True):
    """A bookable window for a guide."""

    __tablename__ = "guide_availability"  # type: ignore[assignment]
    __table_args__ = (
        Index("ix_guide_availability_guide_date", "guide_id", "date"),
        UniqueConstraint("guide_id", "date", "start_time", name="uq_guide_slot"),
    )

    id: Optional[int] = Field(default=None, primary_key=True)
    guide_id: int = Field(foreign_key="guides.id", index=True)
    date: date_type = Field(sa_type=Date, index=True)
    start_time: str = Field(default="10:00")
    end_time: str = Field(default="12:00")
    max_group_size: int = Field(default=6, ge=1, le=20)
    is_booked: bool = Field(default=False)
    note: str = Field(default="")


class GuideBooking(TimestampMixin, table=True):
    """Guide booking lifecycle (journey 4 + journey 7)."""

    __tablename__ = "guide_bookings"  # type: ignore[assignment]

    id: Optional[int] = Field(default=None, primary_key=True)
    user_id: int = Field(foreign_key="users.id", index=True)
    guide_id: int = Field(foreign_key="guides.id", index=True)
    experience_id: Optional[int] = Field(default=None, foreign_key="experiences.id", index=True)
    availability_id: Optional[int] = Field(
        default=None, foreign_key="guide_availability.id", index=True
    )

    date: date_type = Field(sa_type=Date)
    start_time: str = Field(default="10:00")
    duration_min: int = Field(default=120, ge=30, le=480)
    group_size: int = Field(default=2, ge=1, le=20)

    # requested -> accepted -> confirmed -> in_progress -> completed
    #            -> declined | cancelled
    status: str = Field(default="requested", index=True)
    #: mocked only: pending | settled | refunded
    payment_status: str = Field(default="pending")

    hourly_rate: int = Field(default=0)
    total_cost: int = Field(default=0)
    currency: str = Field(default="INR")
    notes: str = Field(default="")

    requested_at: Optional[datetime] = Field(default=None, sa_type=DateTime)
    accepted_at: Optional[datetime] = Field(default=None, sa_type=DateTime)
    confirmed_at: Optional[datetime] = Field(default=None, sa_type=DateTime)
    started_at: Optional[datetime] = Field(default=None, sa_type=DateTime)
    completed_at: Optional[datetime] = Field(default=None, sa_type=DateTime)
    closed_at: Optional[datetime] = Field(default=None, sa_type=DateTime)
    decline_reason: str = Field(default="")


class GuideReview(TimestampMixin, table=True):
    """Post-tour review. One per booking per reviewer."""

    __tablename__ = "guide_reviews"  # type: ignore[assignment]
    __table_args__ = (
        UniqueConstraint("booking_id", "user_id", name="uq_guide_review_per_user"),
    )

    id: Optional[int] = Field(default=None, primary_key=True)
    booking_id: int = Field(foreign_key="guide_bookings.id", index=True)
    user_id: int = Field(foreign_key="users.id", index=True)
    guide_id: int = Field(foreign_key="guides.id", index=True)
    rating: int = Field(ge=1, le=5)
    comment: str = Field(default="")
    #: Simulated safety/quality signals surfaced in the guide growth view.
    punctuality: int = Field(default=0, ge=0, le=5)
    knowledge: int = Field(default=0, ge=0, le=5)


class GuideTraining(TimestampMixin, table=True):
    """Training / certification progress (journey 8)."""

    __tablename__ = "guide_trainings"  # type: ignore[assignment]
    __table_args__ = (
        UniqueConstraint("guide_id", "course_code", name="uq_guide_course"),
    )

    id: Optional[int] = Field(default=None, primary_key=True)
    guide_id: int = Field(foreign_key="guides.id", index=True)
    course_code: str = Field(index=True)
    course_name: str = Field(default="")
    #: not_started | in_progress | completed
    status: str = Field(default="not_started", index=True)
    score: int = Field(default=0, ge=0, le=100)
    completed_at: Optional[datetime] = Field(default=None, sa_type=DateTime)
    #: certification granted once the course is completed and passed
    grants_tier: Optional[str] = Field(default=None)


class MeetupRequest(TimestampMixin, table=True):
    """A traveller asking to be matched (journey 2)."""

    __tablename__ = "meetup_requests"  # type: ignore[assignment]

    id: Optional[int] = Field(default=None, primary_key=True)
    user_id: int = Field(foreign_key="users.id", index=True)
    experience_id: Optional[int] = Field(default=None, foreign_key="experiences.id", index=True)
    category: str = Field(default="food", index=True)
    area: str = Field(default="Bandra, Mumbai")
    lat: float = Field(default=19.0596)
    lng: float = Field(default=72.8295)
    start_time: str = Field(default="18:00")
    duration_min: int = Field(default=120, ge=30, le=600)
    budget_inr: int = Field(default=800, ge=0)
    group_size_pref: int = Field(default=3, ge=2, le=5)
    interests: list[str] = Field(default_factory=list, sa_column=Column(JSON))
    note: str = Field(default="")
    #: open | matched | expired | cancelled
    status: str = Field(default="open", index=True)
    expires_at: Optional[datetime] = Field(default=None, sa_type=DateTime)


class MeetupMatch(TimestampMixin, table=True):
    """A formed micro-group around a shared experience."""

    __tablename__ = "meetup_matches"  # type: ignore[assignment]

    id: Optional[int] = Field(default=None, primary_key=True)
    request_id: int = Field(foreign_key="meetup_requests.id", index=True)
    experience_id: Optional[int] = Field(default=None, foreign_key="experiences.id", index=True)
    member_ids: list[int] = Field(default_factory=list, sa_column=Column(JSON))
    compatibility_score: float = Field(default=0.0, ge=0.0, le=100.0)
    shared_interests: list[str] = Field(default_factory=list, sa_column=Column(JSON))
    plan: dict = Field(default_factory=dict, sa_column=Column(JSON))
    meeting_point: str = Field(default="")
    safety_score: int = Field(default=0, ge=0, le=100)
    start_time: str = Field(default="18:00")
    duration_min: int = Field(default=120)
    total_cost: int = Field(default=0)
    #: formed | confirmed | completed | expired | cancelled
    status: str = Field(default="formed", index=True)
    keep_group: bool = Field(default=False)


class MeetupReview(TimestampMixin, table=True):
    """Post-meetup rating of the *experience* (not of each other)."""

    __tablename__ = "meetup_reviews"  # type: ignore[assignment]
    __table_args__ = (
        UniqueConstraint("match_id", "user_id", name="uq_meetup_review_per_user"),
    )

    id: Optional[int] = Field(default=None, primary_key=True)
    match_id: int = Field(foreign_key="meetup_matches.id", index=True)
    user_id: int = Field(foreign_key="users.id", index=True)
    experience_rating: int = Field(ge=1, le=5)
    would_repeat: bool = Field(default=True)
    comment: str = Field(default="")


class MeetupBlock(TimestampMixin, table=True):
    """Block / report state. Blocking prevents future matching."""

    __tablename__ = "meetup_blocks"  # type: ignore[assignment]
    __table_args__ = (
        UniqueConstraint("blocker_id", "blocked_id", name="uq_meetup_block"),
    )

    id: Optional[int] = Field(default=None, primary_key=True)
    blocker_id: int = Field(foreign_key="users.id", index=True)
    blocked_id: int = Field(foreign_key="users.id", index=True)
    reason: str = Field(default="")
    reported: bool = Field(default=False)


class Group(TimestampMixin, table=True):
    """A decision group (journey 3)."""

    __tablename__ = "groups"  # type: ignore[assignment]

    id: Optional[int] = Field(default=None, primary_key=True)
    name: str = Field(default="Trip group")
    owner_id: int = Field(foreign_key="users.id", index=True)
    area: str = Field(default="Bandra, Mumbai")
    lat: float = Field(default=19.0596)
    lng: float = Field(default=72.8295)
    time_hours: float = Field(default=3.0, ge=0.5, le=24)
    budget_inr: int = Field(default=2000, ge=0)
    interests: list[str] = Field(default_factory=list, sa_column=Column(JSON))
    accessibility: bool = Field(default=False)
    #: collecting_preferences | collecting_votes | locked | cancelled
    status: str = Field(default="collecting_preferences", index=True)
    max_members: int = Field(default=8, ge=2, le=20)
    final_plan: dict = Field(default_factory=dict, sa_column=Column(JSON))
    locked_at: Optional[datetime] = Field(default=None, sa_type=DateTime)


class GroupMember(TimestampMixin, table=True):
    __tablename__ = "group_members"  # type: ignore[assignment]
    __table_args__ = (
        UniqueConstraint("group_id", "user_id", name="uq_group_member"),
    )

    id: Optional[int] = Field(default=None, primary_key=True)
    group_id: int = Field(foreign_key="groups.id", index=True)
    user_id: int = Field(foreign_key="users.id", index=True)
    is_owner: bool = Field(default=False)
    interests: list[str] = Field(default_factory=list, sa_column=Column(JSON))
    budget_inr: int = Field(default=1000, ge=0)
    time_hours: float = Field(default=3.0, ge=0.5, le=24)
    accessibility: bool = Field(default=False)
    has_voted: bool = Field(default=False)


class GroupOption(TimestampMixin, table=True):
    """A candidate plan the group votes on."""

    __tablename__ = "group_options"  # type: ignore[assignment]

    id: Optional[int] = Field(default=None, primary_key=True)
    group_id: int = Field(foreign_key="groups.id", index=True)
    label: str = Field(default="Option")
    rank: int = Field(default=0)
    score: float = Field(default=0.0)
    stops: list[int] = Field(default_factory=list, sa_column=Column(JSON))
    total_minutes: int = Field(default=0)
    total_cost: int = Field(default=0)
    votes: int = Field(default=0)
    is_winner: bool = Field(default=False)


class GroupVote(TimestampMixin, table=True):
    __tablename__ = "group_votes"  # type: ignore[assignment]
    __table_args__ = (
        UniqueConstraint("group_id", "user_id", name="uq_group_vote"),
    )

    id: Optional[int] = Field(default=None, primary_key=True)
    group_id: int = Field(foreign_key="groups.id", index=True)
    option_id: int = Field(foreign_key="group_options.id", index=True)
    user_id: int = Field(foreign_key="users.id", index=True)
    rank: int = Field(default=1, ge=1, le=5)
    comment: str = Field(default="")


class Quest(TimestampMixin, table=True):
    """A hidden-gem quest (journey 5)."""

    __tablename__ = "quests"  # type: ignore[assignment]

    id: Optional[int] = Field(default=None, primary_key=True)
    code: str = Field(index=True, unique=True)
    title: str = Field(default="Quest")
    story: str = Field(default="")
    category: str = Field(default="outdoor", index=True)
    difficulty: str = Field(default="easy")  # easy | medium | hard
    xp_reward: int = Field(default=100, ge=0)
    estimated_minutes: int = Field(default=120)
    estimated_cost: int = Field(default=500)
    is_active: bool = Field(default=True, index=True)


class QuestStop(TimestampMixin, table=True):
    __tablename__ = "quest_stops"  # type: ignore[assignment]
    __table_args__ = (
        UniqueConstraint("quest_id", "position", name="uq_quest_stop_position"),
    )

    id: Optional[int] = Field(default=None, primary_key=True)
    quest_id: int = Field(foreign_key="quests.id", index=True)
    experience_id: int = Field(foreign_key="experiences.id", index=True)
    position: int = Field(default=1)
    hint: str = Field(default="")


class QuestRun(TimestampMixin, table=True):
    """One traveller's attempt at a quest, with the feasible plan and progress."""

    __tablename__ = "quest_runs"  # type: ignore[assignment]
    __table_args__ = (Index("ix_quest_runs_user_status", "user_id", "status"),)

    id: Optional[int] = Field(default=None, primary_key=True)
    quest_id: int = Field(foreign_key="quests.id", index=True)
    user_id: int = Field(foreign_key="users.id", index=True)
    #: available | in_progress | completed | abandoned
    status: str = Field(default="in_progress", index=True)
    time_hours: float = Field(default=3.0)
    budget_inr: int = Field(default=1000)
    #: {"stops": [experience_id...], "dropped": [names], "total_minutes": int}
    plan: dict = Field(default_factory=dict, sa_column=Column(JSON))
    completed_stops: list[int] = Field(default_factory=list, sa_column=Column(JSON))
    xp_awarded: int = Field(default=0)
    badges_earned: list[dict] = Field(default_factory=list, sa_column=Column(JSON))
    started_at: Optional[datetime] = Field(default=None, sa_type=DateTime)
    completed_at: Optional[datetime] = Field(default=None, sa_type=DateTime)


class UserProgress(TimestampMixin, table=True):
    """XP, level and badges for a traveller."""

    __tablename__ = "user_progress"  # type: ignore[assignment]

    id: Optional[int] = Field(default=None, primary_key=True)
    user_id: int = Field(foreign_key="users.id", index=True, unique=True)
    xp: int = Field(default=0, ge=0)
    level: int = Field(default=1, ge=1)
    badges: list[str] = Field(default_factory=list, sa_column=Column(JSON))
    quests_completed: int = Field(default=0)
    quests_started: int = Field(default=0)


class Badge(TimestampMixin, table=True):
    """Badge catalogue. Awarded automatically by journey completion."""

    __tablename__ = "badges"  # type: ignore[assignment]

    id: Optional[int] = Field(default=None, primary_key=True)
    code: str = Field(index=True, unique=True)
    name: str = Field(default="Badge")
    description: str = Field(default="")
    xp_bonus: int = Field(default=0)
    tier: str = Field(default="bronze")


class HiddenGemCandidate(TimestampMixin, table=True):
    """A crowd-sourced gem awaiting review/promotion."""

    __tablename__ = "hidden_gem_candidates"  # type: ignore[assignment]

    id: Optional[int] = Field(default=None, primary_key=True)
    name: str = Field(index=True)
    lat: float
    lng: float
    area: str = Field(default="")
    category: str = Field(default="culture")
    submitted_by: Optional[int] = Field(default=None, foreign_key="users.id", index=True)
    source_id: Optional[int] = Field(default=None, foreign_key="sources.id", index=True)
    votes: int = Field(default=0)
    #: pending | approved | rejected
    status: str = Field(default="pending", index=True)
    promoted_experience_id: Optional[int] = Field(
        default=None, foreign_key="experiences.id", index=True
    )
    note: str = Field(default="")


class Source(TimestampMixin, table=True):
    """Where a hidden-gem candidate came from (PRD v2 data model)."""

    __tablename__ = "sources"  # type: ignore[assignment]

    id: Optional[int] = Field(default=None, primary_key=True)
    name: str = Field(index=True)
    kind: str = Field(default="manual")  # manual | reddit | blog | guide
    url: str = Field(default="")
    is_active: bool = Field(default=True)


class Mention(TimestampMixin, table=True):
    """Polymorphic @mention of a user inside generated content."""

    __tablename__ = "mentions"  # type: ignore[assignment]

    id: Optional[int] = Field(default=None, primary_key=True)
    content_type: str = Field(default="quest")
    content_id: int = Field(default=0, index=True)
    user_id: int = Field(foreign_key="users.id", index=True)
    text: str = Field(default="")
