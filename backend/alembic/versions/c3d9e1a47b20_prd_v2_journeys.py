"""PRD v2 journey tables (solo, meetup, groups, guide ops, quests, gems)

Revision ID: c3d9e1a47b20
Revises: bca4f9c535f1
Create Date: 2026-09-26 18:10:00.000000

Creates every table declared in ``app/models_prd.py``. The pre-existing tables
are untouched, so this is purely additive.
"""

from typing import Sequence, Union

import sqlalchemy as sa
import sqlmodel
from alembic import op

# revision identifiers, used by Alembic.
revision: str = "c3d9e1a47b20"
down_revision: Union[str, None] = "bca4f9c535f1"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None

_TS = sa.Column("created_at", sa.DateTime(), nullable=False)
_TS2 = sa.Column("updated_at", sa.DateTime(), nullable=False)


def _timestamps() -> list:
    return [_TS, _TS2]


def upgrade() -> None:
    # ------------------------------------------------------------------
    # Guides: onboarding, verification, availability, bookings, reviews,
    # training (PRD v2 journeys 4, 6, 7, 8)
    # ------------------------------------------------------------------
    op.create_table(
        "guide_profiles",
        *_timestamps(),
        sa.Column("id", sa.Integer(), nullable=False, primary_key=True),
        sa.Column("guide_id", sa.Integer(), nullable=False),
        sa.Column("user_id", sa.Integer(), nullable=True),
        sa.Column("onboarding_state", sa.String(), nullable=False),
        sa.Column("verification_status", sa.String(), nullable=False),
        sa.Column("verification_tier", sa.String(), nullable=False),
        sa.Column("id_document_type", sa.String(), nullable=True),
        sa.Column("id_document_reference", sa.String(), nullable=True),
        sa.Column("verified_at", sa.DateTime(), nullable=True),
        sa.Column("tier", sa.String(), nullable=False),
        sa.Column("xp", sa.Integer(), nullable=False),
        sa.Column("completed_tours", sa.Integer(), nullable=False),
        sa.Column("review_count", sa.Integer(), nullable=False),
        sa.Column("rating_sum", sa.Float(), nullable=False),
        sa.Column("bio", sa.String(), nullable=False),
        sa.Column("city", sa.String(), nullable=False),
        sa.Column("is_published", sa.Boolean(), nullable=False),
        sa.ForeignKeyConstraint(["guide_id"], ["guides.id"]),
        sa.ForeignKeyConstraint(["user_id"], ["users.id"]),
        sa.UniqueConstraint("guide_id"),
    )
    op.create_index("ix_guide_profiles_guide_id", "guide_profiles", ["guide_id"])
    op.create_index("ix_guide_profiles_user_id", "guide_profiles", ["user_id"])
    op.create_index("ix_guide_profiles_onboarding_state", "guide_profiles", ["onboarding_state"])
    op.create_index(
        "ix_guide_profiles_verification_status", "guide_profiles", ["verification_status"]
    )
    op.create_index("ix_guide_profiles_verification_tier", "guide_profiles", ["verification_tier"])
    op.create_index("ix_guide_profiles_tier", "guide_profiles", ["tier"])

    op.create_table(
        "guide_availability",
        *_timestamps(),
        sa.Column("id", sa.Integer(), nullable=False, primary_key=True),
        sa.Column("guide_id", sa.Integer(), nullable=False),
        sa.Column("date", sa.Date(), nullable=False),
        sa.Column("start_time", sa.String(), nullable=False),
        sa.Column("end_time", sa.String(), nullable=False),
        sa.Column("max_group_size", sa.Integer(), nullable=False),
        sa.Column("is_booked", sa.Boolean(), nullable=False),
        sa.Column("note", sa.String(), nullable=False),
        sa.ForeignKeyConstraint(["guide_id"], ["guides.id"]),
        sa.UniqueConstraint("guide_id", "date", "start_time", name="uq_guide_slot"),
    )
    op.create_index("ix_guide_availability_guide_id", "guide_availability", ["guide_id"])
    op.create_index("ix_guide_availability_date", "guide_availability", ["date"])
    op.create_index(
        "ix_guide_availability_guide_date", "guide_availability", ["guide_id", "date"]
    )

    op.create_table(
        "guide_bookings",
        *_timestamps(),
        sa.Column("id", sa.Integer(), nullable=False, primary_key=True),
        sa.Column("user_id", sa.Integer(), nullable=False),
        sa.Column("guide_id", sa.Integer(), nullable=False),
        sa.Column("experience_id", sa.Integer(), nullable=True),
        sa.Column("availability_id", sa.Integer(), nullable=True),
        sa.Column("date", sa.Date(), nullable=False),
        sa.Column("start_time", sa.String(), nullable=False),
        sa.Column("duration_min", sa.Integer(), nullable=False),
        sa.Column("group_size", sa.Integer(), nullable=False),
        sa.Column("status", sa.String(), nullable=False),
        sa.Column("payment_status", sa.String(), nullable=False),
        sa.Column("hourly_rate", sa.Integer(), nullable=False),
        sa.Column("total_cost", sa.Integer(), nullable=False),
        sa.Column("currency", sa.String(), nullable=False),
        sa.Column("notes", sa.String(), nullable=False),
        sa.Column("requested_at", sa.DateTime(), nullable=True),
        sa.Column("accepted_at", sa.DateTime(), nullable=True),
        sa.Column("confirmed_at", sa.DateTime(), nullable=True),
        sa.Column("started_at", sa.DateTime(), nullable=True),
        sa.Column("completed_at", sa.DateTime(), nullable=True),
        sa.Column("closed_at", sa.DateTime(), nullable=True),
        sa.Column("decline_reason", sa.String(), nullable=False),
        sa.ForeignKeyConstraint(["user_id"], ["users.id"]),
        sa.ForeignKeyConstraint(["guide_id"], ["guides.id"]),
        sa.ForeignKeyConstraint(["experience_id"], ["experiences.id"]),
        sa.ForeignKeyConstraint(["availability_id"], ["guide_availability.id"]),
    )
    op.create_index("ix_guide_bookings_user_id", "guide_bookings", ["user_id"])
    op.create_index("ix_guide_bookings_guide_id", "guide_bookings", ["guide_id"])
    op.create_index("ix_guide_bookings_experience_id", "guide_bookings", ["experience_id"])
    op.create_index("ix_guide_bookings_availability_id", "guide_bookings", ["availability_id"])
    op.create_index("ix_guide_bookings_status", "guide_bookings", ["status"])

    op.create_table(
        "guide_reviews",
        *_timestamps(),
        sa.Column("id", sa.Integer(), nullable=False, primary_key=True),
        sa.Column("booking_id", sa.Integer(), nullable=False),
        sa.Column("user_id", sa.Integer(), nullable=False),
        sa.Column("guide_id", sa.Integer(), nullable=False),
        sa.Column("rating", sa.Integer(), nullable=False),
        sa.Column("comment", sa.String(), nullable=False),
        sa.Column("punctuality", sa.Integer(), nullable=False),
        sa.Column("knowledge", sa.Integer(), nullable=False),
        sa.ForeignKeyConstraint(["booking_id"], ["guide_bookings.id"]),
        sa.ForeignKeyConstraint(["user_id"], ["users.id"]),
        sa.ForeignKeyConstraint(["guide_id"], ["guides.id"]),
        sa.UniqueConstraint("booking_id", "user_id", name="uq_guide_review_per_user"),
    )
    op.create_index("ix_guide_reviews_booking_id", "guide_reviews", ["booking_id"])
    op.create_index("ix_guide_reviews_user_id", "guide_reviews", ["user_id"])
    op.create_index("ix_guide_reviews_guide_id", "guide_reviews", ["guide_id"])

    op.create_table(
        "guide_trainings",
        *_timestamps(),
        sa.Column("id", sa.Integer(), nullable=False, primary_key=True),
        sa.Column("guide_id", sa.Integer(), nullable=False),
        sa.Column("course_code", sa.String(), nullable=False),
        sa.Column("course_name", sa.String(), nullable=False),
        sa.Column("status", sa.String(), nullable=False),
        sa.Column("score", sa.Integer(), nullable=False),
        sa.Column("completed_at", sa.DateTime(), nullable=True),
        sa.Column("grants_tier", sa.String(), nullable=True),
        sa.ForeignKeyConstraint(["guide_id"], ["guides.id"]),
        sa.UniqueConstraint("guide_id", "course_code", name="uq_guide_course"),
    )
    op.create_index("ix_guide_trainings_guide_id", "guide_trainings", ["guide_id"])
    op.create_index("ix_guide_trainings_course_code", "guide_trainings", ["course_code"])
    op.create_index("ix_guide_trainings_status", "guide_trainings", ["status"])

    # ------------------------------------------------------------------
    # Meetups (journey 2)
    # ------------------------------------------------------------------
    op.create_table(
        "meetup_requests",
        *_timestamps(),
        sa.Column("id", sa.Integer(), nullable=False, primary_key=True),
        sa.Column("user_id", sa.Integer(), nullable=False),
        sa.Column("experience_id", sa.Integer(), nullable=True),
        sa.Column("category", sa.String(), nullable=False),
        sa.Column("area", sa.String(), nullable=False),
        sa.Column("lat", sa.Float(), nullable=False),
        sa.Column("lng", sa.Float(), nullable=False),
        sa.Column("start_time", sa.String(), nullable=False),
        sa.Column("duration_min", sa.Integer(), nullable=False),
        sa.Column("budget_inr", sa.Integer(), nullable=False),
        sa.Column("group_size_pref", sa.Integer(), nullable=False),
        sa.Column("interests", sa.JSON(), nullable=False),
        sa.Column("note", sa.String(), nullable=False),
        sa.Column("status", sa.String(), nullable=False),
        sa.Column("expires_at", sa.DateTime(), nullable=True),
        sa.ForeignKeyConstraint(["user_id"], ["users.id"]),
        sa.ForeignKeyConstraint(["experience_id"], ["experiences.id"]),
    )
    op.create_index("ix_meetup_requests_user_id", "meetup_requests", ["user_id"])
    op.create_index("ix_meetup_requests_experience_id", "meetup_requests", ["experience_id"])
    op.create_index("ix_meetup_requests_category", "meetup_requests", ["category"])
    op.create_index("ix_meetup_requests_status", "meetup_requests", ["status"])

    op.create_table(
        "meetup_matches",
        *_timestamps(),
        sa.Column("id", sa.Integer(), nullable=False, primary_key=True),
        sa.Column("request_id", sa.Integer(), nullable=False),
        sa.Column("experience_id", sa.Integer(), nullable=True),
        sa.Column("member_ids", sa.JSON(), nullable=False),
        sa.Column("compatibility_score", sa.Float(), nullable=False),
        sa.Column("shared_interests", sa.JSON(), nullable=False),
        sa.Column("plan", sa.JSON(), nullable=False),
        sa.Column("meeting_point", sa.String(), nullable=False),
        sa.Column("safety_score", sa.Integer(), nullable=False),
        sa.Column("start_time", sa.String(), nullable=False),
        sa.Column("duration_min", sa.Integer(), nullable=False),
        sa.Column("total_cost", sa.Integer(), nullable=False),
        sa.Column("status", sa.String(), nullable=False),
        sa.Column("keep_group", sa.Boolean(), nullable=False),
        sa.ForeignKeyConstraint(["request_id"], ["meetup_requests.id"]),
        sa.ForeignKeyConstraint(["experience_id"], ["experiences.id"]),
    )
    op.create_index("ix_meetup_matches_request_id", "meetup_matches", ["request_id"])
    op.create_index("ix_meetup_matches_experience_id", "meetup_matches", ["experience_id"])
    op.create_index("ix_meetup_matches_status", "meetup_matches", ["status"])

    op.create_table(
        "meetup_reviews",
        *_timestamps(),
        sa.Column("id", sa.Integer(), nullable=False, primary_key=True),
        sa.Column("match_id", sa.Integer(), nullable=False),
        sa.Column("user_id", sa.Integer(), nullable=False),
        sa.Column("experience_rating", sa.Integer(), nullable=False),
        sa.Column("would_repeat", sa.Boolean(), nullable=False),
        sa.Column("comment", sa.String(), nullable=False),
        sa.ForeignKeyConstraint(["match_id"], ["meetup_matches.id"]),
        sa.ForeignKeyConstraint(["user_id"], ["users.id"]),
        sa.UniqueConstraint("match_id", "user_id", name="uq_meetup_review_per_user"),
    )
    op.create_index("ix_meetup_reviews_match_id", "meetup_reviews", ["match_id"])
    op.create_index("ix_meetup_reviews_user_id", "meetup_reviews", ["user_id"])

    op.create_table(
        "meetup_blocks",
        *_timestamps(),
        sa.Column("id", sa.Integer(), nullable=False, primary_key=True),
        sa.Column("blocker_id", sa.Integer(), nullable=False),
        sa.Column("blocked_id", sa.Integer(), nullable=False),
        sa.Column("reason", sa.String(), nullable=False),
        sa.Column("reported", sa.Boolean(), nullable=False),
        sa.ForeignKeyConstraint(["blocker_id"], ["users.id"]),
        sa.ForeignKeyConstraint(["blocked_id"], ["users.id"]),
        sa.UniqueConstraint("blocker_id", "blocked_id", name="uq_meetup_block"),
    )
    op.create_index("ix_meetup_blocks_blocker_id", "meetup_blocks", ["blocker_id"])
    op.create_index("ix_meetup_blocks_blocked_id", "meetup_blocks", ["blocked_id"])

    # ------------------------------------------------------------------
    # Groups (journey 3)
    # ------------------------------------------------------------------
    op.create_table(
        "groups",
        *_timestamps(),
        sa.Column("id", sa.Integer(), nullable=False, primary_key=True),
        sa.Column("name", sa.String(), nullable=False),
        sa.Column("owner_id", sa.Integer(), nullable=False),
        sa.Column("area", sa.String(), nullable=False),
        sa.Column("lat", sa.Float(), nullable=False),
        sa.Column("lng", sa.Float(), nullable=False),
        sa.Column("time_hours", sa.Float(), nullable=False),
        sa.Column("budget_inr", sa.Integer(), nullable=False),
        sa.Column("interests", sa.JSON(), nullable=False),
        sa.Column("accessibility", sa.Boolean(), nullable=False),
        sa.Column("status", sa.String(), nullable=False),
        sa.Column("max_members", sa.Integer(), nullable=False),
        sa.Column("final_plan", sa.JSON(), nullable=False),
        sa.Column("locked_at", sa.DateTime(), nullable=True),
        sa.ForeignKeyConstraint(["owner_id"], ["users.id"]),
    )
    op.create_index("ix_groups_owner_id", "groups", ["owner_id"])
    op.create_index("ix_groups_status", "groups", ["status"])

    op.create_table(
        "group_members",
        *_timestamps(),
        sa.Column("id", sa.Integer(), nullable=False, primary_key=True),
        sa.Column("group_id", sa.Integer(), nullable=False),
        sa.Column("user_id", sa.Integer(), nullable=False),
        sa.Column("is_owner", sa.Boolean(), nullable=False),
        sa.Column("interests", sa.JSON(), nullable=False),
        sa.Column("budget_inr", sa.Integer(), nullable=False),
        sa.Column("time_hours", sa.Float(), nullable=False),
        sa.Column("accessibility", sa.Boolean(), nullable=False),
        sa.Column("has_voted", sa.Boolean(), nullable=False),
        sa.ForeignKeyConstraint(["group_id"], ["groups.id"]),
        sa.ForeignKeyConstraint(["user_id"], ["users.id"]),
        sa.UniqueConstraint("group_id", "user_id", name="uq_group_member"),
    )
    op.create_index("ix_group_members_group_id", "group_members", ["group_id"])
    op.create_index("ix_group_members_user_id", "group_members", ["user_id"])

    op.create_table(
        "group_options",
        *_timestamps(),
        sa.Column("id", sa.Integer(), nullable=False, primary_key=True),
        sa.Column("group_id", sa.Integer(), nullable=False),
        sa.Column("label", sa.String(), nullable=False),
        sa.Column("rank", sa.Integer(), nullable=False),
        sa.Column("score", sa.Float(), nullable=False),
        sa.Column("stops", sa.JSON(), nullable=False),
        sa.Column("total_minutes", sa.Integer(), nullable=False),
        sa.Column("total_cost", sa.Integer(), nullable=False),
        sa.Column("votes", sa.Integer(), nullable=False),
        sa.Column("is_winner", sa.Boolean(), nullable=False),
        sa.ForeignKeyConstraint(["group_id"], ["groups.id"]),
    )
    op.create_index("ix_group_options_group_id", "group_options", ["group_id"])

    op.create_table(
        "group_votes",
        *_timestamps(),
        sa.Column("id", sa.Integer(), nullable=False, primary_key=True),
        sa.Column("group_id", sa.Integer(), nullable=False),
        sa.Column("option_id", sa.Integer(), nullable=False),
        sa.Column("user_id", sa.Integer(), nullable=False),
        sa.Column("rank", sa.Integer(), nullable=False),
        sa.Column("comment", sa.String(), nullable=False),
        sa.ForeignKeyConstraint(["group_id"], ["groups.id"]),
        sa.ForeignKeyConstraint(["option_id"], ["group_options.id"]),
        sa.ForeignKeyConstraint(["user_id"], ["users.id"]),
        sa.UniqueConstraint("group_id", "user_id", name="uq_group_vote"),
    )
    op.create_index("ix_group_votes_group_id", "group_votes", ["group_id"])
    op.create_index("ix_group_votes_option_id", "group_votes", ["option_id"])
    op.create_index("ix_group_votes_user_id", "group_votes", ["user_id"])

    # ------------------------------------------------------------------
    # Quests, progress, badges (journey 5)
    # ------------------------------------------------------------------
    op.create_table(
        "quests",
        *_timestamps(),
        sa.Column("id", sa.Integer(), nullable=False, primary_key=True),
        sa.Column("code", sa.String(), nullable=False),
        sa.Column("title", sa.String(), nullable=False),
        sa.Column("story", sa.String(), nullable=False),
        sa.Column("category", sa.String(), nullable=False),
        sa.Column("difficulty", sa.String(), nullable=False),
        sa.Column("xp_reward", sa.Integer(), nullable=False),
        sa.Column("estimated_minutes", sa.Integer(), nullable=False),
        sa.Column("estimated_cost", sa.Integer(), nullable=False),
        sa.Column("is_active", sa.Boolean(), nullable=False),
        sa.UniqueConstraint("code"),
    )
    op.create_index("ix_quests_code", "quests", ["code"])
    op.create_index("ix_quests_category", "quests", ["category"])
    op.create_index("ix_quests_is_active", "quests", ["is_active"])

    op.create_table(
        "quest_stops",
        *_timestamps(),
        sa.Column("id", sa.Integer(), nullable=False, primary_key=True),
        sa.Column("quest_id", sa.Integer(), nullable=False),
        sa.Column("experience_id", sa.Integer(), nullable=False),
        sa.Column("position", sa.Integer(), nullable=False),
        sa.Column("hint", sa.String(), nullable=False),
        sa.ForeignKeyConstraint(["quest_id"], ["quests.id"]),
        sa.ForeignKeyConstraint(["experience_id"], ["experiences.id"]),
        sa.UniqueConstraint("quest_id", "position", name="uq_quest_stop_position"),
    )
    op.create_index("ix_quest_stops_quest_id", "quest_stops", ["quest_id"])
    op.create_index("ix_quest_stops_experience_id", "quest_stops", ["experience_id"])

    op.create_table(
        "quest_runs",
        *_timestamps(),
        sa.Column("id", sa.Integer(), nullable=False, primary_key=True),
        sa.Column("quest_id", sa.Integer(), nullable=False),
        sa.Column("user_id", sa.Integer(), nullable=False),
        sa.Column("status", sa.String(), nullable=False),
        sa.Column("time_hours", sa.Float(), nullable=False),
        sa.Column("budget_inr", sa.Integer(), nullable=False),
        sa.Column("plan", sa.JSON(), nullable=False),
        sa.Column("completed_stops", sa.JSON(), nullable=False),
        sa.Column("xp_awarded", sa.Integer(), nullable=False),
        sa.Column("badges_earned", sa.JSON(), nullable=False),
        sa.Column("started_at", sa.DateTime(), nullable=True),
        sa.Column("completed_at", sa.DateTime(), nullable=True),
        sa.ForeignKeyConstraint(["quest_id"], ["quests.id"]),
        sa.ForeignKeyConstraint(["user_id"], ["users.id"]),
    )
    op.create_index("ix_quest_runs_quest_id", "quest_runs", ["quest_id"])
    op.create_index("ix_quest_runs_user_id", "quest_runs", ["user_id"])
    op.create_index("ix_quest_runs_status", "quest_runs", ["status"])
    op.create_index("ix_quest_runs_user_status", "quest_runs", ["user_id", "status"])

    op.create_table(
        "user_progress",
        *_timestamps(),
        sa.Column("id", sa.Integer(), nullable=False, primary_key=True),
        sa.Column("user_id", sa.Integer(), nullable=False),
        sa.Column("xp", sa.Integer(), nullable=False),
        sa.Column("level", sa.Integer(), nullable=False),
        sa.Column("badges", sa.JSON(), nullable=False),
        sa.Column("quests_completed", sa.Integer(), nullable=False),
        sa.Column("quests_started", sa.Integer(), nullable=False),
        sa.ForeignKeyConstraint(["user_id"], ["users.id"]),
        sa.UniqueConstraint("user_id"),
    )
    op.create_index("ix_user_progress_user_id", "user_progress", ["user_id"])

    op.create_table(
        "badges",
        *_timestamps(),
        sa.Column("id", sa.Integer(), nullable=False, primary_key=True),
        sa.Column("code", sa.String(), nullable=False),
        sa.Column("name", sa.String(), nullable=False),
        sa.Column("description", sa.String(), nullable=False),
        sa.Column("xp_bonus", sa.Integer(), nullable=False),
        sa.Column("tier", sa.String(), nullable=False),
        sa.UniqueConstraint("code"),
    )
    op.create_index("ix_badges_code", "badges", ["code"])

    # ------------------------------------------------------------------
    # Hidden gem pipeline + sources + mentions (PRD v2 data models)
    # ------------------------------------------------------------------
    op.create_table(
        "sources",
        *_timestamps(),
        sa.Column("id", sa.Integer(), nullable=False, primary_key=True),
        sa.Column("name", sa.String(), nullable=False),
        sa.Column("kind", sa.String(), nullable=False),
        sa.Column("url", sa.String(), nullable=False),
        sa.Column("is_active", sa.Boolean(), nullable=False),
    )
    op.create_index("ix_sources_name", "sources", ["name"])

    op.create_table(
        "hidden_gem_candidates",
        *_timestamps(),
        sa.Column("id", sa.Integer(), nullable=False, primary_key=True),
        sa.Column("name", sa.String(), nullable=False),
        sa.Column("lat", sa.Float(), nullable=False),
        sa.Column("lng", sa.Float(), nullable=False),
        sa.Column("area", sa.String(), nullable=False),
        sa.Column("category", sa.String(), nullable=False),
        sa.Column("submitted_by", sa.Integer(), nullable=True),
        sa.Column("source_id", sa.Integer(), nullable=True),
        sa.Column("votes", sa.Integer(), nullable=False),
        sa.Column("status", sa.String(), nullable=False),
        sa.Column("promoted_experience_id", sa.Integer(), nullable=True),
        sa.Column("note", sa.String(), nullable=False),
        sa.ForeignKeyConstraint(["submitted_by"], ["users.id"]),
        sa.ForeignKeyConstraint(["source_id"], ["sources.id"]),
        sa.ForeignKeyConstraint(["promoted_experience_id"], ["experiences.id"]),
    )
    op.create_index("ix_hidden_gem_candidates_name", "hidden_gem_candidates", ["name"])
    op.create_index(
        "ix_hidden_gem_candidates_submitted_by", "hidden_gem_candidates", ["submitted_by"]
    )
    op.create_index("ix_hidden_gem_candidates_source_id", "hidden_gem_candidates", ["source_id"])
    op.create_index("ix_hidden_gem_candidates_status", "hidden_gem_candidates", ["status"])
    op.create_index(
        "ix_hidden_gem_candidates_promoted_experience_id",
        "hidden_gem_candidates",
        ["promoted_experience_id"],
    )

    op.create_table(
        "mentions",
        *_timestamps(),
        sa.Column("id", sa.Integer(), nullable=False, primary_key=True),
        sa.Column("content_type", sa.String(), nullable=False),
        sa.Column("content_id", sa.Integer(), nullable=False),
        sa.Column("user_id", sa.Integer(), nullable=False),
        sa.Column("text", sa.String(), nullable=False),
        sa.ForeignKeyConstraint(["user_id"], ["users.id"]),
    )
    op.create_index("ix_mentions_content_id", "mentions", ["content_id"])
    op.create_index("ix_mentions_user_id", "mentions", ["user_id"])


def downgrade() -> None:
    for table in (
        "mentions",
        "hidden_gem_candidates",
        "sources",
        "badges",
        "user_progress",
        "quest_runs",
        "quest_stops",
        "quests",
        "group_votes",
        "group_options",
        "group_members",
        "groups",
        "meetup_blocks",
        "meetup_reviews",
        "meetup_matches",
        "meetup_requests",
        "guide_trainings",
        "guide_reviews",
        "guide_bookings",
        "guide_availability",
        "guide_profiles",
    ):
        op.drop_table(table)
