"""Account deletion, the signing-key guard, and honest guide-request statuses."""

import uuid

import pytest
from fastapi.testclient import TestClient
from pydantic import ValidationError
from sqlmodel import Session, select

from app.config import DEFAULT_AUTH_SECRET_KEY, Settings
from app.database import engine
from app.models import Favorite, Guide, GuideRequest, User
from main import app

client = TestClient(app)


def _register() -> tuple[dict, str]:
    email = f"lifecycle-{uuid.uuid4().hex[:10]}@localiq.test"
    r = client.post(
        "/api/v1/auth/register",
        json={"name": "Lifecycle Tester", "email": email, "password": "Secret123"},
    )
    assert r.status_code == 201, r.text
    return r.json(), email


# ---------------------------------------------------------------------------
# Signing-key guard
# ---------------------------------------------------------------------------


def test_production_refuses_the_default_signing_key():
    """Shipping the dev key would make every session token forgeable."""
    with pytest.raises(ValidationError):
        Settings(app_env="production", auth_secret_key=DEFAULT_AUTH_SECRET_KEY)


def test_staging_refuses_the_default_signing_key():
    with pytest.raises(ValidationError):
        Settings(app_env="staging", auth_secret_key=DEFAULT_AUTH_SECRET_KEY)


def test_production_accepts_a_generated_signing_key():
    settings = Settings(app_env="production", auth_secret_key="a" * 64)
    assert settings.auth_secret_key == "a" * 64


def test_development_allows_the_default_signing_key():
    """Local dev and the suite must keep working with no setup."""
    settings = Settings(app_env="development", auth_secret_key=DEFAULT_AUTH_SECRET_KEY)
    assert settings.app_env == "development"


# ---------------------------------------------------------------------------
# Account deletion
# ---------------------------------------------------------------------------


def test_delete_account_erases_the_user_and_its_rows():
    registered, email = _register()
    headers = {"Authorization": f"Bearer {registered['access_token']}"}
    user_id = registered["user"]["id"]

    # Give the account some owned data across two tables.
    with Session(engine) as session:
        guide_id = session.exec(select(Guide)).first().id  # type: ignore[union-attr]
        session.add(
            GuideRequest(
                user_id=user_id,
                guide_id=guide_id,
                booking_ref=f"LQ-{uuid.uuid4().hex[:6]}",
            )
        )
        session.add(Favorite(user_id=user_id, experience_id=1))
        session.commit()

    r = client.delete("/api/v1/auth/me", headers=headers)
    assert r.status_code == 204, r.text

    with Session(engine) as session:
        assert session.get(User, user_id) is None
        assert session.exec(select(Favorite).where(Favorite.user_id == user_id)).all() == []
        assert (
            session.exec(select(GuideRequest).where(GuideRequest.user_id == user_id)).all() == []
        )

    # The token is dead and the credentials are gone.
    assert client.get("/api/v1/auth/me", headers=headers).status_code == 401
    relogin = client.post(
        "/api/v1/auth/login", json={"email": email, "password": "Secret123"}
    )
    assert relogin.status_code == 401


def test_delete_account_requires_authentication():
    assert client.delete("/api/v1/auth/me").status_code == 401


def test_delete_account_is_not_idempotent_for_a_revoked_token():
    registered, _ = _register()
    headers = {"Authorization": f"Bearer {registered['access_token']}"}
    assert client.delete("/api/v1/auth/me", headers=headers).status_code == 204
    # The second call has no valid session any more.
    assert client.delete("/api/v1/auth/me", headers=headers).status_code == 401


# ---------------------------------------------------------------------------
# Guide requests report their stored status
# ---------------------------------------------------------------------------


def test_guide_request_reports_the_stored_status():
    registered, _ = _register()
    headers = {"Authorization": f"Bearer {registered['access_token']}"}
    with Session(engine) as session:
        guide_id = session.exec(select(Guide)).first().id  # type: ignore[union-attr]

    created = client.post(
        f"/api/v1/guides/{guide_id}/request", json={"hours": 2}, headers=headers
    )
    assert created.status_code == 200, created.text
    body = created.json()
    assert body["status"] == "requested"
    # No more false "confirmed" claims in the message.
    assert "confirmed" not in body["message"].lower()

    mine = client.get("/api/v1/guides/me/requests", headers=headers)
    assert mine.status_code == 200
    assert [row["status"] for row in mine.json()] == ["requested"]
