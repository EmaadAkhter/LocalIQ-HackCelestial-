"""Tests for the Context-Aware Right Now Engine (PRD 4.8)."""

from fastapi.testclient import TestClient
from sqlmodel import Session, select

from app.database import engine
from app.models import Experience
from main import app

client = TestClient(app)

RAINY = {"available": True, "is_rainy": True, "suitable_outdoor": False, "condition": "rain", "description": "Rain"}
CLEAR = {"available": True, "is_rainy": False, "suitable_outdoor": True, "condition": "clear", "description": "Clear"}


def _exp(**overrides) -> Experience:
    base = dict(
        id=1,
        name="X",
        category="culture",
        lat=19.0,
        lng=72.8,
        rating=4.5,
        local_gem_score=0.5,
        tags=[],
        crowd_density_level="MEDIUM",
        indoor_outdoor="indoor",
    )
    base.update(overrides)
    return Experience(**base)


# ---------------------------------------------------------------------------
# Scoring
# ---------------------------------------------------------------------------


def test_rain_prefers_indoor():
    from app.services import right_now

    indoor = _exp(indoor_outdoor="indoor")
    outdoor = _exp(id=2, name="Y", indoor_outdoor="outdoor", tags=["beach", "views"])
    now = 10 * 60
    indoor_score = right_now.score_for(indoor, weather=RAINY, now_min=now)["score"]
    outdoor_score = right_now.score_for(outdoor, weather=RAINY, now_min=now)["score"]
    assert indoor_score > outdoor_score


def test_clear_prefers_outdoor():
    from app.services import right_now

    indoor = _exp(indoor_outdoor="indoor")
    outdoor = _exp(id=2, name="Y", indoor_outdoor="outdoor", tags=["beach", "views"])
    now = 10 * 60
    assert (
        right_now.score_for(outdoor, weather=CLEAR, now_min=now)["score"]
        > right_now.score_for(indoor, weather=CLEAR, now_min=now)["score"]
    )


def test_sunset_window_boosts_viewpoints():
    from app.services import right_now

    viewpoint = _exp(tags=["sunset", "views"], indoor_outdoor="outdoor")
    sun = {"available": True, "sunset": "18:42", "sunrise": "06:20"}
    at_sunset = right_now.score_for(
        viewpoint, weather=CLEAR, sun=sun, now_min=18 * 60 + 12
    )
    at_noon = right_now.score_for(viewpoint, weather=CLEAR, sun=sun, now_min=12 * 60)
    assert at_sunset["components"]["time"] > at_noon["components"]["time"]
    assert any("Sunset" in line for line in at_sunset["context"])


def test_peak_hour_crowd_penalty():
    from app.services import right_now

    quiet = _exp(crowd_density_level="LOW")
    busy = _exp(id=2, name="Y", crowd_density_level="HIGH")
    peak = 13 * 60
    assert (
        right_now.score_for(quiet, weather=CLEAR, now_min=peak)["score"]
        >= right_now.score_for(busy, weather=CLEAR, now_min=peak)["score"]
    )


def test_labels_cover_the_range():
    from app.services import right_now

    assert right_now.label_for_score(95) == "Great right now"
    assert right_now.label_for_score(70) == "Good right now"
    assert right_now.label_for_score(55) == "Okay right now"
    assert right_now.label_for_score(20) == "Better later"


def test_context_always_has_at_least_one_line():
    from app.services import right_now

    result = right_now.score_for(_exp(), weather=CLEAR, now_min=10 * 60)
    assert result["context"], "the context panel must never be empty"
    assert 0.0 <= result["score"] <= 100.0


def test_weights_sum_to_one():
    from app.services import right_now

    total = (
        right_now.W_QUALITY
        + right_now.W_WEATHER
        + right_now.W_TIME
        + right_now.W_CROWD
        + right_now.W_SAFETY
    )
    assert abs(total - 1.0) < 1e-9


# ---------------------------------------------------------------------------
# Persistence
# ---------------------------------------------------------------------------


def test_refresh_scores_persists(monkeypatch):
    from app.services import right_now, weather

    async def fake_weather(lat=19.0, lon=72.8):
        return CLEAR

    async def fake_sun(lat=19.0, lon=72.8):
        return {"available": True, "sunset": "18:42", "sunrise": "06:20"}

    monkeypatch.setattr(weather, "fetch_weather", fake_weather)
    monkeypatch.setattr(weather, "fetch_sun_times", fake_sun)

    import asyncio

    with Session(engine) as session:
        count = asyncio.run(right_now.refresh_scores(session, limit=3))
        assert count == 3

    with Session(engine) as session:
        rows = session.exec(select(Experience).limit(3)).all()
        assert all(row.right_now_updated_at is not None for row in rows)
        assert all(0.0 <= row.right_now_score <= 100.0 for row in rows)
        assert all(row.right_now_context_json.get("label") for row in rows)


# ---------------------------------------------------------------------------
# Endpoints
# ---------------------------------------------------------------------------


def _patch_conditions(monkeypatch):
    monkeypatch.setattr("app.api.v1.right_now.fetch_weather", _fake_async(CLEAR))
    monkeypatch.setattr(
        "app.api.v1.right_now.fetch_sun_times",
        _fake_async({"available": True, "sunset": "18:42", "sunrise": "06:20"}),
    )


def _fake_async(value):
    async def _inner(*args, **kwargs):
        return value

    return _inner


def test_right_now_feed_endpoint(monkeypatch):
    _patch_conditions(monkeypatch)
    r = client.post(
        "/api/v1/recommend/right-now",
        json={"location": "Bandra", "time_hours": 3, "limit": 5},
    )
    assert r.status_code == 200, r.text
    items = r.json()
    assert items, "feed should not be empty"
    assert len(items) <= 5
    # Sorted by blended final score.
    finals = [item["final_score"] for item in items]
    assert finals == sorted(finals, reverse=True)
    for item in items:
        assert 0.0 <= item["right_now_score"] <= 100.0
        assert item["right_now_label"]
        assert item["context"], "every item needs a context line"
        assert item["experience"]["right_now_score"] is not None


def test_experience_right_now_detail(monkeypatch):
    _patch_conditions(monkeypatch)
    with Session(engine) as session:
        exp = session.exec(select(Experience)).first()
    r = client.get(f"/api/v1/experiences/{exp.id}/right-now")
    assert r.status_code == 200, r.text
    body = r.json()
    assert body["experience_id"] == exp.id
    assert set(body["components"]) == {"quality", "weather", "time", "crowd", "safety"}
    assert body["context"]


def test_experience_right_now_404():
    assert client.get("/api/v1/experiences/999999/right-now").status_code == 404


def test_admin_refresh_requires_admin_key():
    r = client.post("/api/v1/admin/right-now/refresh")
    assert r.status_code in (401, 503)
