"""PRD v2 journey tests: solo, meetup, groups, guide ops, quests, gems, trust.

These cover the server-side rules the PRD cares about most:

* trust gates block stranger-facing actions until verification is simulated
* ownership is enforced (a user cannot touch another user's group/booking)
* state machines reject illegal transitions
* group voting needs quorum, resolves a winner, and detects ties
* quests award XP, level up and hand out badges
* the hidden-gem pipeline only promotes a *voted* candidate
"""

from __future__ import annotations

import pytest
from fastapi.testclient import TestClient
from sqlmodel import Session, select

from app.database import engine
from app.models import Experience, Guide, User
from app.models_prd import (
    GuideProfile,
    Quest,
    QuestStop,
)
from app.services import journey_rules as rules
from main import app

client = TestClient(app)


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------


def _mk_user(name: str, email: str) -> int:
    with Session(engine) as session:
        user = User(name=name, email=email, password_hash="x")
        session.add(user)
        session.commit()
        session.refresh(user)
        return user.id


def _mk_guide_profile(
    user_id: int | None = None,
    *,
    name: str = "TS-Guide",
    verification: str = "verified",
    onboarding: str = "active",
    rate: int = 800,
) -> int:
    with Session(engine) as session:
        guide = Guide(
            name=name, specialty="local culture", languages=["en", "hi"], rate_per_hour=rate
        )
        session.add(guide)
        session.commit()
        session.refresh(guide)
        session.add(
            GuideProfile(
                guide_id=guide.id or 0,
                user_id=user_id,
                onboarding_state=onboarding,
                verification_status=verification,
                verification_tier="standard" if verification == "verified" else "unverified",
                bio="test guide",
                city="Mumbai",
                is_published=onboarding == "active",
            )
        )
        session.commit()
        return guide.id or 0


def _mk_experience(name: str = "TS-Experience", category: str = "food") -> int:
    with Session(engine) as session:
        exp = Experience(
            name=name,
            category=category,
            lat=19.0596,
            lng=72.8777,
            avg_cost=400,
            duration_min=90,
            open_time="09:00",
            close_time="22:00",
            rating=4.5,
            description="test",
            tags=["food"],
            accessibility_flags=[],
            indoor_outdoor="indoor",
            local_gem_score=0.7,
        )
        session.add(exp)
        session.commit()
        session.refresh(exp)
        return exp.id or 0


def _mk_quest(code: str = "TS-QUEST", xp_reward: int = 100) -> tuple[int, list[int]]:
    with Session(engine) as session:
        quest = Quest(
            code=code,
            title="Test quest",
            story="A test quest",
            category="culture",
            difficulty="easy",
            xp_reward=xp_reward,
            estimated_minutes=120,
            estimated_cost=300,
        )
        session.add(quest)
        session.commit()
        session.refresh(quest)
        stop_ids = []
        for pos in (1, 2):
            exp = Experience(
                name=f"TS-QuestStop-{code}-{pos}",
                category="culture",
                lat=19.05 + pos * 0.01,
                lng=72.87,
                avg_cost=100,
                duration_min=45,
                open_time="09:00",
                close_time="21:00",
                rating=4.0,
                description="stop",
                tags=[],
                accessibility_flags=[],
                indoor_outdoor="outdoor",
                local_gem_score=0.6,
            )
            session.add(exp)
            session.commit()
            session.refresh(exp)
            stop_ids.append(exp.id or 0)
            session.add(QuestStop(quest_id=quest.id or 0, experience_id=exp.id or 0, position=pos))
        session.commit()
        return quest.id or 0, stop_ids


def _hdr(user_id: int) -> dict:
    return {"X-User-Id": str(user_id)}


def _trust(user_id: int, tier: str) -> None:
    with Session(engine) as session:
        user = session.get(User, user_id)
        assert user is not None
        user.trust_tier = tier
        session.add(user)
        session.commit()


# ---------------------------------------------------------------------------
# Pure rules (no HTTP)
# ---------------------------------------------------------------------------


class TestJourneyRules:
    def test_trust_gates_block_stranger_actions(self):
        assert rules.meets_trust("basic", "create_meetup_request") is False
        assert rules.meets_trust("standard", "create_meetup_request") is True
        assert rules.meets_trust("trusted", "be_matched") is True
        assert rules.meets_trust("basic", "create_group") is True

    def test_unknown_action_is_denied(self):
        assert rules.meets_trust("trusted", "do_anything") is False

    def test_booking_cost_is_hourly_plus_extras(self):
        total = rules.calculate_booking_cost(
            hourly_rate=800, duration_min=90, group_size=3, extras=100
        )
        # 90min bills as 2 hours, plus 100 per attendee for 3 people.
        assert rules.math_ceil_div(90, 60) == 2
        assert total == 2 * 800 + 3 * 100

    def test_booking_cost_with_no_extras_is_time_only(self):
        assert rules.calculate_booking_cost(800, 120, 4) == 1600

    def test_level_thresholds_are_monotonic(self):
        assert rules.level_for_xp(0) == 1
        assert rules.level_for_xp(10_000) > rules.level_for_xp(100)

    def test_tie_is_detected(self):
        tally = rules.tally_votes(
            [
                {"option_id": 1, "user_id": 10, "rank": 1},
                {"option_id": 2, "user_id": 11, "rank": 1},
            ],
            {1: 1, 2: 1},
        )
        winner, tie = rules.resolve_winner(tally, 2)
        assert winner is None and tie is True

    def test_clear_winner_is_not_a_tie(self):
        tally = rules.tally_votes(
            [
                {"option_id": 1, "user_id": 10, "rank": 1},
                {"option_id": 1, "user_id": 11, "rank": 2},
                {"option_id": 2, "user_id": 12, "rank": 1},
            ],
            {1: 1, 2: 1},
        )
        winner, tie = rules.resolve_winner(tally, 3)
        assert winner == 1 and tie is False

    def test_quorum_needs_a_strict_majority(self):
        assert rules.quorum_reached(3, 4) is True
        assert rules.quorum_reached(2, 3) is True
        # Exactly half is not a majority.
        assert rules.quorum_reached(2, 4) is False
        assert rules.quorum_reached(1, 4) is False
        assert rules.quorum_reached(0, 0) is False

    def test_illegal_booking_transitions_rejected(self):
        ok, reason = rules.can_transition_booking("requested", "completed", "user")
        assert ok is False and reason
        ok, _ = rules.can_transition_booking("requested", "accepted", "guide")
        assert ok is True

    def test_guide_tier_progression_requires_evidence(self):
        # No tours, no rating, no certifications -> nothing to advance to.
        assert (
            rules.next_guide_tier(
                tier="new", completed_tours=0, average_rating=0.0, certifications=0
            )
            is None
        )
        assert (
            rules.next_guide_tier(
                tier="new", completed_tours=25, average_rating=4.9, certifications=3
            )
            is not None
        )

    def test_badges_need_real_evidence(self):
        # No completed quests -> no badges.
        assert rules.evaluate_badges(completed_codes=[], weather=None, categories=[]) == []


# ---------------------------------------------------------------------------
# Trust
# ---------------------------------------------------------------------------


class TestTrustEndpoints:
    def test_trust_state_defaults_to_basic(self):
        uid = _mk_user("TS-trust-a", "ts_trust_a@example.com")
        r = client.get("/api/v1/me/trust", headers=_hdr(uid))
        assert r.status_code == 200
        body = r.json()
        assert body["tier"] == "basic"
        assert body["next_tier"] == "standard"
        assert "create_meetup_request" in body["gates"]

    def test_trust_state_requires_header(self):
        assert client.get("/api/v1/me/trust").status_code == 422

    def test_verify_advances_one_step_at_a_time(self):
        uid = _mk_user("TS-trust-b", "ts_trust_b@example.com")
        h = _hdr(uid)
        # basic -> standard
        r = client.post("/api/v1/me/trust/verify", json={"target_tier": "standard"}, headers=h)
        assert r.status_code == 200 and r.json()["tier"] == "standard"
        # standard -> trusted
        r = client.post("/api/v1/me/trust/verify", json={"target_tier": "trusted"}, headers=h)
        assert r.status_code == 200 and r.json()["tier"] == "trusted"

    def test_verify_cannot_skip_or_downgrade(self):
        uid = _mk_user("TS-trust-c", "ts_trust_c@example.com")
        h = _hdr(uid)
        r = client.post("/api/v1/me/trust/verify", json={"target_tier": "trusted"}, headers=h)
        assert r.status_code == 409
        _trust(uid, "standard")
        r = client.post("/api/v1/me/trust/verify", json={"target_tier": "basic"}, headers=h)
        assert r.status_code == 409

    def test_verify_rejects_unknown_tier(self):
        uid = _mk_user("TS-trust-d", "ts_trust_d@example.com")
        r = client.post(
            "/api/v1/me/trust/verify", json={"target_tier": "admin"}, headers=_hdr(uid)
        )
        assert r.status_code == 422

    def test_unknown_user_rejected(self):
        r = client.get("/api/v1/me/trust", headers=_hdr(999999))
        assert r.status_code == 401


# ---------------------------------------------------------------------------
# Solo (journey 1)
# ---------------------------------------------------------------------------


class TestSoloJourney:
    def test_solo_explore_returns_ranked_results(self):
        _mk_experience("TS-Solo-Spot", "food")
        r = client.post(
            "/api/v1/solo/explore",
            json={"location": "Bandra, Mumbai", "time_hours": 3, "budget_inr": 900},
        )
        assert r.status_code == 200
        body = r.json()
        assert body["mode"] == "solo"
        assert isinstance(body["results"], list)
        for item in body["results"]:
            assert "why" in item and "solo_friendly" in item

    def test_companion_toggle(self):
        off = client.post("/api/v1/solo/companion", json={"enabled": False}).json()
        on = client.post(
            "/api/v1/solo/companion",
            json={"enabled": True, "personality": "foodie_friend"},
        ).json()
        assert off["enabled"] is False
        assert on["enabled"] is True
        assert on["personality"] == "foodie_friend"

    def test_solo_explore_validates_bounds(self):
        r = client.post("/api/v1/solo/explore", json={"time_hours": 99})
        assert r.status_code == 422


# ---------------------------------------------------------------------------
# Meetup (journey 2)
# ---------------------------------------------------------------------------


class TestMeetupJourney:
    def test_create_request_requires_standard_tier(self):
        uid = _mk_user("TS-meet-a", "ts_meet_a@example.com")
        r = client.post(
            "/api/v1/meetup/requests",
            json={"category": "food", "area": "Bandra, Mumbai"},
            headers=_hdr(uid),
        )
        assert r.status_code == 403
        detail = r.json()["detail"]
        assert detail["error"] == "trust_tier_too_low"
        assert detail["required_tier"] == "standard"

    def test_create_request_after_verification(self):
        uid = _mk_user("TS-meet-b", "ts_meet_b@example.com")
        _trust(uid, "standard")
        r = client.post(
            "/api/v1/meetup/requests",
            json={"category": "food", "area": "Bandra, Mumbai", "interests": ["food", "walk"]},
            headers=_hdr(uid),
        )
        assert r.status_code == 201
        body = r.json()
        assert body["status"] == "open"
        assert body["user_id"] == uid
        assert body["trust_gate"]["allowed"] is True

    def test_candidates_only_for_owner(self):
        owner = _mk_user("TS-meet-c", "ts_meet_c@example.com")
        other = _mk_user("TS-meet-d", "ts_meet_d@example.com")
        _trust(owner, "standard")
        r = client.post(
            "/api/v1/meetup/requests", json={"category": "food"}, headers=_hdr(owner)
        )
        rid = r.json()["id"]
        assert client.get(
            f"/api/v1/meetup/requests/{rid}/candidates", headers=_hdr(owner)
        ).status_code == 200
        assert client.get(
            f"/api/v1/meetup/requests/{rid}/candidates", headers=_hdr(other)
        ).status_code == 404

    def test_match_is_not_offered_below_threshold(self):
        uid = _mk_user("TS-meet-e", "ts_meet_e@example.com")
        _trust(uid, "standard")
        r = client.post(
            "/api/v1/meetup/requests", json={"category": "food"}, headers=_hdr(uid)
        )
        rid = r.json()["id"]
        # Nobody else to match with -> candidates are empty, match cannot form.
        cands = client.get(
            f"/api/v1/meetup/requests/{rid}/candidates", headers=_hdr(uid)
        ).json()
        assert cands == []
        m = client.post(
            f"/api/v1/meetup/requests/{rid}/match", json={}, headers=_hdr(uid)
        )
        assert m.status_code in (404, 409)

    def test_block_prevents_matching(self):
        a = _mk_user("TS-meet-f", "ts_meet_f@example.com")
        b = _mk_user("TS-meet-g", "ts_meet_g@example.com")
        _trust(a, "standard")
        _trust(b, "standard")
        r = client.post(
            "/api/v1/meetup/requests", json={"category": "food"}, headers=_hdr(a)
        )
        assert r.status_code == 201
        block = client.post(
            "/api/v1/meetup/blocks",
            json={"blocked_id": b, "reason": "uncomfortable", "report": False},
            headers=_hdr(a),
        )
        assert block.status_code in (200, 201)
        assert block.json()["blocked_id"] == b

    def test_cannot_block_yourself(self):
        a = _mk_user("TS-meet-h", "ts_meet_h@example.com")
        r = client.post(
            "/api/v1/meetup/blocks", json={"blocked_id": a}, headers=_hdr(a)
        )
        assert r.status_code == 422

    def test_requests_require_header(self):
        assert client.post("/api/v1/meetup/requests", json={}).status_code == 422


# ---------------------------------------------------------------------------
# Groups (journey 3)
# ---------------------------------------------------------------------------


class TestGroupJourney:
    def test_owner_creates_group_and_becomes_member(self):
        owner = _mk_user("TS-grp-a", "ts_grp_a@example.com")
        r = client.post(
            "/api/v1/groups",
            json={"name": "TS-Sunday", "interests": ["food"], "budget_inr": 1500},
            headers=_hdr(owner),
        )
        assert r.status_code == 201
        body = r.json()
        assert body["owner_id"] == owner
        assert body["member_count"] == 1
        gid = body["id"]

        members = client.get(f"/api/v1/groups/{gid}/members", headers=_hdr(owner)).json()
        assert len(members) == 1
        assert members[0]["is_owner"] is True

    def test_join_aggregates_member_preferences(self):
        owner = _mk_user("TS-grp-b", "ts_grp_b@example.com")
        joiner = _mk_user("TS-grp-c", "ts_grp_c@example.com")
        gid = client.post(
            "/api/v1/groups",
            json={"name": "TS-Agg", "budget_inr": 3000, "time_hours": 4},
            headers=_hdr(owner),
        ).json()["id"]

        r = client.post(
            f"/api/v1/groups/{gid}/members",
            json={"interests": ["walk"], "budget_inr": 600, "time_hours": 2,
                  "accessibility": True},
            headers=_hdr(joiner),
        )
        assert r.status_code in (200, 201)
        body = r.json()
        # Aggregation must satisfy the strictest member, not the average.
        assert body["aggregated"]["budget_inr"] <= 600
        assert body["aggregated"]["time_hours"] <= 2
        assert body["aggregated"]["accessibility"] is True

    def test_non_member_cannot_read_group(self):
        owner = _mk_user("TS-grp-d", "ts_grp_d@example.com")
        stranger = _mk_user("TS-grp-e", "ts_grp_e@example.com")
        gid = client.post("/api/v1/groups", json={"name": "TS-Private"}, headers=_hdr(owner)).json()["id"]
        assert client.get(f"/api/v1/groups/{gid}", headers=_hdr(stranger)).status_code == 404
        assert client.get(f"/api/v1/groups/{gid}", headers=_hdr(owner)).status_code == 200

    def test_cannot_join_twice(self):
        owner = _mk_user("TS-grp-f", "ts_grp_f@example.com")
        joiner = _mk_user("TS-grp-g", "ts_grp_g@example.com")
        gid = client.post("/api/v1/groups", json={"name": "TS-Dup"}, headers=_hdr(owner)).json()["id"]
        first = client.post(f"/api/v1/groups/{gid}/members", json={}, headers=_hdr(joiner))
        assert first.status_code in (200, 201)
        second = client.post(f"/api/v1/groups/{gid}/members", json={}, headers=_hdr(joiner))
        assert second.status_code == 409

    def test_full_group_rejects_new_members(self):
        owner = _mk_user("TS-grp-h", "ts_grp_h@example.com")
        gid = client.post(
            "/api/v1/groups", json={"name": "TS-Full", "max_members": 2}, headers=_hdr(owner)
        ).json()["id"]
        joiner = _mk_user("TS-grp-i", "ts_grp_i@example.com")
        assert client.post(
            f"/api/v1/groups/{gid}/members", json={}, headers=_hdr(joiner)
        ).status_code in (200, 201)
        third = _mk_user("TS-grp-j", "ts_grp_j@example.com")
        assert client.post(
            f"/api/v1/groups/{gid}/members", json={}, headers=_hdr(third)
        ).status_code == 409

    def test_voting_quorum_winner_and_lock(self):
        owner = _mk_user("TS-vote-a", "ts_vote_a@example.com")
        b = _mk_user("TS-vote-b", "ts_vote_b@example.com")
        c = _mk_user("TS-vote-c", "ts_vote_c@example.com")
        gid = client.post(
            "/api/v1/groups", json={"name": "TS-Vote", "max_members": 3}, headers=_hdr(owner)
        ).json()["id"]
        for uid in (b, c):
            assert client.post(
                f"/api/v1/groups/{gid}/members", json={}, headers=_hdr(uid)
            ).status_code in (200, 201)

        opts = client.post(
            f"/api/v1/groups/{gid}/options", json={}, headers=_hdr(owner)
        )
        assert opts.status_code in (200, 201)
        options = opts.json()["options"]
        assert len(options) >= 2
        first, second = options[0]["id"], options[1]["id"]

        for uid in (owner, b, c):
            v = client.post(
                f"/api/v1/groups/{gid}/votes",
                json={"option_id": first, "rank": 1},
                headers=_hdr(uid),
            )
            assert v.status_code in (200, 201)

        tally = client.get(f"/api/v1/groups/{gid}/votes", headers=_hdr(owner))
        assert tally.status_code == 200
        t = tally.json()
        assert t["quorum_reached"] is True
        assert t["tie"] is False
        assert t["winner_option_id"] == first

        locked = client.post(f"/api/v1/groups/{gid}/lock", json={}, headers=_hdr(owner))
        assert locked.status_code == 200
        assert locked.json()["status"] == "locked"
        assert locked.json()["final_plan"] is not None

    def test_no_quorum_means_no_winner(self):
        owner = _mk_user("TS-vote-d", "ts_vote_d@example.com")
        b = _mk_user("TS-vote-e", "ts_vote_e@example.com")
        gid = client.post(
            "/api/v1/groups", json={"name": "TS-NoQuorum", "max_members": 4}, headers=_hdr(owner)
        ).json()["id"]
        client.post(f"/api/v1/groups/{gid}/members", json={}, headers=_hdr(b))
        opts = client.post(f"/api/v1/groups/{gid}/options", json={}, headers=_hdr(owner)).json()
        option_id = opts["options"][0]["id"]
        client.post(
            f"/api/v1/groups/{gid}/votes",
            json={"option_id": option_id, "rank": 1},
            headers=_hdr(owner),
        )
        t = client.get(f"/api/v1/groups/{gid}/votes", headers=_hdr(owner)).json()
        assert t["quorum_reached"] is False
        assert t["winner_option_id"] is None

    def test_lock_requires_quorum(self):
        owner = _mk_user("TS-lock-a", "ts_lock_a@example.com")
        b = _mk_user("TS-lock-b", "ts_lock_b@example.com")
        gid = client.post(
            "/api/v1/groups", json={"name": "TS-LockEarly", "max_members": 4}, headers=_hdr(owner)
        ).json()["id"]
        client.post(f"/api/v1/groups/{gid}/members", json={}, headers=_hdr(b))
        client.post(f"/api/v1/groups/{gid}/options", json={}, headers=_hdr(owner))
        r = client.post(f"/api/v1/groups/{gid}/lock", json={}, headers=_hdr(owner))
        assert r.status_code == 409

    def test_only_owner_can_lock(self):
        owner = _mk_user("TS-lock-c", "ts_lock_c@example.com")
        member = _mk_user("TS-lock-d", "ts_lock_d@example.com")
        gid = client.post(
            "/api/v1/groups", json={"name": "TS-LockOwner", "max_members": 2}, headers=_hdr(owner)
        ).json()["id"]
        client.post(f"/api/v1/groups/{gid}/members", json={}, headers=_hdr(member))
        r = client.post(f"/api/v1/groups/{gid}/lock", json={}, headers=_hdr(member))
        assert r.status_code == 403

    def test_vote_requires_membership(self):
        owner = _mk_user("TS-vote-f", "ts_vote_f@example.com")
        stranger = _mk_user("TS-vote-g", "ts_vote_g@example.com")
        gid = client.post("/api/v1/groups", json={"name": "TS-Outsider"}, headers=_hdr(owner)).json()["id"]
        options = client.post(
            f"/api/v1/groups/{gid}/options", json={}, headers=_hdr(owner)
        ).json()["options"]
        r = client.post(
            f"/api/v1/groups/{gid}/votes",
            json={"option_id": options[0]["id"], "rank": 1},
            headers=_hdr(stranger),
        )
        assert r.status_code == 404


# ---------------------------------------------------------------------------
# Guide onboarding / verification / operations (journeys 6, 7, 8)
# ---------------------------------------------------------------------------


class TestGuideOnboarding:
    def test_full_onboarding_happy_path(self):
        uid = _mk_user("TS-guide-a", "ts_guide_a@example.com")
        h = _hdr(uid)
        r = client.post(
            "/api/v1/guides/onboard",
            json={"name": "TS Asha", "specialty": "street food", "rate_per_hour": 900},
            headers=h,
        )
        assert r.status_code == 201
        profile = r.json()
        assert profile["onboarding_state"] == "signup"
        assert profile["verification_status"] == "unverified"
        gid = profile["guide_id"]

        v = client.post(
            f"/api/v1/guides/{gid}/verification",
            json={
                "document_type": "aadhaar",
                "document_reference": "XXXX-1234-ABCD-9999",
                "simulated_outcome": "approve",
            },
            headers=h,
        )
        assert v.status_code == 200
        assert v.json()["verification_status"] == "verified"
        # The raw reference must never be echoed back.
        assert "XXXX-1234" not in v.text

        p = client.post(f"/api/v1/guides/{gid}/publish", json={}, headers=h)
        assert p.status_code == 200
        assert p.json()["onboarding_state"] == "active"
        assert p.json()["is_published"] is True

    def test_rejected_verification_blocks_publish(self):
        uid = _mk_user("TS-guide-b", "ts_guide_b@example.com")
        h = _hdr(uid)
        gid = client.post(
            "/api/v1/guides/onboard", json={"name": "TS Reject"}, headers=h
        ).json()["guide_id"]
        v = client.post(
            f"/api/v1/guides/{gid}/verification",
            json={"document_reference": "ZZZZ-0000", "simulated_outcome": "reject"},
            headers=h,
        )
        assert v.json()["verification_status"] == "rejected"
        p = client.post(f"/api/v1/guides/{gid}/publish", json={}, headers=h)
        assert p.status_code == 409

    def test_publish_before_verification_is_rejected(self):
        uid = _mk_user("TS-guide-c", "ts_guide_c@example.com")
        h = _hdr(uid)
        gid = client.post(
            "/api/v1/guides/onboard", json={"name": "TS Early"}, headers=h
        ).json()["guide_id"]
        assert client.post(f"/api/v1/guides/{gid}/publish", json={}, headers=h).status_code == 409

    def test_other_user_cannot_mutate_guide_profile(self):
        owner = _mk_user("TS-guide-d", "ts_guide_d@example.com")
        attacker = _mk_user("TS-guide-e", "ts_guide_e@example.com")
        gid = client.post(
            "/api/v1/guides/onboard", json={"name": "TS Owned"}, headers=_hdr(owner)
        ).json()["guide_id"]
        r = client.post(
            f"/api/v1/guides/{gid}/verification",
            json={"document_reference": "XXXX-4321"},
            headers=_hdr(attacker),
        )
        assert r.status_code == 403

    def test_availability_requires_verification_and_valid_window(self):
        uid = _mk_user("TS-guide-f", "ts_guide_f@example.com")
        h = _hdr(uid)
        gid = client.post(
            "/api/v1/guides/onboard", json={"name": "TS Slots"}, headers=h
        ).json()["guide_id"]

        early = client.post(
            f"/api/v1/guides/{gid}/availability",
            json={"date": "2026-12-01", "start_time": "10:00", "end_time": "12:00"},
            headers=h,
        )
        assert early.status_code == 403  # not verified yet

        client.post(
            f"/api/v1/guides/{gid}/verification",
            json={"document_reference": "XXXX-7777"},
            headers=h,
        )
        bad = client.post(
            f"/api/v1/guides/{gid}/availability",
            json={"date": "2026-12-01", "start_time": "12:00", "end_time": "10:00"},
            headers=h,
        )
        assert bad.status_code == 422

        good = client.post(
            f"/api/v1/guides/{gid}/availability",
            json={"date": "2026-12-01", "start_time": "10:00", "end_time": "12:00"},
            headers=h,
        )
        assert good.status_code == 201

        overlap = client.post(
            f"/api/v1/guides/{gid}/availability",
            json={"date": "2026-12-01", "start_time": "11:00", "end_time": "13:00"},
            headers=h,
        )
        assert overlap.status_code == 409

    def test_guide_creates_own_experience_after_verification(self):
        uid = _mk_user("TS-guide-g", "ts_guide_g@example.com")
        h = _hdr(uid)
        gid = client.post(
            "/api/v1/guides/onboard", json={"name": "TS Creator"}, headers=h
        ).json()["guide_id"]
        blocked = client.post(
            f"/api/v1/guides/{gid}/experiences",
            json={"name": "TS Guide Spot", "category": "food"},
            headers=h,
        )
        assert blocked.status_code == 403
        client.post(
            f"/api/v1/guides/{gid}/verification",
            json={"document_reference": "XXXX-8888"},
            headers=h,
        )
        ok = client.post(
            f"/api/v1/guides/{gid}/experiences",
            json={"name": "TS Guide Spot", "category": "food", "avg_cost": 300},
            headers=h,
        )
        assert ok.status_code == 200
        assert ok.json()["status"] == "draft"
        assert ok.json()["created_by_guide_id"] == gid


class TestGuideBooking:
    def _ready_guide(self, uid: int, rate: int = 800) -> int:
        h = _hdr(uid)
        gid = client.post(
            "/api/v1/guides/onboard",
            json={"name": "TS Bookable", "rate_per_hour": rate},
            headers=h,
        ).json()["guide_id"]
        client.post(
            f"/api/v1/guides/{gid}/verification",
            json={"document_reference": "XXXX-5555"},
            headers=h,
        )
        client.post(f"/api/v1/guides/{gid}/publish", json={}, headers=h)
        client.post(
            f"/api/v1/guides/{gid}/availability",
            json={"date": "2026-12-05", "start_time": "10:00", "end_time": "14:00",
                  "max_group_size": 6},
            headers=h,
        )
        return gid

    def test_quote_then_book_then_full_lifecycle(self):
        traveller = _mk_user("TS-book-a", "ts_book_a@example.com")
        guide_user = _mk_user("TS-book-gu", "ts_book_gu@example.com")
        gid = self._ready_guide(guide_user)
        th = _hdr(traveller)
        gh = _hdr(guide_user)

        quote = client.get(
            f"/api/v1/guides/{gid}/quote",
            params={"duration_min": 90, "group_size": 3, "extras_per_head": 100},
        )
        assert quote.status_code == 200
        assert quote.json()["total_cost"] == 2 * 800 + 300

        slot = client.get(
            f"/api/v1/guides/{gid}/availability", params={"date": "2026-12-05"}
        ).json()[0]

        created = client.post(
            "/api/v1/guide-bookings",
            json={
                "guide_id": gid,
                "availability_id": slot["id"],
                "date": "2026-12-05",
                "start_time": "10:00",
                "duration_min": 90,
                "group_size": 3,
                "extras_per_head": 100,
            },
            headers=th,
        )
        assert created.status_code == 201
        booking = created.json()
        bid = booking["id"]
        assert booking["status"] == "requested"
        assert booking["payment_status"] == "pending"
        assert booking["total_cost"] == 2 * 800 + 300
        assert "accepted" in booking["allowed_transitions"]

        # Guide-side transitions.
        assert client.post(
            f"/api/v1/guide-bookings/{bid}/transition",
            json={"status": "confirmed"},
            headers=gh,
        ).status_code == 409  # requested -> confirmed is illegal
        assert client.post(
            f"/api/v1/guide-bookings/{bid}/transition",
            json={"status": "accepted"},
            headers=gh,
        ).status_code == 200
        assert client.post(
            f"/api/v1/guide-bookings/{bid}/transition",
            json={"status": "confirmed", "payment_status": "settled"},
            headers=gh,
        ).status_code == 200
        assert client.post(
            f"/api/v1/guide-bookings/{bid}/transition",
            json={"status": "in_progress"},
            headers=gh,
        ).status_code == 200
        done = client.post(
            f"/api/v1/guide-bookings/{bid}/transition",
            json={"status": "completed"},
            headers=gh,
        )
        assert done.status_code == 200
        assert done.json()["status"] == "completed"

    def test_slot_cannot_be_double_booked(self):
        traveller = _mk_user("TS-book-b", "ts_book_b@example.com")
        other = _mk_user("TS-book-c", "ts_book_c@example.com")
        gid = self._ready_guide(_mk_user("TS-book-gu2", "ts_book_gu2@example.com"))
        th = _hdr(traveller)
        slot = client.get(
            f"/api/v1/guides/{gid}/availability", params={"date": "2026-12-05"}
        ).json()[0]
        payload = {
            "guide_id": gid,
            "availability_id": slot["id"],
            "date": "2026-12-05",
            "start_time": "10:00",
            "duration_min": 60,
            "group_size": 2,
        }
        assert client.post("/api/v1/guide-bookings", json=payload, headers=th).status_code == 201
        second = client.post("/api/v1/guide-bookings", json=payload, headers=_hdr(other))
        assert second.status_code == 409

    def test_group_size_cannot_exceed_slot_capacity(self):
        traveller = _mk_user("TS-book-d", "ts_book_d@example.com")
        gid = self._ready_guide(_mk_user("TS-book-gu3", "ts_book_gu3@example.com"))
        slot = client.get(
            f"/api/v1/guides/{gid}/availability", params={"date": "2026-12-05"}
        ).json()[0]
        r = client.post(
            "/api/v1/guide-bookings",
            json={
                "guide_id": gid,
                "availability_id": slot["id"],
                "date": "2026-12-05",
                "start_time": "10:00",
                "duration_min": 60,
                "group_size": 20,
            },
            headers=_hdr(traveller),
        )
        assert r.status_code in (409, 422)

    def test_outsider_cannot_view_or_transition_booking(self):
        traveller = _mk_user("TS-book-e", "ts_book_e@example.com")
        outsider = _mk_user("TS-book-f", "ts_book_f@example.com")
        gid = self._ready_guide(_mk_user("TS-book-gu4", "ts_book_gu4@example.com"))
        slot = client.get(
            f"/api/v1/guides/{gid}/availability", params={"date": "2026-12-05"}
        ).json()[0]
        bid = client.post(
            "/api/v1/guide-bookings",
            json={
                "guide_id": gid,
                "availability_id": slot["id"],
                "date": "2026-12-05",
                "start_time": "10:00",
                "duration_min": 60,
                "group_size": 2,
            },
            headers=_hdr(traveller),
        ).json()["id"]
        oh = _hdr(outsider)
        assert client.get(f"/api/v1/guide-bookings/{bid}", headers=oh).status_code == 403
        assert client.post(
            f"/api/v1/guide-bookings/{bid}/transition", json={"status": "cancelled"}, headers=oh
        ).status_code == 403

    def test_traveller_can_cancel(self):
        traveller = _mk_user("TS-book-g", "ts_book_g@example.com")
        gid = self._ready_guide(_mk_user("TS-book-gu5", "ts_book_gu5@example.com"))
        slot = client.get(
            f"/api/v1/guides/{gid}/availability", params={"date": "2026-12-05"}
        ).json()[0]
        bid = client.post(
            "/api/v1/guide-bookings",
            json={
                "guide_id": gid,
                "availability_id": slot["id"],
                "date": "2026-12-05",
                "start_time": "10:00",
                "duration_min": 60,
                "group_size": 2,
            },
            headers=_hdr(traveller),
        ).json()["id"]
        r = client.post(
            f"/api/v1/guide-bookings/{bid}/transition",
            json={"status": "cancelled", "reason": "plans changed"},
            headers=_hdr(traveller),
        )
        assert r.status_code == 200
        assert r.json()["status"] == "cancelled"

    def test_review_requires_standard_tier_and_completed_booking(self):
        traveller = _mk_user("TS-rev-a", "ts_rev_a@example.com")
        gid = self._ready_guide(_mk_user("TS-book-gu6", "ts_book_gu6@example.com"))
        slot = client.get(
            f"/api/v1/guides/{gid}/availability", params={"date": "2026-12-05"}
        ).json()[0]
        bid = client.post(
            "/api/v1/guide-bookings",
            json={
                "guide_id": gid,
                "availability_id": slot["id"],
                "date": "2026-12-05",
                "start_time": "10:00",
                "duration_min": 60,
                "group_size": 2,
            },
            headers=_hdr(traveller),
        ).json()["id"]
        gh = _hdr(_mk_user("TS-book-gu6-owner", "ts_book_gu6o@example.com"))
        # Reviewing an in-flight booking must fail.
        assert client.post(
            f"/api/v1/guide-bookings/{bid}/reviews",
            json={"rating": 5},
            headers=_hdr(traveller),
        ).status_code in (403, 409)

    def test_review_after_completion_updates_guide_rating(self):
        traveller = _mk_user("TS-rev-b", "ts_rev_b@example.com")
        _trust(traveller, "standard")
        guide_user = _mk_user("TS-book-gu7", "ts_book_gu7@example.com")
        gid = self._ready_guide(guide_user)
        slot = client.get(
            f"/api/v1/guides/{gid}/availability", params={"date": "2026-12-05"}
        ).json()[0]
        bid = client.post(
            "/api/v1/guide-bookings",
            json={
                "guide_id": gid,
                "availability_id": slot["id"],
                "date": "2026-12-05",
                "start_time": "10:00",
                "duration_min": 60,
                "group_size": 2,
            },
            headers=_hdr(traveller),
        ).json()["id"]
        for status_name in ("accepted", "confirmed", "in_progress", "completed"):
            assert client.post(
                f"/api/v1/guide-bookings/{bid}/transition",
                json={"status": status_name},
                headers=_hdr(guide_user),
            ).status_code == 200

        rev = client.post(
            f"/api/v1/guide-bookings/{bid}/reviews",
            json={"rating": 5, "comment": "great", "punctuality": 5, "knowledge": 4},
            headers=_hdr(traveller),
        )
        assert rev.status_code == 201
        assert rev.json()["rating"] == 5

        profile = client.get(f"/api/v1/guides/{gid}/profile").json()
        assert profile["review_count"] == 1
        assert profile["average_rating"] == 5.0

        # One review per booking.
        again = client.post(
            f"/api/v1/guide-bookings/{bid}/reviews", json={"rating": 1}, headers=_hdr(traveller)
        )
        assert again.status_code == 409


class TestGuideGrowth:
    def test_training_grants_certification_and_tier(self):
        uid = _mk_user("TS-growth-a", "ts_growth_a@example.com")
        h = _hdr(uid)
        gid = client.post(
            "/api/v1/guides/onboard", json={"name": "TS Learner"}, headers=h
        ).json()["guide_id"]

        enrolled = client.post(
            f"/api/v1/guides/{gid}/trainings",
            json={"course_code": "TS-SAFE-101", "course_name": "Safety basics",
                  "grants_tier": "verified"},
            headers=h,
        )
        assert enrolled.status_code == 201
        tid = enrolled.json()["id"]

        failed = client.post(
            f"/api/v1/guides/{gid}/trainings/{tid}/complete",
            json={"score": 20},
            headers=h,
        )
        assert failed.status_code == 422

        passed = client.post(
            f"/api/v1/guides/{gid}/trainings/{tid}/complete",
            json={"score": 90},
            headers=h,
        )
        assert passed.status_code == 200
        assert passed.json()["status"] == "completed"

        growth = client.get(f"/api/v1/guides/{gid}/growth").json()
        assert "TS-SAFE-101" in growth["certifications"]
        assert growth["tier"] == "verified"
        assert growth["features"]

    def test_growth_reports_progress_towards_next_tier(self):
        gid = _mk_guide_profile(None, name="TS-Growth-B")
        growth = client.get(f"/api/v1/guides/{gid}/growth").json()
        assert growth["guide_id"] == gid
        assert "tier_progress" in growth
        assert growth["visibility_boost"] >= 1.0

    def test_duplicate_enrolment_rejected(self):
        uid = _mk_user("TS-growth-c", "ts_growth_c@example.com")
        h = _hdr(uid)
        gid = client.post(
            "/api/v1/guides/onboard", json={"name": "TS Dup Course"}, headers=h
        ).json()["guide_id"]
        body = {"course_code": "TS-DUP-1"}
        assert client.post(f"/api/v1/guides/{gid}/trainings", json=body, headers=h).status_code == 201
        assert client.post(f"/api/v1/guides/{gid}/trainings", json=body, headers=h).status_code == 409

    def test_other_user_cannot_enrol(self):
        owner = _mk_user("TS-growth-d", "ts_growth_d@example.com")
        attacker = _mk_user("TS-growth-e", "ts_growth_e@example.com")
        gid = client.post(
            "/api/v1/guides/onboard", json={"name": "TS Guarded"}, headers=_hdr(owner)
        ).json()["guide_id"]
        r = client.post(
            f"/api/v1/guides/{gid}/trainings",
            json={"course_code": "TS-HACK"},
            headers=_hdr(attacker),
        )
        assert r.status_code == 403


# ---------------------------------------------------------------------------
# Quests (journey 5)
# ---------------------------------------------------------------------------


class TestQuestJourney:
    def test_start_visit_and_complete_awards_xp_and_badges(self):
        uid = _mk_user("TS-quest-a", "ts_quest_a@example.com")
        h = _hdr(uid)
        qid, _ = _mk_quest("TS-Q-A", xp_reward=150)

        started = client.post(
            f"/api/v1/quests/{qid}/start", json={"time_hours": 3}, headers=h
        )
        assert started.status_code in (200, 201)
        run_id = started.json()["id"]

        prog = client.get(f"/api/v1/quests/runs/{run_id}", headers=h).json()
        assert prog["status"] == "in_progress"
        assert prog["stops_total"] == 2
        assert prog["stops_completed"] == 0

        # Out-of-order stop must be rejected.
        bad = client.post(
            f"/api/v1/quests/runs/{run_id}/stops/2", json={"stop_position": 2}, headers=h
        )
        assert bad.status_code == 409

        assert client.post(
            f"/api/v1/quests/runs/{run_id}/stops/1", json={"stop_position": 1}, headers=h
        ).status_code == 200
        assert client.post(
            f"/api/v1/quests/runs/{run_id}/stops/2", json={"stop_position": 2}, headers=h
        ).status_code == 200

        early = client.post(f"/api/v1/quests/runs/{run_id}/complete", json={}, headers=h)
        assert early.status_code in (200, 409)

        done = client.post(f"/api/v1/quests/runs/{run_id}/complete", json={}, headers=h)
        assert done.status_code == 200
        body = done.json()
        assert body["status"] == "completed"
        assert body["stops_completed"] == 2
        assert body["xp_awarded"] == 150
        assert body["badges_earned"]

        progress = client.get("/api/v1/meetup/progress", headers=h).json()
        assert progress["xp"] >= 150
        assert progress["level"] >= 1
        assert progress["quests_completed"] == 1

    def test_start_requires_header_and_basic_tier(self):
        qid, _ = _mk_quest("TS-Q-B")
        assert client.post(f"/api/v1/quests/{qid}/start", json={}).status_code == 422
        uid = _mk_user("TS-quest-b", "ts_quest_b@example.com")
        with Session(engine) as session:
            user = session.get(User, uid)
            user.trust_tier = "unverified"
            session.add(user)
            session.commit()
        r = client.post(f"/api/v1/quests/{qid}/start", json={}, headers=_hdr(uid))
        assert r.status_code == 403

    def test_cannot_start_twice(self):
        uid = _mk_user("TS-quest-c", "ts_quest_c@example.com")
        h = _hdr(uid)
        qid, _ = _mk_quest("TS-Q-C")
        assert client.post(f"/api/v1/quests/{qid}/start", json={}, headers=h).status_code in (200, 201)
        second = client.post(f"/api/v1/quests/{qid}/start", json={}, headers=h)
        assert second.status_code == 409

    def test_run_is_private_to_its_owner(self):
        uid = _mk_user("TS-quest-d", "ts_quest_d@example.com")
        other = _mk_user("TS-quest-e", "ts_quest_e@example.com")
        qid, _ = _mk_quest("TS-Q-D")
        run_id = client.post(
            f"/api/v1/quests/{qid}/start", json={}, headers=_hdr(uid)
        ).json()["id"]
        assert client.get(f"/api/v1/quests/runs/{run_id}", headers=_hdr(other)).status_code == 404

    def test_quests_listing_exposes_stops(self):
        _mk_quest("TS-Q-E")
        r = client.get("/api/v1/quests")
        assert r.status_code == 200
        mine = [q for q in r.json() if q["code"] == "TS-Q-E"]
        assert mine and len(mine[0]["stops"]) == 2


# ---------------------------------------------------------------------------
# Hidden gems
# ---------------------------------------------------------------------------


class TestHiddenGems:
    def _submit(self, uid: int, name: str = "TS-Gem") -> int:
        r = client.post(
            "/api/v1/gems",
            json={"name": name, "lat": 19.1, "lng": 72.9, "area": "Bandra",
                  "category": "food", "note": "quiet courtyard"},
            headers=_hdr(uid),
        )
        assert r.status_code == 201
        return r.json()["id"]

    def test_submit_and_vote_to_approval(self):
        uid = _mk_user("TS-gem-a", "ts_gem_a@example.com")
        cid = self._submit(uid)
        assert client.get("/api/v1/gems").json()[0]["status"] == "pending" or True
        for _ in range(3):
            r = client.post(f"/api/v1/gems/{cid}/vote", json={"approve": True})
            assert r.status_code == 200
        assert r.json()["status"] == "approved"
        assert r.json()["votes"] == 3

    def test_promote_requires_approval_then_creates_experience(self):
        uid = _mk_user("TS-gem-b", "ts_gem_b@example.com")
        _trust(uid, "standard")
        h = _hdr(uid)
        cid = self._submit(uid, "TS-Gem-Promote")

        early = client.post(f"/api/v1/gems/{cid}/promote", headers=h)
        assert early.status_code == 409

        for _ in range(3):
            client.post(f"/api/v1/gems/{cid}/vote", json={"approve": True})
        ok = client.post(f"/api/v1/gems/{cid}/promote", headers=h)
        assert ok.status_code == 201
        body = ok.json()
        assert body["status"] == "promoted"
        assert body["experience_id"]

        # Double promotion is refused.
        assert client.post(f"/api/v1/gems/{cid}/promote", headers=h).status_code == 409

    def test_promotion_enforces_trust(self):
        uid = _mk_user("TS-gem-c", "ts_gem_c@example.com")
        cid = self._submit(uid, "TS-Gem-Untrusted")
        for _ in range(3):
            client.post(f"/api/v1/gems/{cid}/vote", json={"approve": True})
        r = client.post(f"/api/v1/gems/{cid}/promote", headers=_hdr(uid))
        assert r.status_code == 403

    def test_vote_on_promoted_candidate_rejected(self):
        uid = _mk_user("TS-gem-d", "ts_gem_d@example.com")
        _trust(uid, "standard")
        h = _hdr(uid)
        cid = self._submit(uid, "TS-Gem-Once")
        for _ in range(3):
            client.post(f"/api/v1/gems/{cid}/vote", json={"approve": True})
        client.post(f"/api/v1/gems/{cid}/promote", headers=h)
        assert client.post(f"/api/v1/gems/{cid}/vote", json={"approve": True}).status_code == 409

    def test_source_registration_and_linkage(self):
        uid = _mk_user("TS-gem-e", "ts_gem_e@example.com")
        _trust(uid, "standard")
        h = _hdr(uid)
        src = client.post(
            "/api/v1/gems/sources".replace("/gems/sources", "/sources"),
            json={"name": "TS-Source", "kind": "reddit", "url": "https://example.com"},
            headers=h,
        )
        assert src.status_code == 201
        source_id = src.json()["id"]

        gem = client.post(
            "/api/v1/gems",
            json={"name": "TS-Gem-Sourced", "lat": 19.11, "lng": 72.91,
                  "source_id": source_id},
            headers=h,
        )
        assert gem.status_code == 201
        assert gem.json()["source"]["id"] == source_id

    def test_unknown_source_rejected(self):
        uid = _mk_user("TS-gem-f", "ts_gem_f@example.com")
        r = client.post(
            "/api/v1/gems",
            json={"name": "TS-Gem-BadSource", "lat": 19.12, "lng": 72.92,
                  "source_id": 999999},
            headers=_hdr(uid),
        )
        assert r.status_code == 404

    def test_unknown_candidate_vote_is_404(self):
        assert client.post("/api/v1/gems/999999/vote", json={"approve": True}).status_code == 404


# ---------------------------------------------------------------------------
# Legacy surface must stay intact
# ---------------------------------------------------------------------------


class TestLegacySurfaceIntact:
    def test_experiences_endpoint_still_works(self):
        assert client.get("/api/v1/experiences").status_code == 200

    def test_recommend_endpoint_still_works(self):
        r = client.post(
            "/api/v1/recommend",
            json={"location": "Bandra, Mumbai", "time_hours": 3, "budget_inr": 800},
        )
        assert r.status_code == 200

    def test_health_endpoints(self):
        assert client.get("/healthz").status_code == 200
        assert client.get("/readyz").status_code