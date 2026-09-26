"""Shared pytest configuration.

Tests must never depend on the developer's local ``.env``: with a real Ollama
model configured, ``/parse`` and ``/chat`` would wait on connection timeouts and
the run would take minutes instead of seconds. Forcing ``APP_ENV=test`` before
any application module is imported also switches rate limiting off, which is
what the rest of the suite assumes.

Test isolation
--------------
The suite writes to the *developer's* SQLite file. Several phases create rows
(experiences named ``TS-*`` / ``P5 *``, users, itineraries) and previously left
them behind, so a run permanently mutated the dev database and the seed
comparison drifted (a stray ``TS-9d2d43`` experience was found in it).

:func:`_cleanup_test_rows` is an autouse fixture that removes exactly those
test-created rows after every test, so the dev database always returns to the
48 curated experiences plus whatever the developer had before the run. Seeded
rows are never touched: they are matched by name/email prefix, not by id.
"""

import os
import tempfile

os.environ.setdefault("APP_ENV", "test")
os.environ.setdefault("RATE_LIMIT_ENABLED", "false")
# Media: force the filesystem backend and a throwaway root so tests never need a
# running object store and never leave files in the repo.
os.environ.setdefault("S3_ENABLED", "false")
os.environ.setdefault("MEDIA_ROOT", tempfile.mkdtemp(prefix="localiq-media-"))

import pytest  # noqa: E402
from sqlmodel import delete, select  # noqa: E402

# Name / email fragments that only ever appear on rows created by the test suite.
_TEST_NAME_FRAGMENTS = ("TS-", "P5 ", "P6 ", "P5Test", "Test User", "Demo User", "tmp-", "temp-")
_TEST_EMAIL_FRAGMENTS = ("@localiq.test", "@example.com", "nobody@", "p5user", "testuser")


def _is_test_row(name: str) -> bool:
    return any(fragment.lower() in (name or "").lower() for fragment in _TEST_NAME_FRAGMENTS)


def _is_test_email(email: str) -> bool:
    lowered = (email or "").lower()
    return any(fragment in lowered for fragment in _TEST_EMAIL_FRAGMENTS)


@pytest.fixture(scope="session", autouse=True)
def _bootstrap_database():
    """Create the schema and seed the curated dataset once per session.

    The suite writes to the developer's SQLite file. On a fresh clone (or after
    ``data/localiq.db`` is deleted) there are no tables, so every test errors
    with "no such table". ``init_db`` is idempotent and ``seed_if_empty`` only
    inserts when the experiences table is empty, so an existing database is
    left untouched.
    """
    from app.database import init_db
    from app.seed import seed_if_empty

    init_db()
    seed_if_empty()
    yield


@pytest.fixture(autouse=True)
def _reset_llm_circuit():
    """Keep the LLM circuit breaker isolated between tests.

    The breaker is process-global by design (that is what makes it work in
    production). Without this reset, a test that trips the breaker would make
    every later test in the session short-circuit and return ``None``.
    """
    from app.services import llm

    llm.reset_circuit()
    yield
    llm.reset_circuit()


@pytest.fixture(autouse=True)
def _cleanup_test_rows():
    """Delete rows the suite created, after each test."""
    yield

    from app.database import engine
    from app.models import (
        AITip,
        ConversationSession,
        Experience,
        ExperienceLog,
        ExperienceSession,
        ExperienceWallet,
        Favorite,
        Guide,
        GuideRequest,
        Itinerary,
        ItineraryStop,
        PreferenceSignal,
        RecommendationFeedback,
        User,
        UserActivityInteraction,
        UserBadge,
        UserSession,
    )
    from app.models_prd import (
        Badge,
        Group,
        GroupMember,
        GroupOption,
        GroupVote,
        GuideAvailability,
        GuideBooking,
        GuideProfile,
        GuideReview,
        GuideTraining,
        HiddenGemCandidate,
        Mention,
        MeetupBlock,
        MeetupMatch,
        MeetupRequest,
        MeetupReview,
        Quest,
        QuestRun,
        QuestStop,
        Source,
        UserProgress,
    )
    from sqlmodel import Session

    try:
        with Session(engine) as session:
            # PRD v2 journey rows are test-created wholesale, so they can be
            # cleared in FK-safe order (children first) before users/guides go.
            for model in (
                Mention,
                GroupVote,
                GroupOption,
                GroupMember,
                Group,
                QuestRun,
                QuestStop,
                UserProgress,
                Quest,
                Badge,
                MeetupBlock,
                MeetupReview,
                MeetupMatch,
                MeetupRequest,
                GuideReview,
                GuideBooking,
                GuideAvailability,
                GuideTraining,
                GuideProfile,
                ExperienceSession,
                AITip,
            ):
                session.exec(delete(model))
            # Quests/badges/sources are seeded reference data, so only remove
            # rows this suite created.
            for model, marker in (
                (Quest, "TS-"),
                (Badge, "TS-"),
                (Source, "TS-"),
            ):
                for row in session.exec(select(model)).all():
                    if marker in str(getattr(row, "code", "")) or marker in str(
                        getattr(row, "name", "")
                    ):
                        session.delete(row)
            for cand in session.exec(select(HiddenGemCandidate)).all():
                if cand.promoted_experience_id is None and (
                    "TS-" in cand.name or cand.submitted_by is None
                ):
                    session.delete(cand)
            session.commit()

            test_experiences = session.exec(
                select(Experience).where(Experience.name.contains("TS-"))
            ).all()
            for exp in test_experiences:
                # Children first (FK order).
                session.exec(
                    delete(RecommendationFeedback).where(
                        RecommendationFeedback.experience_id == exp.id
                    )
                )
                session.exec(delete(Favorite).where(Favorite.experience_id == exp.id))
                session.exec(delete(GuideRequest).where(GuideRequest.experience_id == exp.id))
                session.exec(delete(Guide).where(Guide.experience_id == exp.id))
                session.delete(exp)

            p5_guides = session.exec(select(Guide).where(Guide.name.contains("Test"))).all()
            for guide in p5_guides:
                session.delete(guide)

            users = session.exec(select(User)).all()
            for user in users:
                if not _is_test_email(user.email) and not _is_test_row(user.name):
                    continue
                session.exec(
                    delete(Favorite).where(Favorite.user_id == user.id)
                )
                session.exec(
                    delete(RecommendationFeedback).where(
                        RecommendationFeedback.user_id == user.id
                    )
                )
                session.exec(
                    delete(UserActivityInteraction).where(
                        UserActivityInteraction.user_id == user.id
                    )
                )
                session.exec(
                    delete(PreferenceSignal).where(PreferenceSignal.user_id == user.id)
                )
                session.exec(
                    delete(ConversationSession).where(
                        ConversationSession.user_id == user.id
                    )
                )
                session.exec(
                    delete(UserBadge).where(UserBadge.user_id == user.id)
                )
                session.exec(
                    delete(ExperienceLog).where(ExperienceLog.user_id == user.id)
                )
                session.exec(
                    delete(ExperienceWallet).where(ExperienceWallet.user_id == user.id)
                )
                session.exec(delete(GuideRequest).where(GuideRequest.user_id == user.id))
                session.exec(delete(ItineraryStop).where(ItineraryStop.itinerary_id.in_(
                    select(Itinerary.id).where(Itinerary.user_id == user.id)
                )))
                session.exec(delete(Itinerary).where(Itinerary.user_id == user.id))
                session.exec(delete(UserSession).where(UserSession.user_id == user.id))
                session.delete(user)

            # Itineraries owned by a now-deleted test user, plus strays.
            orphans = session.exec(
                select(Itinerary).where(Itinerary.name.contains("P5"))
            ).all()
            for itin in orphans:
                session.exec(
                    delete(ItineraryStop).where(ItineraryStop.itinerary_id == itin.id)
                )
                session.delete(itin)

            session.commit()
    except Exception:  # never fail a test because cleanup had a problem
        pass
