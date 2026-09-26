"""Contract tests for the app-facing /places and /context endpoints.

These pin the shapes the Flutter repositories parse (camelCase keys, absolute
image URLs, the ``Place -> Experience`` split) plus the heuristic traffic bands.
"""

from fastapi.testclient import TestClient
from sqlmodel import Session, select

from app.database import engine
from app.models import Experience
from main import app

client = TestClient(app)

MUMBAI = {"lat": 19.0596, "lng": 72.8295}


# ---------------------------------------------------------------------------
# Places
# ---------------------------------------------------------------------------


def test_list_places_returns_app_place_shape():
    r = client.get("/api/v1/places", params={**MUMBAI, "limit": 5})
    assert r.status_code == 200, r.text
    places = r.json()
    assert places, "seed data should yield places"

    place = places[0]
    for key in (
        "id",
        "name",
        "category",
        "address",
        "area",
        "centre",
        "heroImageUrl",
        "imageUrls",
        "openingHours",
        "accessibility",
        "rating",
        "reviewCount",
        "priceLevel",
        "typicalSpend",
        "crowdLevel",
        "indoor",
        "localFavourite",
        "bookingRequired",
    ):
        assert key in place, f"missing {key}"

    assert set(place["centre"]) == {"latitude", "longitude"}
    assert isinstance(place["typicalSpend"], int)
    assert 0 <= place["priceLevel"] <= 4
    assert place["crowdLevel"] in {"quiet", "moderate", "busy", "veryBusy"}
    assert place["heroImageUrl"].startswith("http")
    # Category must be a value the Dart enum can parse.
    assert place["category"] in {
        "food", "culture", "history", "art", "nature", "heritage",
        "nightlife", "shopping", "wellness", "adventure", "localLife",
    }


def test_place_detail_and_experiences():
    first = client.get("/api/v1/places", params={**MUMBAI, "limit": 1}).json()[0]
    place_id = first["id"]

    detail = client.get(f"/api/v1/places/{place_id}")
    assert detail.status_code == 200
    assert detail.json()["id"] == place_id

    experiences = client.get(f"/api/v1/places/{place_id}/experiences")
    assert experiences.status_code == 200
    items = experiences.json()
    assert len(items) == 1
    exp = items[0]
    for key in (
        "id", "placeId", "title", "tagline", "description", "category",
        "imageUrl", "activityMinutes", "typicalSpend", "weatherSuitability",
        "localScore", "touristScore", "highlights",
    ):
        assert key in exp, f"missing {key}"
    assert exp["placeId"] == place_id
    assert exp["weatherSuitability"] in {
        "indoorOnly", "sheltered", "weatherSensitive", "allWeather"
    }


def test_place_detail_404():
    assert client.get("/api/v1/places/999999").status_code == 404
    assert client.get("/api/v1/places/not-a-number").status_code == 404


def test_places_category_and_spend_filters():
    r = client.get(
        "/api/v1/places",
        params={**MUMBAI, "categories": ["food"], "max_spend": 500, "limit": 20},
    )
    assert r.status_code == 200, r.text
    for place in r.json():
        assert place["category"] == "food"
        assert place["typicalSpend"] <= 500


def test_places_text_filter():
    r = client.get("/api/v1/places", params={"text": "kebab", "limit": 10})
    assert r.status_code == 200
    for place in r.json():
        assert "kebab" in place["name"].lower() or "kebab" in (place.get("summary") or "").lower()


def test_popular_and_gems():
    for path, params in (
        ("/api/v1/places/popular", {**MUMBAI, "limit": 5}),
        ("/api/v1/places/gems", {**MUMBAI, "limit": 5}),
    ):
        r = client.get(path, params=params)
        assert r.status_code == 200, r.text
        assert isinstance(r.json(), list)


def test_discover_returns_places_and_experiences():
    r = client.get("/api/v1/places/discover", params={"text": "street food", "limit": 5})
    assert r.status_code == 200, r.text
    body = r.json()
    assert set(body) == {"places", "experiences", "interpreted_query"}
    assert len(body["places"]) == len(body["experiences"])
    assert body["interpreted_query"] == "street food"


def test_legacy_places_search_still_mounted():
    """The Google Places integration router must keep its own routes."""
    r = client.get("/api/v1/places/search", params={"q": "cafe", "limit": 3})
    assert r.status_code in (200, 422, 503)  # 503 only if Places is disabled


def test_experience_endpoint_carries_app_fields():
    with Session(engine) as session:
        exp = session.exec(select(Experience)).first()
    r = client.get(f"/api/v1/experiences/{exp.id}")
    assert r.status_code == 200
    body = r.json()
    assert body["title"] == exp.name
    assert body["place_id"] == str(exp.id)
    assert body["activity_minutes"] == exp.duration_min
    assert body["typical_spend"] == exp.avg_cost
    assert 0 <= body["local_score"] <= 100
    assert body["weather_suitability"]


# ---------------------------------------------------------------------------
# Context
# ---------------------------------------------------------------------------

_FAKE_WEATHER = {
    "available": True,
    "temp_c": 31.5,
    "feels_like_c": 36.0,
    "humidity": 65,
    "condition": "drizzle",
    "is_rainy": True,
    "suitable_outdoor": False,
    "description": "Drizzle, 31.5°C",
    "precipitation_chance": 70,
    "wind_kph": 11.2,
    "uv_index": 4.0,
    "sunrise": "2026-09-26T06:28",
    "sunset": "2026-09-26T18:31",
    "observed_at": "2026-09-26T12:00:00+00:00",
}


def _patch_weather(monkeypatch):
    async def fake_fetch(lat=19.0, lon=72.8):
        return _FAKE_WEATHER

    monkeypatch.setattr("app.api.v1.weather.fetch_weather", fake_fetch)


def test_weather_endpoint_app_shape(monkeypatch):
    _patch_weather(monkeypatch)
    r = client.get("/api/v1/weather", params=MUMBAI)
    assert r.status_code == 200, r.text
    body = r.json()
    assert body["temperature_c"] == 31.5
    assert body["apparent_temperature_c"] == 36.0
    assert body["humidity"] == 65
    assert body["precipitation_chance"] == 70
    assert body["wind_kph"] == 11.2
    assert body["uv_index"] == 4.0
    # drizzle -> rain in the app vocabulary.
    assert body["condition"] == "rain"
    assert body["sunrise"].startswith("2026-09-26T06:28")


def test_weather_accepts_lng_alias(monkeypatch):
    seen = {}

    async def fake_fetch(lat=19.0, lon=72.8):
        seen["lat"], seen["lon"] = lat, lon
        return _FAKE_WEATHER

    monkeypatch.setattr("app.api.v1.weather.fetch_weather", fake_fetch)
    client.get("/api/v1/weather", params={"lat": 18.9, "lng": 72.83})
    assert seen["lat"] == 18.9
    assert abs(seen["lon"] - 72.83) < 1e-6


def test_traffic_endpoint_shape():
    r = client.get("/api/v1/traffic", params=MUMBAI)
    assert r.status_code == 200, r.text
    traffic = r.json()["traffic"]
    assert set(traffic) == {"level", "speedMultiplier", "updatedAt"}
    assert traffic["level"] in {"light", "moderate", "heavy", "severe"}
    assert traffic["speedMultiplier"] > 0


def test_live_context_combines_both(monkeypatch):
    _patch_weather(monkeypatch)
    r = client.get("/api/v1/context/live", params=MUMBAI)
    assert r.status_code == 200, r.text
    body = r.json()
    assert set(body) == {"weather", "traffic"}
    assert body["weather"]["condition"] == "rain"
    assert body["traffic"]["level"]


def test_traffic_bands_by_hour_and_weekend():
    from app.services import context as context_service

    assert context_service._traffic_band(2, 0) == ("light", 0.9)
    assert context_service._traffic_band(8, 0) == ("heavy", 1.45)
    assert context_service._traffic_band(13, 0) == ("moderate", 1.15)
    assert context_service._traffic_band(19, 0) == ("severe", 1.8)
    assert context_service._traffic_band(23, 0) == ("light", 0.95)
    # Weekends are calmer at the peak with more midday traffic.
    assert context_service._traffic_band(8, 6) == ("moderate", 1.2)
    assert context_service._traffic_band(19, 6) == ("heavy", 1.45)


def test_weather_fallback_has_all_app_keys():
    from app.services import context as context_service
    from app.services.weather import neutral_weather

    app_weather = context_service.app_weather(neutral_weather(reason="test"))
    for key in (
        "temperatureC", "condition", "apparentTemperatureC", "humidity",
        "precipitationChance", "windKph", "uvIndex", "observedAt", "sunrise", "sunset",
    ):
        assert key in app_weather
    assert app_weather["condition"] == "cloudy"  # unknown -> cloudy for the app
    assert app_weather["temperatureC"] == 28.0
