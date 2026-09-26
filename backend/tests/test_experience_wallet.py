"""Tests for the Experience Wallet & Passport (PRD 4.9)."""

import uuid

from fastapi.testclient import TestClient
from sqlmodel import Session, select

from app.database import engine
from app.models import Experience
from main import app

client = TestClient(app)


def _register() -> str:
    email = f"wallet-{uuid.uuid4().hex[:10]}@localiq.test"
    r = client.post(
        "/api/v1/auth/register",
        json={"name": "Wallet User", "email": email, "password": "Secret123"},
    )
    assert r.status_code == 201, r.text
    return r.json()["access_token"]


def _auth(token: str) -> dict:
    return {"Authorization": f"Bearer {token}"}


def _experiences(n: int) -> list[Experience]:
    with Session(engine) as session:
        rows = list(session.exec(select(Experience)).all())
    assert len(rows) >= n
    return rows[:n]


def _log(token: str, experience_id: int, **extra):
    return client.post(
        "/api/v1/me/wallet/log",
        json={"experience_id": experience_id, **extra},
        headers=_auth(token),
    )


def test_wallet_requires_auth():
    assert client.get("/api/v1/me/wallet").status_code == 401
    assert client.post("/api/v1/me/wallet/log", json={"experience_id": 1}).status_code == 401


def test_log_experience_updates_wallet_and_awards_first_badge():
    token = _register()
    exp = _experiences(1)[0]
    r = _log(token, exp.id, rating=4.5, notes="Loved it")
    assert r.status_code == 201, r.text
    body = r.json()
    assert body["experience_id"] == exp.id
    assert body["stats"]["total_experiences"] == 1
    codes = [b["code"] for b in body["new_badges"]]
    assert "wallet_first_step" in codes


def test_log_is_idempotent():
    token = _register()
    exp = _experiences(1)[0]
    _log(token, exp.id)
    second = _log(token, exp.id, rating=5)
    assert second.status_code == 201
    assert second.json()["stats"]["total_experiences"] == 1


def test_passport_returns_stats_badges_timeline_pins():
    token = _register()
    exps = _experiences(2)
    _log(token, exps[0].id)
    _log(token, exps[1].id)

    r = client.get("/api/v1/me/wallet", headers=_auth(token))
    assert r.status_code == 200, r.text
    body = r.json()
    assert body["stats"]["total_experiences"] == 2
    assert len(body["timeline"]) == 2
    assert len(body["pins"]) == 2
    assert all("lat" in pin and "lng" in pin for pin in body["pins"])
    # Full badge catalogue is returned, earned flag set correctly.
    by_code = {b["code"]: b for b in body["badges"]}
    assert by_code["wallet_first_step"]["earned"] is True
    assert by_code["wallet_city_explorer"]["earned"] is False


def test_city_explorer_badge_at_ten_experiences():
    token = _register()
    exps = _experiences(10)
    for exp in exps:
        assert _log(token, exp.id).status_code == 201

    badges = client.get("/api/v1/me/wallet/badges", headers=_auth(token)).json()
    by_code = {b["code"]: b for b in badges}
    assert by_code["wallet_first_step"]["earned"] is True
    assert by_code["wallet_city_explorer"]["earned"] is True


def test_timeline_endpoint_and_limit():
    token = _register()
    exps = _experiences(3)
    for exp in exps:
        _log(token, exp.id)
    r = client.get("/api/v1/me/wallet/timeline?limit=2", headers=_auth(token))
    assert r.status_code == 200
    assert len(r.json()) == 2


def test_share_summary():
    token = _register()
    exp = _experiences(1)[0]
    _log(token, exp.id)
    r = client.get("/api/v1/me/wallet/share", headers=_auth(token))
    assert r.status_code == 200, r.text
    body = r.json()
    assert body["total_experiences"] == 1
    assert body["highlights"]


def test_completing_logs_a_taste_signal():
    token = _register()
    exp = _experiences(1)[0]
    _log(token, exp.id)
    interactions = client.get("/api/v1/me/taste", headers=_auth(token)).json()["interactions"]
    assert interactions.get("complete", 0) >= 1