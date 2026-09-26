"""Tests for fast guide onboarding (documents + specialisation)."""

import uuid

from fastapi.testclient import TestClient
from sqlmodel import Session, select

from app.database import engine
from app.models import Guide, User
from app.models_prd import GuideProfile
from main import app

client = TestClient(app)

# A tiny valid-ish PNG header; the store does not inspect the bytes.
_PNG = b"\x89PNG\r\n\x1a\n" + b"0" * 64


def _register(name: str = "TS-Guide Applicant") -> str:
    email = f"guide-onb-{uuid.uuid4().hex[:10]}@localiq.test"
    r = client.post(
        "/api/v1/auth/register",
        json={"name": name, "email": email, "password": "Secret123"},
    )
    assert r.status_code == 201, r.text
    return r.json()["access_token"]


def _auth(token: str) -> dict:
    return {"Authorization": f"Bearer {token}"}


def _upload(token: str, kind: str, content: bytes = _PNG, content_type: str = "image/png"):
    return client.post(
        "/api/v1/guides/onboarding/documents",
        data={"kind": kind},
        files={"file": (f"{kind}.png", content, content_type)},
        headers=_auth(token),
    )


# ---------------------------------------------------------------------------


def test_options_are_public():
    r = client.get("/api/v1/guides/onboarding/options")
    assert r.status_code == 200, r.text
    body = r.json()
    assert body["areas"], "known areas should be offered"
    assert "street_food" in body["niches"]
    assert set(body["document_kinds"]) == {"driver_license", "guide_license"}


def test_status_before_start_is_not_started():
    token = _register()
    body = client.get("/api/v1/guides/onboarding/me", headers=_auth(token)).json()
    assert body["state"] == "not_started"
    assert body["can_submit"] is False


def test_start_requires_auth():
    assert client.post("/api/v1/guides/onboarding/start", json={}).status_code == 401


def test_start_creates_a_draft():
    token = _register("TS-Priya Guide")
    r = client.post("/api/v1/guides/onboarding/start", json={"languages": ["en", "hi"]}, headers=_auth(token))
    assert r.status_code == 200, r.text
    body = r.json()
    assert body["state"] == "signup"
    assert body["verification_status"] == "unverified"
    assert body["guide_id"]


def test_start_is_idempotent():
    token = _register()
    first = client.post("/api/v1/guides/onboarding/start", json={}, headers=_auth(token)).json()
    second = client.post("/api/v1/guides/onboarding/start", json={}, headers=_auth(token)).json()
    assert first["guide_id"] == second["guide_id"]


def test_document_upload_then_apply_flow():
    token = _register()
    client.post("/api/v1/guides/onboarding/start", json={}, headers=_auth(token))

    driver = _upload(token, "driver_license")
    assert driver.status_code == 200, driver.text
    assert driver.json()["key"].startswith("guides/")

    guide = _upload(token, "guide_license")
    assert guide.status_code == 200

    status = client.get("/api/v1/guides/onboarding/me", headers=_auth(token)).json()
    assert status["has_driver_license"] is True
    assert status["has_guide_license"] is True
    assert status["can_submit"] is True
    # Documents are exposed as metadata only — never the bytes.
    assert set(status["documents"]) == {"driver_license", "guide_license"}
    assert "key" in status["documents"]["driver_license"]

    applied = client.post(
        "/api/v1/guides/onboarding/apply",
        json={"areas": ["Bandra", "Colaba"], "niches": ["street_food"], "rate_per_hour": 1200},
        headers=_auth(token),
    )
    assert applied.status_code == 200, applied.text
    body = applied.json()
    assert body["state"] == "id_uploaded"
    assert body["verification_status"] == "pending"
    assert body["areas"] == ["Bandra", "Colaba"]
    assert body["niches"] == ["street_food"]


def test_apply_without_documents_is_rejected():
    token = _register()
    client.post("/api/v1/guides/onboarding/start", json={}, headers=_auth(token))
    r = client.post(
        "/api/v1/guides/onboarding/apply",
        json={"areas": ["Bandra"], "niches": []},
        headers=_auth(token),
    )
    assert r.status_code == 422


def test_apply_without_areas_is_rejected():
    token = _register()
    client.post("/api/v1/guides/onboarding/start", json={}, headers=_auth(token))
    _upload(token, "driver_license")
    _upload(token, "guide_license")
    r = client.post(
        "/api/v1/guides/onboarding/apply",
        json={"areas": [], "niches": ["food"]},
        headers=_auth(token),
    )
    assert r.status_code == 422


def test_upload_rejects_bad_kind_and_type():
    token = _register()
    client.post("/api/v1/guides/onboarding/start", json={}, headers=_auth(token))
    assert _upload(token, "passport").status_code == 422
    assert _upload(token, "driver_license", content_type="text/plain").status_code == 422


def test_upload_before_start_conflicts():
    token = _register()
    assert _upload(token, "driver_license").status_code == 409


def test_admin_verify_publishes_and_raises_trust():
    token = _register()
    start = client.post("/api/v1/guides/onboarding/start", json={}, headers=_auth(token)).json()
    guide_id = start["guide_id"]
    _upload(token, "driver_license")
    _upload(token, "guide_license")
    client.post(
        "/api/v1/guides/onboarding/apply",
        json={"areas": ["Bandra"], "niches": ["food"]},
        headers=_auth(token),
    )

    # Admin surface is gated by the shared key.
    no_key = client.post(f"/api/v1/admin/guides/{guide_id}/verify", json={"approve": True})
    assert no_key.status_code in (401, 503)

    from app.config import get_settings

    settings = get_settings()
    if not settings.admin_api_key:
        # Nothing more to assert without an admin key configured.
        return

    ok = client.post(
        f"/api/v1/admin/guides/{guide_id}/verify",
        json={"approve": True, "notes": "Looks good"},
        headers={"X-Admin-Key": settings.admin_api_key},
    )
    assert ok.status_code == 200, ok.text
    body = ok.json()
    assert body["verification_status"] == "verified"
    assert body["is_published"] is True

    with Session(engine) as session:
        profile = session.exec(
            select(GuideProfile).where(GuideProfile.guide_id == guide_id)
        ).first()
        user = session.get(User, profile.user_id)
        assert user.trust_tier == "standard"
        guide = session.get(Guide, guide_id)
        assert guide.verification_status == "verified"
        assert guide.areas_covered == ["Bandra"]


def test_admin_reject_keeps_unpublished():
    from app.config import get_settings

    settings = get_settings()
    if not settings.admin_api_key:
        return

    token = _register()
    start = client.post("/api/v1/guides/onboarding/start", json={}, headers=_auth(token)).json()
    guide_id = start["guide_id"]
    _upload(token, "driver_license")
    _upload(token, "guide_license")
    client.post(
        "/api/v1/guides/onboarding/apply",
        json={"areas": ["Juhu"], "niches": ["nature"]},
        headers=_auth(token),
    )
    r = client.post(
        f"/api/v1/admin/guides/{guide_id}/verify",
        json={"approve": False, "notes": "Document unclear"},
        headers={"X-Admin-Key": settings.admin_api_key},
    )
    assert r.status_code == 200
    assert r.json()["verification_status"] == "rejected"
    assert r.json()["is_published"] is False
