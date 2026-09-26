"""Phase 5 API-completeness tests: itineraries, favorites, nearby,
admin content, feedback."""

import uuid

from fastapi.testclient import TestClient
from sqlmodel import Session, delete

from app.config import get_settings
from app.database import engine
from app.models import RecommendationFeedback
from main import app

client = TestClient(app)


def _auth_headers() -> dict:
    email = f"p5-{uuid.uuid4().hex[:10]}@localiq.test"
    response = client.post(
        "/api/v1/auth/register",
        json={"name": "P5 User", "email": email, "password": "Strong123"},
    )
    assert response.status_code == 201, response.text
    return {"Authorization": f"Bearer {response.json()['access_token']}"}


def _experience_ids(limit: int = 3) -> list[int]:
    response = client.get(f"/api/v1/experiences?limit={limit}")
    assert response.status_code == 200
    return [item["id"] for item in response.json()["items"]]


# ---------------------------------------------------------------------------
# 5.1 Itineraries
# ---------------------------------------------------------------------------


def test_itinerary_crud_flow():
    headers = _auth_headers()
    ids = _experience_ids(3)

    created = client.post(
        "/api/v1/itineraries",
        json={"name": "P5 Day", "stops": [{"experience_id": i} for i in ids]},
        headers=headers,
    )
    assert created.status_code == 201, created.text
    body = created.json()
    assert body["name"] == "P5 Day"
    assert len(body["stops"]) == 3
    assert body["total_cost"] > 0
    assert body["total_duration_min"] > 0
    assert body["stops"][1]["travel_time_min"] >= 10, "travel time between stops"
    itinerary_id = body["id"]

    listed = client.get("/api/v1/itineraries", headers=headers)
    assert listed.status_code == 200
    assert any(it["id"] == itinerary_id for it in listed.json())

    assert client.get(f"/api/v1/itineraries/{itinerary_id}", headers=headers).status_code == 200

    updated = client.put(
        f"/api/v1/itineraries/{itinerary_id}",
        json={"name": "Short", "stops": [{"experience_id": ids[0]}]},
        headers=headers,
    )
    assert updated.status_code == 200
    assert updated.json()["name"] == "Short"
    assert len(updated.json()["stops"]) == 1

    assert client.delete(f"/api/v1/itineraries/{itinerary_id}", headers=headers).status_code == 204
    assert client.get(f"/api/v1/itineraries/{itinerary_id}", headers=headers).status_code == 404


def test_itinerary_requires_auth():
    assert client.get("/api/v1/itineraries").status_code == 401
    assert client.post("/api/v1/itineraries", json={"stops": []}).status_code == 401


def test_itinerary_unknown_experience_rejected():
    headers = _auth_headers()
    response = client.post(
        "/api/v1/itineraries", json={"stops": [{"experience_id": 999999}]}, headers=headers
    )
    assert response.status_code == 400


def test_itinerary_ownership_isolation():
    owner = _auth_headers()
    other = _auth_headers()
    ids = _experience_ids(1)
    created = client.post(
        "/api/v1/itineraries", json={"stops": [{"experience_id": ids[0]}]}, headers=owner
    ).json()
    assert client.get(f"/api/v1/itineraries/{created['id']}", headers=other).status_code == 404
    assert client.delete(f"/api/v1/itineraries/{created['id']}", headers=other).status_code == 404


# ---------------------------------------------------------------------------
# 5.2 Favorites
# ---------------------------------------------------------------------------


def test_favorites_flow():
    headers = _auth_headers()
    ids = _experience_ids(2)

    assert client.post(f"/api/v1/me/favorites/{ids[0]}", headers=headers).status_code == 201
    # Idempotent: a second save must not error or duplicate.
    assert client.post(f"/api/v1/me/favorites/{ids[0]}", headers=headers).status_code == 201

    listed = client.get("/api/v1/me/favorites", headers=headers)
    assert listed.status_code == 200
    assert [item["id"] for item in listed.json()] == [ids[0]]

    assert client.delete(f"/api/v1/me/favorites/{ids[0]}", headers=headers).status_code == 204
    assert client.get("/api/v1/me/favorites", headers=headers).json() == []


def test_favorites_require_auth():
    assert client.get("/api/v1/me/favorites").status_code == 401


def test_favorite_unknown_experience():
    headers = _auth_headers()
    assert client.post("/api/v1/me/favorites/999999", headers=headers).status_code == 404


# ---------------------------------------------------------------------------
# 5.4 Geospatial
# ---------------------------------------------------------------------------


def test_nearby_sorted_within_radius():
    response = client.get("/api/v1/experiences/nearby?lat=18.9067&lng=72.8147&radius_km=5")
    assert response.status_code == 200
    data = response.json()
    assert data["radius_km"] == 5.0
    distances = [item["distance_km"] for item in data["items"]]
    assert distances == sorted(distances)
    assert all(d <= 5.0 for d in distances)


def test_nearby_validates_coordinates():
    assert client.get("/api/v1/experiences/nearby?lat=999&lng=0").status_code == 422


# ---------------------------------------------------------------------------
# 5.3 Admin content
# ---------------------------------------------------------------------------


def _patch_admin_key(monkeypatch, key: str) -> None:
    from app.api.v1 import admin

    base = get_settings()
    monkeypatch.setattr(
        admin, "get_settings", lambda: base.model_copy(update={"admin_api_key": key})
    )


def test_admin_disabled_without_key(monkeypatch):
    _patch_admin_key(monkeypatch, "")
    response = client.post(
        "/api/v1/admin/experiences",
        json={"name": "X", "category": "food", "lat": 19.0, "lng": 72.8},
    )
    assert response.status_code == 503


def test_admin_crud_with_key(monkeypatch):
    _patch_admin_key(monkeypatch, "secret-admin")
    headers = {"X-Admin-Key": "secret-admin"}

    created = client.post(
        "/api/v1/admin/experiences",
        json={"name": "P5 Test Venue", "category": "food", "lat": 19.0, "lng": 72.8, "avg_cost": 100},
        headers=headers,
    )
    assert created.status_code == 201, created.text
    experience_id = created.json()["id"]

    updated = client.patch(
        f"/api/v1/admin/experiences/{experience_id}", json={"avg_cost": 250}, headers=headers
    )
    assert updated.status_code == 200
    assert updated.json()["avg_cost"] == 250

    wrong = client.patch(
        f"/api/v1/admin/experiences/{experience_id}",
        json={"avg_cost": 1},
        headers={"X-Admin-Key": "nope"},
    )
    assert wrong.status_code == 401

    assert client.delete(f"/api/v1/admin/experiences/{experience_id}", headers=headers).status_code == 204
    assert client.get(f"/api/v1/experiences/{experience_id}").status_code == 404


# ---------------------------------------------------------------------------
# 5.5 Feedback loop
# ---------------------------------------------------------------------------


def test_feedback_recorded_and_scores_computed():
    from app.api.v1 import recommendations

    experience_id = _experience_ids(1)[0]
    recommendations.clear_recommend_cache()

    for _ in range(3):
        response = client.post(
            f"/api/v1/recommendations/{experience_id}/feedback",
            json={"helpful": False, "location": "Bandra", "interests": ["food"]},
        )
        assert response.status_code == 200
    assert response.json()["helpful"] is False

    # Recording feedback invalidates cached recommendations.
    assert recommendations.recommend_cache_stats()["size"] == 0

    with Session(engine) as session:
        scores = recommendations._feedback_scores(session)
    assert scores.get(experience_id, 0.0) < 0

    # Clean up so repeated runs don't skew ranking.
    with Session(engine) as session:
        session.exec(delete(RecommendationFeedback).where(RecommendationFeedback.experience_id == experience_id))
        session.commit()


def test_feedback_unknown_experience():
    response = client.post("/api/v1/recommendations/999999/feedback", json={"helpful": True})
    assert response.status_code == 404
