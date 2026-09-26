"""Tests for the taste profile, the reranker layer, the three graphs and the agent."""

import uuid

from fastapi.testclient import TestClient
from sqlmodel import Session, select

from app.database import engine
from app.models import Experience
from main import app

client = TestClient(app)


def _register() -> str:
    email = f"taste-{uuid.uuid4().hex[:10]}@localiq.test"
    r = client.post(
        "/api/v1/auth/register",
        json={"name": "Taste User", "email": email, "password": "Secret123"},
    )
    assert r.status_code == 201, r.text
    return r.json()["access_token"]


def _auth(token: str) -> dict:
    return {"Authorization": f"Bearer {token}"}


def _first_experience() -> Experience:
    """First seeded experience, preferring one that actually has tags.

    Other suites can leave untagged ``TS-`` rows around; taste/reranker tests
    need real tags to observe a signal.
    """
    with Session(engine) as session:
        rows = list(session.exec(select(Experience)).all())
    for exp in rows:
        if exp.tags:
            return exp
    return rows[0]


# ---------------------------------------------------------------------------
# Taste service
# ---------------------------------------------------------------------------


def test_extract_tags_handles_likes_and_dislikes():
    from app.services import taste

    hits = taste.extract_tags_from_text(
        "I love street food and sunrise walks, but I hate nightlife"
    )
    assert hits.get("street_food", 0) > 0
    assert hits.get("sunrise", 0) > 0
    assert hits.get("nightlife", 0) < 0, "negated tags must be learned as dislikes"


def test_tag_weight_clamped_and_pruned():
    from app.services import taste

    vector = taste.apply_tag_weight({}, ["street_food"], 10.0)
    assert vector["street_food"] == taste._MAX_WEIGHT
    # Unknown tags are dropped.
    assert taste.apply_tag_weight({}, ["not_a_real_tag"], 1.0) == {}


# ---------------------------------------------------------------------------
# Reranker layer
# ---------------------------------------------------------------------------


def test_reranker_taste_boost_changes_score():
    from app.services.reranker import RerankContext, score_experience

    exp = _first_experience()
    tags = [t for t in (exp.tags or [])][:3]
    assert tags, "seed data should have tags"

    neutral = score_experience(exp, RerankContext(taste_vector={}))
    matched = score_experience(
        exp, RerankContext(taste_vector={t: 2.0 for t in tags})
    )
    assert matched.parts["taste"] > neutral.parts["taste"]


def test_reranker_drops_infeasible_windows():
    from app.services.reranker import RerankContext, rerank

    with Session(engine) as session:
        experiences = list(session.exec(select(Experience).limit(50)).all())

    generous = rerank(experiences, RerankContext(time_hours=12.0))
    tight = rerank(experiences, RerankContext(time_hours=0.2))
    assert len(generous) > len(tight)
    assert tight == []


def test_reranker_weights_sum_to_one():
    from app.services import reranker

    total = (
        reranker.W_BASE
        + reranker.W_TASTE
        + reranker.W_PROXIMITY
        + reranker.W_WEATHER
        + reranker.W_TIME_OF_DAY
    )
    assert abs(total - 1.0) < 1e-9


# ---------------------------------------------------------------------------
# Interactions + taste profile API
# ---------------------------------------------------------------------------


def test_interaction_updates_taste_vector():
    token = _register()
    exp = _first_experience()
    r = client.post(
        "/api/v1/interactions",
        json={"experience_id": exp.id, "action": "save"},
        headers=_auth(token),
    )
    assert r.status_code == 200, r.text
    body = r.json()
    assert body["vector"], "a save should nudge the taste vector"
    assert body["interactions"].get("save") == 1


def test_interactions_require_auth():
    exp = _first_experience()
    r = client.post(
        "/api/v1/interactions", json={"experience_id": exp.id, "action": "view"}
    )
    assert r.status_code == 401


def test_taste_profile_edit_and_pause():
    token = _register()
    r = client.put(
        "/api/v1/me/taste",
        json={
            "vector": {"street_food": 2.0, "nightlife": -1.0},
            "personalization_enabled": False,
        },
        headers=_auth(token),
    )
    assert r.status_code == 200, r.text
    body = r.json()
    assert body["vector"]["street_food"] == 2.0
    assert body["vector"]["nightlife"] == -1.0
    assert body["personalization_enabled"] is False
    assert "street food" in body["text"].lower()


def test_taste_refresh_uses_deterministic_fallback_in_tests():
    token = _register()
    client.put("/api/v1/me/taste", json={"vector": {"street_food": 1.5}}, headers=_auth(token))
    r = client.post("/api/v1/me/taste/refresh", headers=_auth(token))
    assert r.status_code == 200
    assert r.json()["text"]


# ---------------------------------------------------------------------------
# Graphs
# ---------------------------------------------------------------------------


def test_similar_experiences_endpoint():
    exp = _first_experience()
    r = client.get(f"/api/v1/experiences/{exp.id}/similar")
    assert r.status_code == 200
    rows = r.json()
    assert isinstance(rows, list) and rows
    assert rows[0]["experience"]["id"] != exp.id


def test_similar_experiences_404_for_unknown():
    assert client.get("/api/v1/experiences/999999/similar").status_code == 404


def test_user_matches_returns_list():
    token = _register()
    r = client.post("/api/v1/users/matches", json={"limit": 5}, headers=_auth(token))
    assert r.status_code == 200
    assert isinstance(r.json(), list)


def test_taste_recommend_endpoint_signed_out():
    r = client.post(
        "/api/v1/recommend/taste",
        json={"location": "Bandra", "time_hours": 3, "limit": 5},
    )
    assert r.status_code == 200, r.text
    rows = r.json()
    assert isinstance(rows, list) and rows
    assert rows[0]["experience"]["name"]
    assert "score" in rows[0]


# ---------------------------------------------------------------------------
# Companion / guide agent
# ---------------------------------------------------------------------------


def test_agent_clarifies_then_recommends():
    first = client.post("/api/v1/agent/chat", json={"message": "I want to do something today"})
    assert first.status_code == 200, first.text
    body = first.json()
    assert body["mode"] == "clarify"
    session_id = body["session_id"]
    assert body["reply"]

    second = client.post(
        "/api/v1/agent/chat",
        json={
            "session_id": session_id,
            "message": "I have 3 hours and I'm in Bandra, recommend something",
        },
    )
    assert second.status_code == 200, second.text
    body2 = second.json()
    assert body2["session_id"] == session_id
    assert body2["mode"] == "recommend"
    assert body2["recommendations"], "should return at least one pick"
    assert str(body2["constraints"].get("location", "")).lower() == "bandra"


def test_agent_guide_returns_tips():
    exp = _first_experience()
    r = client.post("/api/v1/agent/guide", json={"experience_id": exp.id})
    assert r.status_code == 200, r.text
    body = r.json()
    assert body["name"] == exp.name
    assert len(body["tips"]) >= 1


def test_agent_session_history_is_persisted():
    first = client.post("/api/v1/agent/chat", json={"message": "hello there"})
    session_id = first.json()["session_id"]
    r = client.get(f"/api/v1/agent/sessions/{session_id}")
    assert r.status_code == 200
    messages = r.json()["messages"]
    assert any(m["role"] == "user" for m in messages)
    assert any(m["role"] == "assistant" for m in messages)
