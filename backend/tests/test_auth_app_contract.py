"""Tests for the app-facing auth contract (refresh/guest/google + user shape).

The Flutter client parses a flat payload: ``accessToken``/``refreshToken`` /
``expiresIn`` and a ``user`` with ``displayName``, ``provider``, ``tier``,
``homeCity``, ``isAnonymous``. ``json_map_x.pick`` accepts snake_case too, so we
assert on the snake_case keys the backend ships.
"""

import base64
import json
import uuid

from fastapi.testclient import TestClient

from main import app

client = TestClient(app)


def _register() -> dict:
    email = f"auth-{uuid.uuid4().hex[:10]}@localiq.test"
    r = client.post(
        "/api/v1/auth/register",
        json={"name": "Auth Tester", "email": email, "password": "Secret123"},
    )
    assert r.status_code == 201, r.text
    return r.json()


def _fake_google_jwt(email: str, name: str = "Google User", sub: str = "g-123") -> str:
    def b64(obj: dict) -> str:
        raw = json.dumps(obj).encode()
        return base64.urlsafe_b64encode(raw).rstrip(b"=").decode()

    return f"{b64({'alg': 'none', 'typ': 'JWT'})}.{b64({'sub': sub, 'email': email, 'name': name})}.sig"


# ---------------------------------------------------------------------------
# Token + user shape
# ---------------------------------------------------------------------------


def test_register_returns_app_token_shape():
    body = _register()
    assert body["access_token"]
    assert body["refresh_token"]
    assert isinstance(body["expires_in"], int) and body["expires_in"] > 0

    user = body["user"]
    assert user["display_name"] == "Auth Tester"
    assert user["provider"] == "email"
    assert user["tier"] == "free"
    assert user["home_city"] == "Mumbai"
    assert user["is_anonymous"] is False
    assert user["created_at"]


def test_login_returns_fresh_tokens():
    body = _register()
    login = client.post(
        "/api/v1/auth/login",
        json={"email": body["user"]["email"], "password": "Secret123"},
    )
    assert login.status_code == 200, login.text
    payload = login.json()
    assert payload["refresh_token"]
    assert payload["refresh_token"] != body["refresh_token"]


def test_me_uses_the_access_token():
    body = _register()
    r = client.get(
        "/api/v1/auth/me",
        headers={"Authorization": f"Bearer {body['access_token']}"},
    )
    assert r.status_code == 200
    assert r.json()["display_name"] == "Auth Tester"


# ---------------------------------------------------------------------------
# Refresh
# ---------------------------------------------------------------------------


def test_refresh_rotates_and_invalidates_the_old_token():
    body = _register()
    first_refresh = body["refresh_token"]

    rotated = client.post("/api/v1/auth/refresh", json={"refresh_token": first_refresh})
    assert rotated.status_code == 200, rotated.text
    new_tokens = rotated.json()
    assert new_tokens["access_token"] and new_tokens["refresh_token"]
    assert new_tokens["refresh_token"] != first_refresh

    # The old refresh token has been rotated away.
    reuse = client.post("/api/v1/auth/refresh", json={"refresh_token": first_refresh})
    assert reuse.status_code == 401

    # The new access token works.
    me = client.get(
        "/api/v1/auth/me",
        headers={"Authorization": f"Bearer {new_tokens['access_token']}"},
    )
    assert me.status_code == 200


def test_refresh_rejects_garbage():
    r = client.post("/api/v1/auth/refresh", json={"refresh_token": "not-a-real-token"})
    assert r.status_code == 401


# ---------------------------------------------------------------------------
# Guest
# ---------------------------------------------------------------------------


def test_guest_creates_anonymous_account():
    r = client.post("/api/v1/auth/guest")
    assert r.status_code == 200, r.text
    body = r.json()
    assert body["user"]["is_anonymous"] is True
    assert body["user"]["tier"] == "guest"
    assert body["user"]["provider"] == "guest"

    me = client.get(
        "/api/v1/auth/me", headers={"Authorization": f"Bearer {body['access_token']}"}
    )
    assert me.status_code == 200
    assert me.json()["is_anonymous"] is True


def test_two_guests_are_distinct_accounts():
    first = client.post("/api/v1/auth/guest").json()
    second = client.post("/api/v1/auth/guest").json()
    assert first["user"]["id"] != second["user"]["id"]


# ---------------------------------------------------------------------------
# Password reset
# ---------------------------------------------------------------------------


def test_forgot_password_does_not_enumerate_accounts():
    unknown = client.post(
        "/api/v1/auth/forgot-password", json={"email": f"nobody-{uuid.uuid4().hex}@localiq.test"}
    )
    assert unknown.status_code == 200
    assert unknown.json()["status"] == "sent"
    assert "dev_reset_token" not in unknown.json()


def test_forgot_password_then_reset_flow():
    body = _register()
    email = body["user"]["email"]

    requested = client.post("/api/v1/auth/forgot-password", json={"email": email})
    assert requested.status_code == 200
    token = requested.json().get("dev_reset_token")
    assert token, "non-production should expose a dev reset token"

    reset = client.post(
        "/api/v1/auth/reset-password", json={"token": token, "password": "NewSecret456"}
    )
    assert reset.status_code == 200, reset.text

    # Old password fails, new password works.
    assert (
        client.post(
            "/api/v1/auth/login", json={"email": email, "password": "Secret123"}
        ).status_code
        == 401
    )
    assert (
        client.post(
            "/api/v1/auth/login", json={"email": email, "password": "NewSecret456"}
        ).status_code
        == 200
    )


def test_reset_rejects_bad_token():
    r = client.post(
        "/api/v1/auth/reset-password", json={"token": "nope", "password": "NewSecret456"}
    )
    assert r.status_code == 400


# ---------------------------------------------------------------------------
# Google
# ---------------------------------------------------------------------------


def test_google_dev_fallback_creates_account():
    email = f"google-{uuid.uuid4().hex[:10]}@localiq.test"
    r = client.post(
        "/api/v1/auth/google", json={"id_token": _fake_google_jwt(email)}
    )
    assert r.status_code == 200, r.text
    body = r.json()
    assert body["user"]["email"] == email
    assert body["user"]["provider"] == "google"
    assert body["refresh_token"]

    # Signing in again reuses the same account.
    again = client.post("/api/v1/auth/google", json={"id_token": _fake_google_jwt(email)})
    assert again.json()["user"]["id"] == body["user"]["id"]
