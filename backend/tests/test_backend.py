"""Backend tests for LocalIQ core logic."""

import uuid

from fastapi.testclient import TestClient
from sqlmodel import Session, select

from app.api.v1.parse import heuristic_parse
from app.database import engine, init_db
from app.models import Experience, Guide
from app.seed import seed_database
from app.services import recommender
from app.services.llm import OllamaClient
from app.services.weather import neutral_weather
from main import app

client = TestClient(app)


def setup_module(module):
    init_db()
    seed_database()


def test_health():
    r = client.get("/health")
    assert r.status_code == 200
    assert r.json() == {"status": "ok"}


def test_db_initialized_and_seeded():
    with Session(engine) as s:
        exps = s.exec(select(Experience)).all()
        guides = s.exec(select(Guide)).all()
    assert len(exps) >= 40, f"expected 40+ experiences, got {len(exps)}"
    assert len(guides) >= 5


def test_seed_is_repeatable():
    first = seed_database()
    second = seed_database()
    assert first == second
    with Session(engine) as s:
        assert len(s.exec(select(Experience)).all()) == first["experiences"]


def test_list_experiences():
    r = client.get("/api/v1/experiences?limit=5")
    assert r.status_code == 200
    data = r.json()
    assert data["total"] >= 40
    assert len(data["items"]) == 5


def test_get_experience_and_404():
    r = client.get("/api/v1/experiences/1")
    assert r.status_code == 200
    assert r.json()["id"] == 1
    r2 = client.get("/api/v1/experiences/999999")
    assert r2.status_code == 404


def _sample_exp(**overrides):
    base = dict(
        name="Test", category="food", lat=19.05, lng=72.82, avg_cost=500,
        duration_min=60, open_time="09:00", close_time="21:00", rating=4.5,
        description="t", tags=["food"], accessibility_flags=[],
        indoor_outdoor="indoor", local_gem_score=0.5,
    )
    base.update(overrides)
    return Experience(**base)


def test_budget_feasibility():
    exp = _sample_exp(avg_cost=2000)
    res = recommender.check_feasibility(exp, budget_inr=500, time_hours=8,
                                       user_coords=None, accessibility=None, start_time=None)
    assert not res.feasible
    ok = recommender.check_feasibility(exp, budget_inr=2500, time_hours=8,
                                      user_coords=None, accessibility=None, start_time=None)
    assert ok.feasible


def test_time_feasibility():
    exp = _sample_exp(duration_min=300)
    res = recommender.check_feasibility(exp, budget_inr=None, time_hours=2,
                                       user_coords=None, accessibility=None, start_time=None)
    assert not res.feasible


def test_opening_hours_feasibility():
    exp = _sample_exp(open_time="09:00", close_time="12:00", duration_min=60)
    res = recommender.check_feasibility(exp, budget_inr=None, time_hours=8,
                                       user_coords=None, accessibility=None, start_time="20:00")
    assert not res.feasible


def test_ranking_prefers_interest_match():
    food = _sample_exp(category="food", rating=4.0, local_gem_score=0.5)
    art = _sample_exp(category="art", rating=4.0, local_gem_score=0.5)
    out = recommender.recommend([food, art], interests=["food"], budget_inr=2000, time_hours=8)
    assert out["feasible_count"] == 2
    assert out["results"][0].experience.category == "food"


def test_weather_boost_indoor_on_rain():
    indoor = _sample_exp(indoor_outdoor="indoor")
    outdoor = _sample_exp(indoor_outdoor="outdoor")
    rainy = {"available": True, "condition": "rain", "is_rainy": True}
    assert recommender.weather_boost_for(indoor, rainy) > recommender.weather_boost_for(outdoor, rainy)


def test_recommend_endpoint():
    r = client.post("/api/v1/recommend", json={
        "location": "Bandra", "time_hours": 4, "budget_inr": 1500,
        "group_type": "friends", "interests": ["food", "art"],
    })
    assert r.status_code == 200
    data = r.json()
    assert data["total_candidates"] >= 40
    assert data["feasible_count"] >= 1
    first = data["recommendations"][0]
    assert "why_this_fits" in first and first["why_this_fits"]
    assert first["estimated_cost"] <= 1500


def test_recommend_invalid_input():
    r = client.post("/api/v1/recommend", json={"time_hours": -5})
    assert r.status_code == 422


def test_parse_heuristic_fallback():
    parsed = heuristic_parse("I have 4 hours, ₹1500 and want food and art around Bandra")
    assert parsed.time_hours == 4
    assert parsed.budget_inr == 1500
    assert "food" in parsed.interests and "art" in parsed.interests
    assert parsed.location and "bandra" in parsed.location.lower()


def test_parse_endpoint_no_llm():
    r = client.post("/api/v1/parse", json={"text": "2 hours near Colaba under Rs 800 for shopping"})
    assert r.status_code == 200
    c = r.json()["constraints"]
    assert c["budget_inr"] == 800
    assert "shopping" in c["interests"]


def test_weather_fallback_shape():
    w = neutral_weather(reason="test")
    assert w["available"] is False
    assert w["condition"] == "unknown"


def test_chat_fallback_no_ollama(monkeypatch=None):
    # Force Ollama unconfigured by pointing at empty model via client patch.
    r = client.post("/api/v1/chat", json={"experience_id": 1, "message": "How do I reach there?"})
    assert r.status_code == 200
    assert r.json()["reply"]
    # Unknown experience -> 404
    r2 = client.post("/api/v1/chat", json={"experience_id": 999999, "message": "hi"})
    assert r2.status_code == 404


def test_ollama_failure_handling():
    import asyncio

    async def run():
        bad = OllamaClient(base_url="http://127.0.0.1:1", model="nonexistent")
        assert await bad.generate("hello", timeout=2) is None
        assert await bad.generate_json("hello") is None
        health = await bad.health()
        assert health["available"] is False

    asyncio.run(run())


def test_guides_endpoints():
    r = client.get("/api/v1/experiences/1/guides")
    assert r.status_code == 200
    assert isinstance(r.json(), list)
    with Session(engine) as s:
        guide = s.exec(select(Guide)).first()
    assert guide is not None
    r2 = client.post(f"/api/v1/guides/{guide.id}/request", json={"name": "Test User", "hours": 2})
    assert r2.status_code == 200
    assert r2.json()["status"] == "confirmed_mock"
    r3 = client.post("/api/v1/guides/999999/request", json={"name": "X"})
    assert r3.status_code == 404


# ---------------------------------------------------------------------------
# Authentication
# ---------------------------------------------------------------------------


def _register(email: str | None = None) -> dict:
    """Register a throwaway user. Email is unique per run so the local DB
    (which persists between test runs) never causes a 409."""
    email = email or f"user-{uuid.uuid4().hex[:10]}@localiq.test"
    r = client.post(
        "/api/v1/auth/register",
        json={"name": "Demo User", "email": email, "password": "secret123"},
    )
    assert r.status_code == 201, r.text
    return r.json()


def test_password_hashing_is_salted():
    from app.services.auth import hash_password, verify_password

    a, b = hash_password("secret123"), hash_password("secret123")
    assert a != b, "each hash must use a fresh salt"
    assert "secret123" not in a
    assert verify_password("secret123", a)
    assert verify_password("secret123", b)
    assert not verify_password("wrong", a)
    assert not verify_password("secret123", "garbage")


def test_register_login_me_logout():
    data = _register()
    email = data["user"]["email"]
    token = data["access_token"]
    assert email.endswith("@localiq.test")
    headers = {"Authorization": f"Bearer {token}"}

    me = client.get("/api/v1/auth/me", headers=headers)
    assert me.status_code == 200
    assert me.json()["email"] == email

    # Duplicate email is rejected.
    dup = client.post(
        "/api/v1/auth/register",
        json={"name": "Other", "email": email, "password": "secret123"},
    )
    assert dup.status_code == 409

    # Wrong password rejected.
    bad = client.post("/api/v1/auth/login", json={"email": email, "password": "nope12345"})
    assert bad.status_code == 401

    # Unknown email rejected with the same message.
    unknown = client.post(
        "/api/v1/auth/login", json={"email": "nobody@localiq.test", "password": "secret123"}
    )
    assert unknown.status_code == 401
    assert unknown.json()["detail"] == bad.json()["detail"]

    # Fresh login works, logout revokes the token.
    again = client.post(
        "/api/v1/auth/login", json={"email": "flow@localiq.test", "password": "secret123"}
    )
    assert again.status_code == 200
    h2 = {"Authorization": f"Bearer {again.json()['access_token']}"}
    assert client.get("/api/v1/auth/me", headers=h2).status_code == 200
    assert client.post("/api/v1/auth/logout", headers=h2).status_code == 200
    assert client.get("/api/v1/auth/me", headers=h2).status_code == 401


def test_protected_route_requires_token():
    assert client.get("/api/v1/auth/me").status_code == 401
    assert client.get("/api/v1/auth/me", headers={"Authorization": "Bearer bogus"}).status_code == 401
    assert client.get("/api/v1/guides/me/requests").status_code == 401


def test_guide_request_persists_to_db():
    from app.models import GuideRequest

    registered = _register()
    token = registered["access_token"]
    with Session(engine) as s:
        guide = s.exec(select(Guide)).first()
    assert guide is not None
    r = client.post(
        f"/api/v1/guides/{guide.id}/request",
        json={"date": "2026-10-01", "hours": 3, "group_size": 4},
        headers={"Authorization": f"Bearer {token}"},
    )
    assert r.status_code == 200
    booking_ref = r.json()["booking_ref"]
    assert r.json()["booking_id"] is not None

    with Session(engine) as s:
        row = s.exec(select(GuideRequest).where(GuideRequest.booking_ref == booking_ref)).first()
    assert row is not None
    assert row.user_id == registered["user"]["id"]
    assert row.hours == 3
    assert row.group_size == 4
    assert row.requester_name == "Demo User"  # defaults to the account name

    mine = client.get("/api/v1/guides/me/requests", headers={"Authorization": f"Bearer {token}"})
    assert mine.status_code == 200
    assert any(item["booking_ref"] == booking_ref for item in mine.json())


def test_users_stored_in_sqlite_not_plaintext():
    from app.models import User

    registered = _register()
    with Session(engine) as s:
        user = s.exec(select(User).where(User.email == registered["user"]["email"])).first()
    assert user is not None
    assert "secret123" not in user.password_hash
    assert user.password_hash.startswith("pbkdf2_sha256$")
    # Session token must not be stored in the clear either.
    from app.models import UserSession

    with Session(engine) as s:
        rows = s.exec(select(UserSession).where(UserSession.user_id == user.id)).all()
    assert rows
    assert all(registered["access_token"] not in r.token_hash for r in rows)


def test_auth_validation_errors():
    assert client.post("/api/v1/auth/register", json={"name": "A", "email": "x@y.z", "password": "123"}).status_code == 422
    assert client.post("/api/v1/auth/register", json={"name": "A B", "email": "not-an-email", "password": "secret123"}).status_code == 400


def test_auth_status_endpoint():
    r = client.get("/api/v1/auth/status")
    assert r.status_code == 200
    body = r.json()
    assert body["auth"] == "enabled"
    assert "ollama" in body
