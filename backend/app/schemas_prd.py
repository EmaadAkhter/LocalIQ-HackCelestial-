"""Pydantic schemas for the PRD v2 journeys (sections 4-6).

Kept separate from ``app.schemas`` (the pre-existing API contracts) so nothing
that already works changes shape.
"""

from __future__ import annotations

from datetime import date, datetime
from typing import Any, Literal

from pydantic import BaseModel, Field

# ---------------------------------------------------------------------------
# Shared
# ---------------------------------------------------------------------------


class TrustGate(BaseModel):
    action: str
    required_tier: str
    current_tier: str
    allowed: bool


class SoloRecommendation(BaseModel):
    experience: dict
    score: float
    why: str
    solo_friendly: bool
    solo_reasons: list[str] = Field(default_factory=list)


class SoloSearchRequest(BaseModel):
    location: str = Field(default="Bandra, Mumbai", max_length=100)
    time_hours: float = Field(default=3, ge=0.5, le=24)
    budget_inr: int = Field(default=800, ge=0)
    interests: list[str] = Field(default_factory=list)
    accessibility: bool = False
    #: Optional AI companion state (mock; no model call in Phase 1).
    companion_enabled: bool = False
    companion_personality: str = "chill_friend"
    limit: int = Field(default=8, ge=1, le=20)


class SoloSearchResponse(BaseModel):
    mode: str = "solo"
    location: str
    time_hours: float
    budget_inr: int
    companion: dict
    total_recommendations: int
    solo_friendly_count: int
    results: list[SoloRecommendation] = Field(default_factory=list)


class CompanionStateRequest(BaseModel):
    enabled: bool
    personality: str = "chill_friend"


# ---------------------------------------------------------------------------
# Meetup
# ---------------------------------------------------------------------------


class MeetupRequestCreate(BaseModel):
    category: str = Field(default="food", max_length=40)
    experience_id: int | None = None
    area: str = Field(default="Bandra, Mumbai", max_length=120)
    lat: float = Field(default=19.0596, ge=-90, le=90)
    lng: float = Field(default=72.8777, ge=-180, le=180)
    start_time: str = Field(default="18:00", pattern=r"^\d{2}:\d{2}$")
    duration_min: int = Field(default=120, ge=30, le=600)
    budget_inr: int = Field(default=800, ge=0)
    group_size_pref: int = Field(default=3, ge=2, le=5)
    interests: list[str] = Field(default_factory=list)
    note: str = Field(default="", max_length=500)
    expires_in_hours: int = Field(default=48, ge=1, le=720)


class MeetupRequestResponse(BaseModel):
    id: int
    user_id: int
    status: str
    category: str
    area: str
    start_time: str
    duration_min: int
    budget_inr: int
    group_size_pref: int
    interests: list[str]
    trust_gate: TrustGate | None = None
    created_at: datetime
    expires_at: datetime | None = None


class MatchCandidate(BaseModel):
    user_id: int
    name: str
    compatibility: dict
    shared_interests: list[str]
    eligible: bool
    reason: str


class MeetupMatchRequest(BaseModel):
    """Optional: name the people to match with.

    Leave it empty and the server picks the best eligible candidates it already
    ranked, which is the default the journey describes.
    """

    member_ids: list[int] = Field(default_factory=list)


class MeetupMatchResponse(BaseModel):
    id: int
    request_id: int
    status: str
    experience: dict | None = None
    member_ids: list[int]
    member_names: list[str] = Field(default_factory=list)
    compatibility_score: float
    shared_interests: list[str]
    plan: dict
    meeting_point: str
    safety: dict
    start_time: str
    duration_min: int
    total_cost: int
    keep_group: bool = False


class MeetupStatusRequest(BaseModel):
    status: Literal["confirmed", "completed", "cancelled"]


class MeetupReviewCreate(BaseModel):
    experience_rating: int = Field(ge=1, le=5)
    would_repeat: bool = True
    comment: str = Field(default="", max_length=500)


class MeetupReviewResponse(BaseModel):
    id: int
    match_id: int
    user_id: int
    experience_rating: int
    would_repeat: bool
    comment: str
    created_at: datetime


class BlockCreate(BaseModel):
    blocked_id: int
    reason: str = Field(default="", max_length=300)
    report: bool = False


class BlockResponse(BaseModel):
    blocker_id: int
    blocked_id: int
    reason: str
    reported: bool


# ---------------------------------------------------------------------------
# Groups
# ---------------------------------------------------------------------------


class GroupCreate(BaseModel):
    name: str = Field(default="My group", max_length=80)
    area: str = Field(default="Bandra, Mumbai", max_length=120)
    time_hours: float = Field(default=3, ge=0.5, le=24)
    budget_inr: int = Field(default=2000, ge=0)
    interests: list[str] = Field(default_factory=list)
    accessibility: bool = False
    max_members: int = Field(default=8, ge=2, le=20)


class GroupPreferences(BaseModel):
    interests: list[str] = Field(default_factory=list)
    budget_inr: int = Field(default=1000, ge=0)
    time_hours: float = Field(default=3, ge=0.5, le=24)
    accessibility: bool = False


class GroupResponse(BaseModel):
    id: int
    name: str
    owner_id: int
    status: str
    area: str
    time_hours: float
    budget_inr: int
    interests: list[str]
    accessibility: bool
    max_members: int
    member_count: int
    aggregated: dict = Field(default_factory=dict)
    final_plan: dict | None = None
    locked_at: datetime | None = None
    options: list["GroupOptionResponse"] = Field(default_factory=list)
    votes_cast: int = 0
    quorum_reached: bool = False


class GroupMemberResponse(BaseModel):
    user_id: int
    name: str
    is_owner: bool
    interests: list[str]
    budget_inr: int
    time_hours: float
    accessibility: bool
    has_voted: bool


class GroupOptionResponse(BaseModel):
    id: int
    label: str
    rank: int
    score: float
    stops: list[int]
    total_minutes: int
    total_cost: int
    votes: int
    is_winner: bool


class GroupVoteCreate(BaseModel):
    option_id: int
    rank: int = Field(default=1, ge=1, le=5)
    comment: str = Field(default="", max_length=300)


class GroupVoteResponse(BaseModel):
    id: int
    group_id: int
    option_id: int
    user_id: int
    rank: int
    comment: str
    created_at: datetime


class GroupVoteTally(BaseModel):
    group_id: int
    status: str
    member_count: int
    votes_cast: int
    quorum_reached: bool
    winner_option_id: int | None = None
    tie: bool = False
    tally: list[dict] = Field(default_factory=list)
    final_plan: dict | None = None


# ---------------------------------------------------------------------------
# Guide onboarding / verification
# ---------------------------------------------------------------------------


class GuideOnboardStart(BaseModel):
    user_id: int | None = None
    name: str = Field(..., min_length=2, max_length=80)
    specialty: str = Field(default="local culture", max_length=120)
    languages: list[str] = Field(default_factory=list)
    city: str = Field(default="Mumbai", max_length=60)
    bio: str = Field(default="", max_length=600)
    rate_per_hour: int = Field(default=800, ge=0, le=10000)
    photo: str | None = None


class GuideIdUpload(BaseModel):
    """Simulated verification. Metadata only - never a real ID file."""

    document_type: Literal["aadhaar", "passport", "voter_id", "driving_licence"] = "aadhaar"
    #: Free-text reference the reviewer would look up. Not a document.
    document_reference: str = Field(..., min_length=4, max_length=32)
    #: Demo switch: 'approve' / 'reject'. There is no automated KYC in Phase 1.
    simulated_outcome: Literal["approve", "reject"] = "approve"


class GuideProfileResponse(BaseModel):
    guide_id: int
    name: str
    onboarding_state: str
    verification_status: str
    verification_tier: str
    tier: str
    xp: int
    completed_tours: int
    review_count: int
    average_rating: float
    is_published: bool
    features: list[str] = Field(default_factory=list)
    visibility_boost: float = 1.0
    next_tier: str | None = None
    certifications: list[str] = Field(default_factory=list)
    trainings: list[dict] = Field(default_factory=list)
    can_accept_bookings: bool = False


class GuideAvailabilityCreate(BaseModel):
    date: date
    start_time: str = Field(default="10:00", pattern=r"^\d{2}:\d{2}$")
    end_time: str = Field(default="12:00", pattern=r"^\d{2}:\d{2}$")
    max_group_size: int = Field(default=6, ge=1, le=20)
    note: str = Field(default="", max_length=200)


class GuideAvailabilityResponse(BaseModel):
    id: int
    guide_id: int
    date: date
    start_time: str
    end_time: str
    max_group_size: int
    is_booked: bool
    note: str


# ---------------------------------------------------------------------------
# Guide booking
# ---------------------------------------------------------------------------


class GuideBookingCreate(BaseModel):
    guide_id: int
    experience_id: int | None = None
    availability_id: int | None = None
    date: date
    start_time: str = Field(default="10:00", pattern=r"^\d{2}:\d{2}$")
    duration_min: int = Field(default=120, ge=30, le=480)
    group_size: int = Field(default=2, ge=1, le=20)
    notes: str = Field(default="", max_length=500)
    #: Optional per-head surcharge beyond the time charge.
    extras_per_head: int = Field(default=0, ge=0, le=5000)


class GuideBookingQuote(BaseModel):
    guide_id: int
    hourly_rate: int
    duration_min: int
    group_size: int
    charged_hours: int
    extras_per_head: int
    total_cost: int
    currency: str = "INR"


class GuideBookingResponse(BaseModel):
    id: int
    user_id: int
    guide_id: int
    guide_name: str | None = None
    experience_id: int | None = None
    date: date
    start_time: str
    duration_min: int
    group_size: int
    status: str
    payment_status: str
    hourly_rate: int
    total_cost: int
    currency: str
    notes: str
    allowed_transitions: list[str] = Field(default_factory=list)
    created_at: datetime
    decline_reason: str = ""
    reviewed: bool = False


class GuideBookingTransition(BaseModel):
    status: Literal[
        "accepted", "declined", "confirmed", "cancelled", "in_progress", "completed"
    ]
    reason: str = Field(default="", max_length=300)
    #: Mock payment transition; no money moves in Phase 1.
    payment_status: Literal["pending", "settled", "refunded"] | None = None


class GuideReviewCreate(BaseModel):
    rating: int = Field(ge=1, le=5)
    comment: str = Field(default="", max_length=500)
    punctuality: int = Field(default=0, ge=0, le=5)
    knowledge: int = Field(default=0, ge=0, le=5)


class GuideReviewResponse(BaseModel):
    id: int
    booking_id: int
    guide_id: int
    user_id: int
    rating: int
    comment: str
    punctuality: int
    knowledge: int
    created_at: datetime


# ---------------------------------------------------------------------------
# Guide growth
# ---------------------------------------------------------------------------


class GuideTrainingCreate(BaseModel):
    course_code: str = Field(..., min_length=2, max_length=40)
    course_name: str = Field(default="", max_length=120)
    grants_tier: str | None = None


class GuideTrainingResponse(BaseModel):
    id: int
    guide_id: int
    course_code: str
    course_name: str
    status: str
    score: int
    grants_tier: str | None = None
    completed_at: datetime | None = None


class GuideTrainingComplete(BaseModel):
    score: int = Field(default=80, ge=0, le=100)
    #: Passing threshold check is server-side.
    comment: str = Field(default="", max_length=300)


class GuideGrowthResponse(BaseModel):
    guide_id: int
    tier: str
    next_tier: str | None = None
    tier_progress: dict = Field(default_factory=dict)
    xp: int
    completed_tours: int
    review_count: int
    average_rating: float
    certifications: list[str] = Field(default_factory=list)
    features: list[str] = Field(default_factory=list)
    visibility_boost: float = 1.0
    trainings: list[dict] = Field(default_factory=list)


class GuideExperienceCreate(BaseModel):
    """An experience a guide adds themselves (draft until published)."""

    name: str = Field(..., min_length=2, max_length=120)
    category: str = Field(default="culture", max_length=40)
    lat: float = Field(default=19.076, ge=-90, le=90)
    lng: float = Field(default=72.8777, ge=-180, le=180)
    avg_cost: int = Field(default=0, ge=0, le=100000)
    duration_min: int = Field(default=60, ge=15, le=1440)
    open_time: str = Field(default="09:00", pattern=r"^\d{2}:\d{2}$")
    close_time: str = Field(default="21:00", pattern=r"^\d{2}:\d{2}$")
    description: str = Field(default="", max_length=1000)
    image_url: str | None = Field(default=None, max_length=300)
    tags: list[str] = Field(default_factory=list)
    accessibility_flags: list[str] = Field(default_factory=list)
    indoor_outdoor: str = Field(default="indoor", max_length=20)
    local_gem_score: float = Field(default=0.5, ge=0, le=1)
    publish: bool = False


class GuideExperienceResponse(BaseModel):
    id: int
    name: str
    status: str
    created_by_guide_id: int


# ---------------------------------------------------------------------------
# Quests
# ---------------------------------------------------------------------------


class QuestStopResponse(BaseModel):
    position: int
    experience: dict
    hint: str = ""


class QuestResponse(BaseModel):
    id: int
    code: str
    title: str
    story: str
    category: str
    difficulty: str
    xp_reward: int
    estimated_minutes: int
    estimated_cost: int
    is_active: bool
    stops: list[QuestStopResponse] = Field(default_factory=list)


class QuestStartRequest(BaseModel):
    #: Optional overrides; when absent the quest's own stops are used.
    time_hours: float | None = Field(default=None, ge=0.5, le=24)
    budget_inr: int | None = Field(default=None, ge=0)
    area: str | None = Field(default=None, max_length=120)


class QuestProgressResponse(BaseModel):
    #: The run this progress refers to. Needed to address
    #: /quests/runs/{run_id}/... for stop visits and completion.
    run_id: int = 0
    quest_id: int
    quest_code: str
    quest_title: str
    status: str
    stops_total: int
    stops_completed: int
    progress_percent: int
    current_stop: dict | None = None
    started_at: datetime | None = None
    completed_at: datetime | None = None
    xp_awarded: int = 0
    badges_earned: list[dict] = Field(default_factory=list)
    allowed_transitions: list[str] = Field(default_factory=list)


class QuestStopVisit(BaseModel):
    stop_position: int = Field(..., ge=1)


class UserProgressResponse(BaseModel):
    user_id: int
    xp: int
    level: int
    level_name: str
    badges: list[dict] = Field(default_factory=list)
    quests_started: int
    quests_completed: int


# ---------------------------------------------------------------------------
# Hidden gems
# ---------------------------------------------------------------------------


class HiddenGemCreate(BaseModel):
    name: str = Field(..., min_length=2, max_length=120)
    lat: float
    lng: float
    area: str = Field(default="", max_length=80)
    category: str = Field(default="culture", max_length=40)
    note: str = Field(default="", max_length=500)
    source_id: int | None = None


class HiddenGemResponse(BaseModel):
    id: int
    name: str
    lat: float
    lng: float
    area: str
    category: str
    status: str
    votes: int
    promoted_experience_id: int | None = None
    submitted_by: int | None = None
    source: dict | None = None


class HiddenGemVote(BaseModel):
    #: The candidate id lives in the path; this is optional and only used to
    #: cross-check when a client sends both.
    candidate_id: int = 0
    approve: bool = True


class TrustStateResponse(BaseModel):
    """Trust tier + what it unlocks. Never includes ID documents or PII."""

    user_id: int
    tier: str
    verified_at: datetime | None = None
    unlocked: list[str] = Field(default_factory=list)
    next_tier: str | None = None
    gates: dict[str, str] = Field(default_factory=dict)


class TrustVerifyRequest(BaseModel):
    """Simulated verification. Phase 1 performs no KYC."""

    target_tier: str
    acknowledged_not_real_kyc: bool = True


GroupResponse.model_rebuild()
