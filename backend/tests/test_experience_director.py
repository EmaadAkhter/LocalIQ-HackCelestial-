"""Tests for the AI Experience Director (PRD 4.10)."""

import uuid

from fastapi.testclient import TestClient
from sqlmodel import Session, select

from app.database import engine
from app.models import Experience
from main import app

client = TestClient(app)

RAINY = {"available": True, "is_rainy": True, "suitable_outdoor": False, "condition": "rain"}


def _register() -> str:
    email = f"director-{uuid.uuid4().hex[:10]}@localiq.test"
    r = client.post(
        "/api/v1/auth/register",
        json={"name": "Director User", "email": email, "password": "Secret123"},
    )
    assert r.status_code == 201, r.text
    return r.json()["access_token"]


def _auth(token: str) -> dict:
    return {"Authorization": f"Bearer {token}"}


def _experience(outdoor: bool | None = None) -> Experience:
    with Session(engine) as session:
        rows = list(session.exec(select(Experience)).all())
    if outdoor is True:
        rows = [e for e in rows if e.indoor_outdoor == "outdoor" or "beach" in (e.tags or [])]
    elif outdoor is False:
        rows = [e for e in rows if e.indoor_outdoor == "indoor"]
    assert rows, "seed data needs a matching experience"
    return rows[0]


def _start(token: str, **body) -> dict:
    r = client.post("/api/v1/director/sessions", json=body, headers=_auth(token))
    assert r.status_code == 201, r.text
    return r.json()


# ---------------------------------------------------------------------------
# Start
# ---------------------------------------------------------------------------


def test_start_session_for_experience():
    token = _register()
    exp = _experience()
    body = _start(token, experience_id=exp.id)
    assert body["status"] == "active"
    assert len(body["stops"]) == 1
    assert body["stops"][0]["experience_id"] == exp.id


def test_start_requires_a_target():
    token = _register()
    r = client.post("/api/v1/director/sessions", json={}, headers=_auth(token))
    assert r.status_code == 422


def test_start_unknown_experience_422():
    token = _register()
    r = client.post(
        "/api/v1/director/sessions", json={"experience_id": 999999}, headers=_auth(token)
    )
    assert r.status_code == 422


def test_start_requires_auth():
    assert client.post("/api/v1/director/sessions", json={"experience_id": 1}).status_code == 401


# ---------------------------------------------------------------------------
# Check-in tips
# ---------------------------------------------------------------------------


def test_check_in_returns_tips_then_exhausts():
    token = _register()
    exp = _experience()
    live = _start(token, experience_id=exp.id)

    seen: list[int] = []
    for _ in range(10):
        r = client.post(
            f"/api/v1/director/sessions/{live['id']}/check-in",
            json={"lat": exp.lat, "lng": exp.lng},
            headers=_auth(token),
        )
        assert r.status_code == 200, r.text
        body = r.json()
        if body["tip"] is None:
            assert "caught up" in body["message"].lower()
            break
        assert body["tip"]["message"]
        seen.append(body["tip"]["id"])
    assert seen, "at least one tip should be returned"
    assert len(seen) == len(set(seen)), "tips must not repeat within a session"


# ---------------------------------------------------------------------------
# Adaptation
# ---------------------------------------------------------------------------


def test_adapt_rainy_outdoor_suggests_alternative(monkeypatch):
    token = _register()
    exp = _experience(outdoor=True)

    async def fake_weather(*args, **kwargs):
        return RAINY

    monkeypatch.setattr("app.services.experience_director.fetch_weather", fake_weather)

    live = _start(token, experience_id=exp.id)
    r = client.post(
        f"/api/v1/director/sessions/{live['id']}/adapt",
        json={"lat": exp.lat, "lng": exp.lng},
        headers=_auth(token),
    )
    assert r.status_code == 200, r.text
    body = r.json()
    assert body["adaptation_needed"] is True
    assert "rain" in body["message"].lower()
    if body["suggestion"] is not None:
        assert body["suggestion"]["indoor_outdoor"] != "outdoor"


def test_adapt_fair_weather_is_quiet(monkeypatch):
    token = _register()
    exp = _experience()
    fair = {"available": True, "is_rainy": False, "suitable_outdoor": True, "condition": "clear"}

    async def fake_weather(*args, **kwargs):
        return fair

    monkeypatch.setattr("app.services.experience_director.fetch_weather", fake_weather)
    live = _start(token, experience_id=exp.id)
    r = client.post(
        f"/api/v1/director/sessions/{live['id']}/adapt",
        json={"lat": exp.lat, "lng": exp.lng},
        headers=_auth(token),
    )
    assert r.status_code == 200
    assert r.json()["adaptation_needed"] is False


# ---------------------------------------------------------------------------
# End + wallet integration
# ---------------------------------------------------------------------------


def test_end_session_summarises_and_logs_to_wallet():
    token = _register()
    exp = _experience()
    live = _start(token, experience_id=exp.id)

    r = client.post(
        f"/api/v1/director/sessions/{live['id']}/end",
        json={"rating": 4.5, "notes": "Great outing"},
        headers=_auth(token),
    )
    assert r.status_code == 200, r.text
    body = r.json()
    assert body["status"] == "completed"
    assert body["summary"]["total_stops"] == 1
    assert body["summary"]["total_cost"] >= 0
    assert body["summary"]["insight"]

    wallet = client.get("/api/v1/me/wallet", headers=_auth(token)).json()
    assert wallet["stats"]["total_experiences"] == 1


def test_itinerary_session_covers_all_stops():
    token = _register()
    with Session(engine) as session:
        exps = list(session.exec(select(Experience)).all())[:2]

    itinerary = client.post(
        "/api/v1/itineraries",
        json={"name": "Director plan", "stops": [{"experience_id": e.id} for e in exps]},
        headers=_auth(token),
    ).json()

    live = _start(token, itinerary_id=itinerary["id"])
    assert len(live["stops"]) == 2

    ended = client.post(
        f"/api/v1/director/sessions/{live['id']}/end", json={}, headers=_auth(token)
    ).json()
    assert ended["summary"]["total_stops"] == 2
    wallet = client.get("/api/v1/me/wallet", headers=_auth(token)).json()
    assert wallet["stats"]["total_experiences"] == 2


# ---------------------------------------------------------------------------
# Ownership
# ---------------------------------------------------------------------------


def test_session_is_private_to_owner():
    owner = _register()
    other = _register()
    exp = _experience()
    live = _start(owner, experience_id=exp.id)

    assert (
        client.get(
            f"/api/v1/director/sessions/{live['id']}", headers=_auth(other)
        ).status_code
        == 404
    )
