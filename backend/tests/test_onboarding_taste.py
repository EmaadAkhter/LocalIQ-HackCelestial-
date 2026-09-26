"""Tests for guided taste onboarding."""

import uuid

from fastapi.testclient import TestClient

from main import app

client = TestClient(app)


def _register() -> str:
    email = f"onboarding-{uuid.uuid4().hex[:10]}@localiq.test"
    r = client.post(
        "/api/v1/auth/register",
        json={"name": "Onboarding Guest", "email": email, "password": "Secret123"},
    )
    assert r.status_code == 201, r.text
    return r.json()["access_token"]


def _auth(token: str) -> dict:
    return {"Authorization": f"Bearer {token}"}


def _answer(token: str, session_id: int, **payload):
    return client.post(
        f"/api/v1/onboarding/user/{session_id}/answer",
        json=payload,
        headers=_auth(token),
    )


def _walk(token: str, *, avoid_text: str = "I dislike nightlife", notes: str = "I love sunrise walks") -> dict:
    """Drive the whole conversation, always taking the first option."""
    start = client.post("/api/v1/onboarding/user/start", json={}, headers=_auth(token))
    assert start.status_code == 200, start.text
    step = start.json()
    session_id = step["session_id"]

    for _ in range(12):
        if step["done"]:
            break
        if step["free_text"]:
            payload = {"message": avoid_text if step["step"] == 5 else notes}
        elif step["options"]:
            payload = {"selections": [step["options"][0]]}
        else:
            payload = {"message": "anything"}
        r = _answer(token, session_id, **payload)
        assert r.status_code == 200, r.text
        step = r.json()
    return step


# ---------------------------------------------------------------------------


def test_start_returns_the_first_prompt():
    token = _register()
    r = client.post("/api/v1/onboarding/user/start", json={}, headers=_auth(token))
    assert r.status_code == 200, r.text
    body = r.json()
    assert body["step"] == 0
    assert body["status"] == "in_progress"
    assert body["total_steps"] >= 5
    assert "Mumbai" in body["prompt"]
    assert body["options"]
    assert body["done"] is False


def test_start_requires_auth():
    assert client.post("/api/v1/onboarding/user/start", json={}).status_code == 401


def test_status_before_start_is_not_started():
    token = _register()
    body = client.get("/api/v1/onboarding/user/status", headers=_auth(token)).json()
    assert body["status"] == "not_started"
    assert body["completed"] is False


def test_start_resumes_an_in_progress_session():
    token = _register()
    first = client.post("/api/v1/onboarding/user/start", json={}, headers=_auth(token)).json()
    second = client.post("/api/v1/onboarding/user/start", json={}, headers=_auth(token)).json()
    assert first["session_id"] == second["session_id"]


def test_restart_creates_a_new_session():
    token = _register()
    first = client.post("/api/v1/onboarding/user/start", json={}, headers=_auth(token)).json()
    second = client.post(
        "/api/v1/onboarding/user/start", json={"restart": True}, headers=_auth(token)
    ).json()
    assert second["session_id"] != first["session_id"]


def test_full_conversation_builds_a_taste_profile():
    token = _register()
    final = _walk(token)
    assert final["done"] is True
    assert final["status"] == "completed"
    taste = final["taste"]
    assert taste["likes"], "the conversation should produce positive tags"
    assert taste["text"]

    # The profile is visible on the taste endpoint.
    snap = client.get("/api/v1/me/taste", headers=_auth(token)).json()
    assert snap["vector"]


def test_avoid_step_produces_negative_tags():
    token = _register()
    final = _walk(token, avoid_text="I really dislike street food and crowds")
    assert final["done"] is True
    vector = final["taste"]["vector"]
    negatives = {k: v for k, v in vector.items() if v < 0}
    assert negatives, "the avoid step should learn dislikes"


def test_answer_to_unknown_session_404s():
    token = _register()
    r = _answer(token, 999999, selections=["First time"])
    assert r.status_code == 404


def test_answer_to_someone_elses_session_404s():
    owner = _register()
    other = _register()
    start = client.post("/api/v1/onboarding/user/start", json={}, headers=_auth(owner)).json()
    r = _answer(other, start["session_id"], selections=["First time"])
    assert r.status_code == 404


def test_answering_after_completion_is_stable():
    token = _register()
    final = _walk(token)
    sid = final["session_id"]
    again = _answer(token, sid, message="one more thing")
    assert again.status_code == 200
    assert again.json()["status"] == "completed"
