"""Phase 4 performance tests: weather cache, recommendation cache,
DB-level budget filtering, image placeholders."""

import asyncio

from fastapi.testclient import TestClient

from app.models import Experience
from app.schemas import ExperienceResponse
from app.services import weather
from main import app

client = TestClient(app)


# ---------------------------------------------------------------------------
# 4.1 Weather cache
# ---------------------------------------------------------------------------


def test_weather_cache_avoids_second_fetch(monkeypatch):
    calls = {"n": 0}

    async def fake_live(lat, lon):
        calls["n"] += 1
        return {
            "available": True,
            "condition": "clear",
            "description": "Clear, 30°C",
            "is_rainy": False,
            "suitable_outdoor": True,
            "temp_c": 30,
        }

    monkeypatch.setattr(weather, "_fetch_weather_live", fake_live)
    weather.clear_weather_cache()

    async def run():
        return await weather.fetch_weather(19.0, 72.0), await weather.fetch_weather(19.0, 72.0)

    first, second = asyncio.run(run())
    assert first == second
    assert calls["n"] == 1, "second call must be served from cache"


def test_weather_failure_is_not_cached(monkeypatch):
    calls = {"n": 0}

    async def fake_live(lat, lon):
        calls["n"] += 1
        return weather.neutral_weather(reason="test")

    monkeypatch.setattr(weather, "_fetch_weather_live", fake_live)
    weather.clear_weather_cache()

    async def run():
        await weather.fetch_weather(10.0, 70.0)
        await weather.fetch_weather(10.0, 70.0)

    asyncio.run(run())
    assert calls["n"] == 2, "failures must not be cached"


# ---------------------------------------------------------------------------
# 4.2 Recommendation cache
# ---------------------------------------------------------------------------


def test_recommend_cache_hit():
    from app.api.v1 import recommendations

    recommendations.clear_recommend_cache()
    payload = {
        "location": "Bandstand",
        "time_hours": 3,
        "budget_inr": 900,
        "interests": ["food"],
        "limit": 5,
    }

    first = client.post("/api/v1/recommend", json=payload)
    second = client.post("/api/v1/recommend", json=payload)

    assert first.status_code == second.status_code == 200
    assert first.json() == second.json()
    assert recommendations.recommend_cache_stats()["hits"] >= 1


# ---------------------------------------------------------------------------
# 4.3 DB-level budget filtering
# ---------------------------------------------------------------------------


def test_recommend_filters_budget_in_sql_but_reports_full_pool():
    from app.api.v1 import recommendations

    recommendations.clear_recommend_cache()
    response = client.post(
        "/api/v1/recommend", json={"budget_inr": 500, "limit": 20, "time_hours": 6}
    )
    assert response.status_code == 200
    data = response.json()

    # Pool size is the full table, not the budget-filtered candidate set.
    assert data["total_candidates"] >= 40
    for item in data["recommendations"]:
        assert item["estimated_cost"] <= 500


def test_avg_cost_index_registered():
    assert "ix_experiences_avg_cost" in {index.name for index in Experience.__table__.indexes}


# ---------------------------------------------------------------------------
# 4.4 Image enrichment
# ---------------------------------------------------------------------------


def test_experiences_have_image_placeholder():
    response = client.get("/api/v1/experiences?limit=3")
    assert response.status_code == 200
    for item in response.json()["items"]:
        assert item["image_url"], "every card needs an image"
        # Images are either a backend-hosted curated asset (served at
        # /static/images/...) or an absolute http(s) URL (e.g. Google proxy).
        assert item["image_url"].startswith(("/static/images/", "http://", "https://")), (
            f"unexpected image_url: {item['image_url']}"
        )


def test_provided_image_url_is_preserved():
    experience = ExperienceResponse(
        id=1,
        name="Curated",
        category="food",
        lat=19.0,
        lng=72.8,
        avg_cost=100,
        duration_min=60,
        open_time="09:00",
        close_time="21:00",
        rating=4.5,
        description="",
        image_url="https://example.com/curated.jpg",
    )
    assert experience.image_url == "https://example.com/curated.jpg"
