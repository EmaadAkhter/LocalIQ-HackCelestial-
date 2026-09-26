"""Tests for the Google Places/Routes integration and the enriched API surface.

Covers:
  * normalization of Google payloads into LocalIQ models
  * Places text/nearby search with Google configured (mocked HTTP) and disabled
  * Routes compute + fallback to the local Haversine estimate
  * automatic SQLite fallback when Google is unavailable
  * the enriched /recommend and /experiences/{id} contracts
  * the photo proxy (no key ever reaches the client)
"""

from __future__ import annotations

import httpx
import pytest
from fastapi.testclient import TestClient
from sqlmodel import Session, select

from app.database import engine, init_db
from main import app
from app.schemas import OpeningHoursInfo, RouteInfo, WeatherContext
from app.seed import seed_database
from app.services import google_places, google_routes

client = TestClient(app)

PLACES_KEY = "test-places-key"
ROUTES_KEY = "test-routes-key"

GOOGLE_PLACE_PAYLOAD = {
    "places": [
        {
            "id": "ChIJ-test-place-id",
            "displayName": {"text": "Marine Drive Café"},
            "formattedAddress": "Netaji Subhash Chandra Bose Rd, Colaba",
            "shortDescription": "Sea-facing cafe",
            "location": {"latitude": 18.943, "longitude": 72.8225},
            "rating": 4.4,
            "userRatingCount": 1200,
            "priceLevel": "PRICE_LEVEL_MODERATE",
            "primaryType": "cafe",
            "types": ["cafe", "food", "point_of_interest"],
            "photos": [{"name": "places/ABC123/photos/DEF456"}],
            "regularOpeningHours": {
                "openNow": True,
                "weekdayDescriptions": [
                    "Monday: 8:00 AM – 11:00 PM",
                    "Tuesday: 8:00 AM – 11:00 PM",
                    "Wednesday: 8:00 AM – 11:00 PM",
                    "Thursday: 8:00 AM – 11:00 PM",
                    "Friday: 8:00 AM – 11:30 PM",
                    "Saturday: 8:00 AM – 11:30 PM",
                    "Sunday: 8:00 AM – 11:00 PM",
                ],
            },
            "googleMapsUri": "https://maps.google.com/?cid=1",
            "businessStatus": "OPERATIONAL",
        }
    ]
}

GOOGLE_ROUTE_PAYLOAD = {
    "routes": [
        {
            "distanceMeters": 5340,
            "duration": "1240s",
            "polyline": {"encodedPolyline": "abc123def456"},
            "legs": [{"distanceMeters": 5340, "duration": "1240s"}],
        }
    ]
}


def setup_module(module):
    init_db()
    seed_database()


@pytest.fixture(autouse=True)
def _no_server_keys(monkeypatch):
    """Default: no Google server keys, so the offline path is exercised."""
    from app.config import get_settings

    settings = get_settings()
    monkeypatch.setattr(settings, "google_places_api_key", "", raising=False)
    monkeypatch.setattr(settings, "google_routes_api_key", "", raising=False)
    yield


# ---------------------------------------------------------------------------
# Normalization
# ---------------------------------------------------------------------------


def test_normalize_place_maps_google_fields_to_localiq_model():
    result = google_places.normalize_place(GOOGLE_PLACE_PAYLOAD["places"][0])
    assert result.name == "Marine Drive Café"
    assert result.category == "food"  # primaryType cafe -> food
    assert result.lat == pytest.approx(18.943)
    assert result.lng == pytest.approx(72.8225)
    assert result.rating == pytest.approx(4.4)
    assert result.review_count == 1200
    assert result.avg_cost == 600  # PRICE_LEVEL_MODERATE
    assert result.source == "google_places"
    # Photo URL must be a LocalIQ proxy, never a Google URL containing a key.
    assert result.image_url is not None
    assert result.image_url.startswith("/api/v1/images/place")
    assert "googleapis.com" not in result.image_url
    assert "key=" not in result.image_url


def test_normalize_place_parses_opening_hours():
    result = google_places.normalize_place(GOOGLE_PLACE_PAYLOAD["places"][0])
    assert result.open_time == "08:00"
    assert result.close_time in {"23:00", "23:30"}
    assert result.open_now is True


def test_normalize_place_handles_unknown_fields():
    result = google_places.normalize_place({"displayName": {"text": "Mystery"}})
    assert result.category == "culture"
    assert result.avg_cost == 0
    assert result.image_url is None
    assert result.open_time is None


# ---------------------------------------------------------------------------
# Places search: Google vs SQLite fallback
# ---------------------------------------------------------------------------


def test_search_places_returns_normalized_results_when_google_available(monkeypatch):
    from app.config import get_settings

    monkeypatch.setattr(get_settings(), "google_places_api_key", PLACES_KEY, raising=False)

    def handler(request: httpx.Request) -> httpx.Response:
        assert request.headers["X-Goog-Api-Key"] == PLACES_KEY
        return httpx.Response(200, json=GOOGLE_PLACE_PAYLOAD)

    transport = httpx.MockTransport(handler)
    original = httpx.AsyncClient

    def patched(*args, **kwargs):
        kwargs["transport"] = transport
        return original(*args, **kwargs)

    monkeypatch.setattr(httpx, "AsyncClient", patched)

    r = client.get("/api/v1/places/search?q=cafe&lat=18.94&lng=72.82")
    assert r.status_code == 200
    body = r.json()
    assert body["source"] == "google_places"
    assert body["fallback"] is False
    assert body["count"] == 1
    item = body["items"][0]
    assert item["name"] == "Marine Drive Café"
    assert item["category"] == "food"
    assert item["distance_km"] is not None
    # The response must not contain any Google key material.
    assert PLACES_KEY not in r.text


def test_search_places_falls_back_to_sqlite_when_google_unavailable():
    r = client.get("/api/v1/places/search?q=Gateway")
    assert r.status_code == 200
    body = r.json()
    assert body["source"] == "sqlite"
    assert body["fallback"] is True
    assert body["count"] >= 1
    # Name matches outrank description matches in the fallback.
    assert body["items"][0]["name"] == "Gateway of India Sunrise"
    assert all(i["source"] == "sqlite" for i in body["items"])
    assert all(i["lat"] and i["lng"] for i in body["items"])


def test_search_places_falls_back_when_google_errors(monkeypatch):
    from app.config import get_settings

    monkeypatch.setattr(get_settings(), "google_places_api_key", PLACES_KEY, raising=False)

    def handler(request: httpx.Request) -> httpx.Response:
        return httpx.Response(500, json={"error": "backend error"})

    original = httpx.AsyncClient

    def patched(*args, **kwargs):
        kwargs["transport"] = httpx.MockTransport(handler)
        return original(*args, **kwargs)

    monkeypatch.setattr(httpx, "AsyncClient", patched)

    r = client.get("/api/v1/places/search?q=cafe")
    assert r.status_code == 200
    assert r.json()["source"] == "sqlite"
    assert r.json()["fallback"] is True


def test_nearby_places_falls_back_to_sqlite_and_sorts_by_distance():
    r = client.get("/api/v1/places/nearby?lat=19.0596&lng=72.8295&limit=5")
    assert r.status_code == 200
    body = r.json()
    assert body["source"] == "sqlite"
    distances = [i["distance_km"] for i in body["items"]]
    assert distances == sorted(distances)
    assert all(d is not None for d in distances)


def test_search_places_validation():
    assert client.get("/api/v1/places/search").status_code == 422  # q required
    assert client.get("/api/v1/places/search?q=x&lat=999").status_code == 422


# ---------------------------------------------------------------------------
# Routes
# ---------------------------------------------------------------------------


def test_compute_route_normalizes_google_response(monkeypatch):
    from app.config import get_settings

    monkeypatch.setattr(get_settings(), "google_routes_api_key", ROUTES_KEY, raising=False)

    def handler(request: httpx.Request) -> httpx.Response:
        assert request.headers["X-Goog-Api-Key"] == ROUTES_KEY
        return httpx.Response(200, json=GOOGLE_ROUTE_PAYLOAD)

    original = httpx.AsyncClient

    def patched(*args, **kwargs):
        kwargs["transport"] = httpx.MockTransport(handler)
        return original(*args, **kwargs)

    monkeypatch.setattr(httpx, "AsyncClient", patched)

    import asyncio

    route = asyncio.run(
        google_routes.compute_route(19.0596, 72.8295, 19.1075, 72.8263, travel_mode="DRIVE")
    )
    assert route is not None
    assert route.distance_m == 5340
    assert route.duration_s == 1240
    assert route.duration_min == 21
    assert route.polyline == "abc123def456"
    assert route.travel_mode == "DRIVE"
    assert route.source == "google_routes"


def test_compute_route_returns_none_without_key():
    import asyncio

    assert asyncio.run(google_routes.compute_route(19.0, 72.8, 19.1, 72.9)) is None


def test_compute_route_returns_none_on_google_error(monkeypatch):
    import asyncio

    from app.config import get_settings

    monkeypatch.setattr(get_settings(), "google_routes_api_key", ROUTES_KEY, raising=False)

    def handler(request: httpx.Request) -> httpx.Response:
        return httpx.Response(403, json={"error": {"message": "forbidden"}})

    original = httpx.AsyncClient

    def patched(*args, **kwargs):
        kwargs["transport"] = httpx.MockTransport(handler)
        return original(*args, **kwargs)

    monkeypatch.setattr(httpx, "AsyncClient", patched)

    assert asyncio.run(google_routes.compute_route(19.0, 72.8, 19.1, 72.9)) is None


def test_route_between_many_preserves_order_and_pads():
    import asyncio

    destinations = [(19.1, 72.8), (19.2, 72.9), (19.3, 73.0), (19.4, 73.1), (19.5, 73.2),
                    (19.6, 73.3), (19.7, 73.4), (19.8, 73.5), (19.9, 73.6), (20.0, 73.7),
                    (20.1, 73.8), (20.2, 73.9)]
    result = asyncio.run(
        google_routes.route_between_many(19.0, 72.8, destinations)
    )
    assert len(result) == len(destinations)  # never drops entries


# ---------------------------------------------------------------------------
# Photo proxy
# ---------------------------------------------------------------------------


def test_photo_proxy_returns_404_when_unavailable():
    r = client.get("/api/v1/images/place?name=places/ABC/photos/DEF")
    assert r.status_code == 404


def test_photo_proxy_streams_bytes_and_hides_key(monkeypatch):
    from app.config import get_settings

    monkeypatch.setattr(get_settings(), "google_places_api_key", PLACES_KEY, raising=False)

    def handler(request: httpx.Request) -> httpx.Response:
        assert PLACES_KEY in str(request.url)  # key used server-side only
        return httpx.Response(
            200, content=b"\xff\xd8\xffFAKEJPEG", headers={"content-type": "image/jpeg"}
        )

    original = httpx.AsyncClient

    def patched(*args, **kwargs):
        kwargs["transport"] = httpx.MockTransport(handler)
        return original(*args, **kwargs)

    monkeypatch.setattr(httpx, "AsyncClient", patched)

    r = client.get("/api/v1/images/place?name=places/ABC/photos/DEF")
    assert r.status_code == 200
    assert r.headers["content-type"].startswith("image/")
    assert r.content == b"\xff\xd8\xffFAKEJPEG"
    assert PLACES_KEY not in r.text


# ---------------------------------------------------------------------------
# Enriched endpoints
# ---------------------------------------------------------------------------


def test_recommend_returns_frontend_ready_fields():
    r = client.post(
        "/api/v1/recommend",
        json={
            "location": "Bandra",
            "time_hours": 4,
            "budget_inr": 1500,
            "interests": ["food", "art"],
        },
    )
    assert r.status_code == 200
    body = r.json()
    assert body["total_candidates"] >= 40
    assert body["feasible_count"] >= 1
    assert "weather" in body
    assert body["route_source"] == "local"  # no server key in tests

    item = body["recommendations"][0]
    for field in (
        "id",
        "name",
        "category",
        "image",
        "lat",
        "lng",
        "cost",
        "rating",
        "opening_hours",
        "distance_km",
        "travel_time_min",
        "why_this_fits",
        "weather",
        "route",
    ):
        assert field in item, f"missing {field}"
    assert item["why_this_fits"]
    assert item["opening_hours"]["open_time"]
    assert item["route"]["source"] == "local"
    assert item["route"]["duration_min"] == item["travel_time_min"]
    # Backwards-compatible nested experience payload.
    assert item["experience"]["name"] == item["name"]


def test_recommend_uses_google_route_when_available(monkeypatch):
    from app.config import get_settings

    monkeypatch.setattr(get_settings(), "google_routes_api_key", ROUTES_KEY, raising=False)
    monkeypatch.setattr(
        google_places, "search_places", _async_return([])
    )

    def handler(request: httpx.Request) -> httpx.Response:
        return httpx.Response(200, json=GOOGLE_ROUTE_PAYLOAD)

    original = httpx.AsyncClient

    def patched(*args, **kwargs):
        kwargs["transport"] = httpx.MockTransport(handler)
        return original(*args, **kwargs)

    monkeypatch.setattr(httpx, "AsyncClient", patched)

    r = client.post(
        "/api/v1/recommend",
        json={"location": "Bandra", "time_hours": 6, "budget_inr": 3000, "include_route": True},
    )
    assert r.status_code == 200
    body = r.json()
    assert body["route_source"] == "google_routes"
    first = body["recommendations"][0]
    assert first["route"]["source"] == "google_routes"
    assert first["route"]["polyline"] == "abc123def456"
    assert first["route"]["distance_m"] == 5340
    assert first["distance_km"] == 5.34
    assert first["travel_time_min"] == 21


def test_recommend_can_skip_route_enrichment():
    r = client.post(
        "/api/v1/recommend",
        json={"location": "Bandra", "time_hours": 4, "budget_inr": 1500, "include_route": False},
    )
    assert r.status_code == 200
    assert r.json()["route_source"] == "local"


def test_recommend_accepts_explicit_origin():
    r = client.post(
        "/api/v1/recommend",
        json={
            "time_hours": 6,
            "budget_inr": 2000,
            "origin_lat": 19.0596,
            "origin_lng": 72.8295,
            "travel_mode": "DRIVE",
        },
    )
    assert r.status_code == 200
    first = r.json()["recommendations"][0]
    assert first["distance_km"] >= 0
    assert first["route"]["travel_mode"] == "DRIVE"


def test_experience_detail_is_frontend_ready():
    r = client.get("/api/v1/experiences/1/detail?lat=19.0596&lng=72.8295")
    assert r.status_code == 200
    body = r.json()
    assert body["experience"]["id"] == 1
    assert body["distance_km"] > 0
    assert body["travel_time_min"] > 0
    assert body["total_time_min"] >= body["travel_time_min"]
    assert body["opening_hours"]["label"] in {"Open", "Closed"}
    assert "weather" in body
    # No server key configured in tests, so the offline estimate is expected.
    assert body["route"]["source"] == "local"


def test_experience_detail_404_still_works():
    assert client.get("/api/v1/experiences/999999").status_code == 404
    assert client.get("/api/v1/experiences/999999/detail").status_code == 404


def test_integrations_status_reports_fallback():
    r = client.get("/api/v1/integrations/status")
    assert r.status_code == 200
    body = r.json()
    assert body["places"]["configured"] is False
    assert body["routes"]["configured"] is False
    assert body["fallback"] == "sqlite+haversine"


def test_existing_endpoints_still_work():
    assert client.get("/api/v1/experiences").status_code == 200
    assert client.get("/api/v1/experiences/1/guides").status_code == 200
    assert client.get("/api/v1/weather").status_code == 200
    with Session(engine) as session:
        guide = session.exec(select(__import__("app.models", fromlist=["Guide"]).Guide)).first()
    assert guide is not None
    r = client.post(f"/api/v1/guides/{guide.id}/request", json={"hours": 2})
    assert r.status_code == 200
    assert r.json()["status"] == "requested"


def test_config_endpoint_never_returns_server_keys():
    r = client.get("/api/v1/config")
    assert r.status_code == 200
    body = r.json()
    assert "google_places_api_key" not in body
    assert "google_routes_api_key" not in body
    assert set(body) == {"google_maps_api_key", "maps_enabled", "open_meteo_enabled"}


def test_no_google_key_leaks_in_any_response():
    r = client.post(
        "/api/v1/recommend",
        json={"location": "Bandra", "time_hours": 4, "budget_inr": 2000},
    )
    assert "AIza" not in r.text
    assert "googleapis.com" not in r.text
    assert "google_routes_api_key" not in r.text


def test_schema_helpers_are_reusable():
    assert OpeningHoursInfo(open_time="09:00", close_time="21:00").is_open is True
    assert RouteInfo().source == "local"
    assert WeatherContext().available is False


def _async_return(value):
    async def _inner(*args, **kwargs):
        return value

    return _inner
