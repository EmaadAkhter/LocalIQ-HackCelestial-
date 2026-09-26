"""Tests for the driver trip map: pickup, ordered stops, drop-off, route."""

import asyncio
import uuid

from fastapi.testclient import TestClient
from sqlmodel import Session, select

from app.database import engine
from app.models import (
    Guide,
    GuidePackage,
    GuidePackageStop,
    PackageBooking,
    User,
)
from app.models_prd import GuideProfile
from app.services import driver_trips
from app.services.auth import hash_password
from main import app

client = TestClient(app)

MUMBAI = (19.0596, 72.8295)
BANDRA = (19.0596, 72.8295)
JUHU = (19.1075, 72.8263)


def _auth(token: str) -> dict:
    return {"Authorization": f"Bearer {token}"}


def _register(name: str, email_prefix: str) -> tuple[int, str]:
    email = f"{email_prefix}-{uuid.uuid4().hex[:10]}@localiq.test"
    r = client.post(
        "/api/v1/auth/register",
        json={"name": name, "email": email, "password": "Secret123"},
    )
    assert r.status_code == 201, r.text
    body = r.json()
    return body["user"]["id"], body["access_token"]


def _make_trip(*, guest_user_id: int | None = None) -> tuple[int, int, int]:
    """Insert guide + profile + package + stop + confirmed booking.

    Returns ``(booking_id, guide_id, package_id)``.
    """
    with Session(engine) as session:
        guide = Guide(
            name="TS-Driver Guide",
            specialty="heritage",
            languages=["en"],
            rate_per_hour=1000,
        )
        session.add(guide)
        session.commit()
        session.refresh(guide)

        # A user owns the guide (the "driver").
        driver = User(
            name="TS-Driver Account",
            email=f"driver-{uuid.uuid4().hex[:10]}@localiq.test",
            password_hash=hash_password("Secret123"),
            trust_tier="standard",
            provider="email",
        )
        session.add(driver)
        session.commit()
        session.refresh(driver)

        session.add(
            GuideProfile(
                guide_id=guide.id,
                user_id=driver.id,
                onboarding_state="verified",
                verification_status="verified",
                verification_tier="standard",
                is_published=True,
            )
        )
        session.commit()

        package = GuidePackage(
            guide_id=guide.id,
            title="TS South Mumbai Walk",
            pickup_lat=BANDRA[0],
            pickup_lng=BANDRA[1],
            default_pickup_area="Bandra",
            total_duration_hours=3,
            price_per_person=800,
        )
        session.add(package)
        session.commit()
        session.refresh(package)

        session.add(
            GuidePackageStop(
                package_id=package.id,
                sequence=1,
                segment_type="experience",
                location_name="TS Gateway of India",
                lat=BANDRA[0] + 0.01,
                lng=BANDRA[1] + 0.01,
                duration_min=45,
            )
        )
        session.commit()

        booking = PackageBooking(
            booking_ref=f"D{uuid.uuid4().hex[:6].upper()}",
            guide_id=guide.id,
            package_id=package.id,
            user_id=guest_user_id,
            pickup_address="Bandra Station",
            pickup_lat=JUHU[0],
            pickup_lng=JUHU[1],
            date="2026-09-27",
            start_time="10:00",
            hours=3,
            group_size=2,
            status="confirmed",
            guest_name="TS Guest",
        )
        session.add(booking)
        session.commit()
        session.refresh(booking)
        return booking.id, guide.id, package.id


def _driver_token(guide_id: int) -> str:
    """Sign in as the guide owner (login, so we get a real token)."""
    with Session(engine) as session:
        profile = session.exec(
            select(GuideProfile).where(GuideProfile.guide_id == guide_id)
        ).first()
        user = session.get(User, profile.user_id)
    r = client.post(
        "/api/v1/auth/login",
        json={"email": user.email, "password": "Secret123"},
    )
    assert r.status_code == 200, r.text
    return r.json()["access_token"]


# ---------------------------------------------------------------------------
# Geometry helpers
# ---------------------------------------------------------------------------


def test_decode_polyline_known_value():
    # Google's canonical example decodes to these three points.
    decoded = driver_trips.decode_polyline("_p~iF~ps|U_ulLnnqC_mqNvxq`@")
    assert len(decoded) == 3
    assert abs(decoded[0][0] - 38.5) < 0.001 and abs(decoded[0][1] - (-120.2)) < 0.001
    assert abs(decoded[1][0] - 40.7) < 0.001 and abs(decoded[1][1] - (-120.95)) < 0.001
    assert abs(decoded[2][0] - 43.252) < 0.001 and abs(decoded[2][1] - (-126.453)) < 0.001


def test_synthesise_path_is_deterministic_and_dense():
    points = [BANDRA, JUHU]
    first = driver_trips.synthesise_path(points)
    second = driver_trips.synthesise_path(points)
    assert first == second
    assert len(first) > len(points)
    assert first[0] == points[0]
    assert first[-1] == points[-1]


def test_build_route_offline_returns_geometry(monkeypatch):
    monkeypatch.setattr(driver_trips.google_routes, "is_configured", lambda: False)
    route = asyncio.run(driver_trips.build_route([BANDRA, JUHU]))
    assert route["source"] == "local"
    assert len(route["path"]) > 2
    assert route["distance_km"] > 0
    assert route["duration_min"] >= 1


def test_decoding_empty_polyline_is_safe():
    assert driver_trips.decode_polyline("") == []


# ---------------------------------------------------------------------------
# Endpoints
# ---------------------------------------------------------------------------


def test_driver_trips_requires_a_guide():
    _, token = _register("TS-Non Guide", "nonguide")
    r = client.get("/api/v1/driver/trips", headers=_auth(token))
    assert r.status_code == 403
    assert "not_a_guide" in r.text


def test_driver_trips_requires_auth():
    assert client.get("/api/v1/driver/trips").status_code == 401


def test_driver_trip_detail_shape():
    booking_id, guide_id, package_id = _make_trip()
    token = _driver_token(guide_id)

    listing = client.get("/api/v1/driver/trips", headers=_auth(token))
    assert listing.status_code == 200, listing.text
    rows = listing.json()
    assert any(row["id"] == booking_id for row in rows)
    row = next(r for r in rows if r["id"] == booking_id)
    assert row["pickup"]["lat"] == JUHU[0]
    assert row["package_title"] == "TS South Mumbai Walk"

    detail = client.get(f"/api/v1/driver/trips/{booking_id}", headers=_auth(token))
    assert detail.status_code == 200, detail.text
    body = detail.json()
    assert body["pickup"]["address"] == "Bandra Station"
    assert body["drop"] is not None
    assert len(body["stops"]) == 1
    assert body["stops"][0]["name"] == "TS Gateway of India"
    assert len(body["route"]) > 3
    assert body["distance_km"] > 0
    assert body["route_source"] in {"local", "google_routes"}
    assert "in_progress" in body["allowed_transitions"]


def test_driver_cannot_read_another_guides_trip():
    booking_id, guide_id, _ = _make_trip()
    _, other_guide_id, _ = _make_trip()
    other_token = _driver_token(other_guide_id)
    r = client.get(f"/api/v1/driver/trips/{booking_id}", headers=_auth(other_token))
    assert r.status_code == 404


def test_trip_status_state_machine():
    booking_id, guide_id, _ = _make_trip()
    token = _driver_token(guide_id)

    # confirmed -> completed is not allowed.
    bad = client.post(
        f"/api/v1/driver/trips/{booking_id}/status",
        json={"status": "completed"},
        headers=_auth(token),
    )
    assert bad.status_code == 409

    started = client.post(
        f"/api/v1/driver/trips/{booking_id}/status",
        json={"status": "in_progress"},
        headers=_auth(token),
    )
    assert started.status_code == 200, started.text
    assert started.json()["status"] == "in_progress"

    done = client.post(
        f"/api/v1/driver/trips/{booking_id}/status",
        json={"status": "completed"},
        headers=_auth(token),
    )
    assert done.status_code == 200
    assert done.json()["status"] == "completed"
    assert done.json()["allowed_transitions"] == []


def test_driver_location_updates_and_remaining():
    booking_id, guide_id, _ = _make_trip()
    token = _driver_token(guide_id)

    r = client.post(
        f"/api/v1/driver/trips/{booking_id}/location",
        json={"lat": 19.05, "lng": 72.83},
        headers=_auth(token),
    )
    assert r.status_code == 200, r.text
    body = r.json()
    assert body["driver_location"]["lat"] == 19.05
    # Drop defaults to the pickup (Juhu), so there is distance still to cover.
    assert body["remaining"]["distance_km"] > 0
    assert body["remaining"]["duration_min"] >= 1


def test_guest_can_track_their_own_trip():
    guest_id, token = _register("TS-Guest", "guest")
    booking_id, _, _ = _make_trip(guest_user_id=guest_id)

    r = client.get(f"/api/v1/bookings/{booking_id}/tracking", headers=_auth(token))
    assert r.status_code == 200, r.text
    assert r.json()["id"] == booking_id


def test_stranger_cannot_track_a_trip():
    guest_id, _ = _register("TS-Guest", "guest")
    booking_id, _, _ = _make_trip(guest_user_id=guest_id)
    _, stranger_token = _register("TS-Stranger", "stranger")

    r = client.get(
        f"/api/v1/bookings/{booking_id}/tracking", headers=_auth(stranger_token)
    )
    assert r.status_code == 403


def test_tracking_unknown_trip_404s():
    r = client.get("/api/v1/bookings/999999/tracking")
    assert r.status_code == 404
