"""Tests for self-hosted object storage and Google Places photo enrichment."""

import uuid

from fastapi.testclient import TestClient
from sqlmodel import Session

from app.database import engine
from app.models import Experience
from main import app

client = TestClient(app)


def _ts_experience(name: str | None = None) -> Experience:
    """Create a throwaway experience (cleaned up by the conftest fixture)."""
    with Session(engine) as session:
        exp = Experience(
            name=name or f"TS-Photo {uuid.uuid4().hex[:8]}",
            category="culture",
            lat=19.0760,
            lng=72.8777,
        )
        session.add(exp)
        session.commit()
        session.refresh(exp)
        return exp


# ---------------------------------------------------------------------------
# Storage service
# ---------------------------------------------------------------------------


def test_storage_filesystem_roundtrip():
    from app.services import storage

    key = f"tests/{uuid.uuid4().hex}.txt"
    storage.upload_bytes(key, b"hello localiq", "text/plain")
    assert storage.object_exists(key)
    fetched = storage.get_object(key)
    assert fetched is not None
    data, content_type = fetched
    assert data == b"hello localiq"
    assert content_type == "text/plain"
    storage.delete_object(key)
    assert not storage.object_exists(key)


def test_public_url_without_cdn_base():
    from app.services import storage

    assert storage.public_url("experiences/1/x.jpg") == "/media/experiences/1/x.jpg"
    assert storage.public_url("") == ""


def test_media_endpoint_serves_and_404s():
    from app.services import storage

    key = f"tests/{uuid.uuid4().hex}.png"
    storage.upload_bytes(key, b"\x89PNGdata", "image/png")

    ok = client.get(f"/media/{key}")
    assert ok.status_code == 200
    assert ok.content == b"\x89PNGdata"
    assert ok.headers["content-type"].startswith("image/png")

    assert client.get("/media/does/not/exist.png").status_code == 404


def test_storage_status_endpoint():
    r = client.get("/storage/status")
    assert r.status_code == 200
    assert "backend" in r.json()


# ---------------------------------------------------------------------------
# Experience image resolution
# ---------------------------------------------------------------------------


def test_experience_response_derives_url_from_image_key():
    from app.schemas import ExperienceResponse

    keyed = _ts_experience()
    with Session(engine) as session:
        row = session.get(Experience, keyed.id)
        row.image_key = "experiences/9/abc.jpg"
        session.add(row)
        session.commit()
        session.refresh(row)
        assert ExperienceResponse.model_validate(row).image_url == "/media/experiences/9/abc.jpg"

    # A curated image_url still wins when no key is set.
    curated = _ts_experience()
    with Session(engine) as session:
        row = session.get(Experience, curated.id)
        row.image_url = "/static/images/x.jpg"
        session.add(row)
        session.commit()
        session.refresh(row)
        assert ExperienceResponse.model_validate(row).image_url == "/static/images/x.jpg"


# ---------------------------------------------------------------------------
# Photo enrichment
# ---------------------------------------------------------------------------


def test_enrichment_noop_without_places_key(monkeypatch):
    from app.services import google_places, photo_enrichment

    monkeypatch.setattr(google_places, "is_configured", lambda: False)
    exp = _ts_experience()
    with Session(engine) as session:
        row = session.get(Experience, exp.id)
        assert asyncio_run(photo_enrichment.enrich_experience_photo(session, row)) is False
        assert row.image_key is None


def test_enrichment_stores_photo(monkeypatch):
    from app.services import google_places, photo_enrichment

    exp = _ts_experience()
    fake_place = google_places.PlacesResult(
        name=exp.name,
        lat=exp.lat,
        lng=exp.lng,
        photo_name="places/abc/photos/def",
    )

    async def fake_search(*args, **kwargs):
        return [fake_place]

    async def fake_photo(photo_name, max_width_px=800):
        return b"\xff\xd8\xffJPEGBYTES", "image/jpeg"

    monkeypatch.setattr(google_places, "is_configured", lambda: True)
    monkeypatch.setattr(google_places, "search_places", fake_search)
    monkeypatch.setattr(google_places, "fetch_photo", fake_photo)

    with Session(engine) as session:
        row = session.get(Experience, exp.id)
        stored = asyncio_run(photo_enrichment.enrich_experience_photo(session, row))
        assert stored is True
        assert row.image_key
        assert row.image_key.startswith("experiences/")

    # The bytes are retrievable through the media proxy.
    with Session(engine) as session:
        row = session.get(Experience, exp.id)
        media = client.get(f"/media/{row.image_key}")
        assert media.status_code == 200
        assert media.content == b"\xff\xd8\xffJPEGBYTES"


def test_enrichment_rejects_far_away_match(monkeypatch):
    from app.services import google_places, photo_enrichment

    exp = _ts_experience()
    # ~ Delhi coordinates: far outside the 1.5 km match radius.
    far = google_places.PlacesResult(
        name=exp.name, lat=28.61, lng=77.20, photo_name="places/x/photos/y"
    )

    async def fake_search(*args, **kwargs):
        return [far]

    monkeypatch.setattr(google_places, "is_configured", lambda: True)
    monkeypatch.setattr(google_places, "search_places", fake_search)

    with Session(engine) as session:
        row = session.get(Experience, exp.id)
        assert asyncio_run(photo_enrichment.enrich_experience_photo(session, row)) is False
        assert row.image_key is None


def asyncio_run(coro):
    import asyncio

    return asyncio.run(coro)
