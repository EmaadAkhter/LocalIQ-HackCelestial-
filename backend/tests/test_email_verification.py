"""Email verification (Resend) + the reset-email hand-off.

Sending is always stubbed: the suite must never touch a real mail provider.
`conftest` also clears ``RESEND_API_KEY`` so a developer's key cannot leak in.
"""

import uuid
from datetime import timedelta

from fastapi.testclient import TestClient
from sqlmodel import Session, select

from app.database import engine
from app.models import EmailVerificationToken, User
from app.services import email as email_service
from app.services import verification
from app.services.auth import utcnow
from main import app

client = TestClient(app)


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------


def _register(name: str = "Email Tester") -> tuple[dict, str]:
    email = f"verify-{uuid.uuid4().hex[:10]}@localiq.test"
    r = client.post(
        "/api/v1/auth/register",
        json={"name": name, "email": email, "password": "Secret123"},
    )
    assert r.status_code == 201, r.text
    return r.json(), email


def _capture_verification(monkeypatch) -> list[dict]:
    """Record verification emails instead of sending them."""
    sent: list[dict] = []

    def fake_send(*, to: str, name: str | None, token: str) -> bool:
        sent.append({"to": to, "name": name, "token": token})
        return True

    monkeypatch.setattr(
        "app.api.v1.auth.email_service.send_verification_email", fake_send
    )
    return sent


def _capture_reset(monkeypatch) -> list[dict]:
    sent: list[dict] = []

    def fake_send(*, to: str, name: str | None, token: str) -> bool:
        sent.append({"to": to, "name": name, "token": token})
        return True

    monkeypatch.setattr(
        "app.api.v1.auth.email_service.send_password_reset_email", fake_send
    )
    return sent


class _FakeResponse:
    status_code = 200

    def raise_for_status(self) -> None:  # noqa: D102
        return None


class _FakeClient:
    """Stands in for httpx.Client, capturing the Resend request."""

    captured: dict = {}

    def __init__(self, **_kwargs) -> None:  # noqa: D107
        pass

    def __enter__(self) -> "_FakeClient":
        return self

    def __exit__(self, *_exc) -> bool:
        return False

    def post(self, url, json=None, headers=None):  # noqa: A002 - httpx signature
        _FakeClient.captured = {"url": url, "json": json, "headers": headers}
        return _FakeResponse()


class _StubSettings:
    resend_api_key = "re_test_key"
    resend_from = "LocalIQ <onboarding@resend.dev>"
    app_public_origin = "https://localiq.tavesglobal.com"
    email_verification_ttl_hours = 48


# ---------------------------------------------------------------------------
# Email transport (the Resend REST contract)
# ---------------------------------------------------------------------------


def test_email_is_a_noop_without_an_api_key(monkeypatch):
    class _NoKey:
        resend_api_key = ""
        resend_from = "LocalIQ <onboarding@resend.dev>"
        app_public_origin = "http://localhost:8080"

    monkeypatch.setattr(email_service, "get_settings", lambda: _NoKey())
    called = {"posted": False}

    def _explode(**_kwargs):
        called["posted"] = True
        raise AssertionError("must not call Resend without a key")

    monkeypatch.setattr(email_service.httpx, "Client", _explode)
    assert email_service.send_email(to="a@b.test", subject="s", text="t") is False
    assert called["posted"] is False


def test_email_posts_the_resend_payload(monkeypatch):
    monkeypatch.setattr(email_service, "get_settings", lambda: _StubSettings())
    monkeypatch.setattr(email_service.httpx, "Client", _FakeClient)

    ok = email_service.send_email(
        to="guest@localiq.test", subject="Hello", text="Body", reply_to="team@localiq.test"
    )
    assert ok is True

    captured = _FakeClient.captured
    assert captured["url"] == "https://api.resend.com/emails"
    assert captured["headers"]["Authorization"] == "Bearer re_test_key"
    body = captured["json"]
    assert body["from"] == "LocalIQ <onboarding@resend.dev>"
    assert body["to"] == ["guest@localiq.test"]
    assert body["subject"] == "Hello"
    assert body["text"] == "Body"
    assert body["reply_to"] == "team@localiq.test"


def test_verification_link_uses_the_public_origin(monkeypatch):
    monkeypatch.setattr(email_service, "get_settings", lambda: _StubSettings())
    link = email_service.verification_link("tok123")
    assert link == "https://localiq.tavesglobal.com/verify-email?token=tok123"


# ---------------------------------------------------------------------------
# Registration -> verification
# ---------------------------------------------------------------------------


def test_register_sends_a_verification_email(monkeypatch):
    sent = _capture_verification(monkeypatch)
    body, email = _register()

    assert len(sent) == 1
    assert sent[0]["to"] == email
    assert sent[0]["token"]
    assert body["user"]["email_verified"] is False

    with Session(engine) as session:
        user = session.exec(select(User).where(User.email == email)).one()
        rows = session.exec(
            select(EmailVerificationToken).where(EmailVerificationToken.user_id == user.id)
        ).all()
    assert len(rows) == 1
    assert rows[0].consumed_at is None


def test_verify_email_marks_the_account_verified(monkeypatch):
    sent = _capture_verification(monkeypatch)
    registered, _ = _register()
    token = sent[0]["token"]

    r = client.post("/api/v1/auth/verify-email", json={"token": token})
    assert r.status_code == 200, r.text
    payload = r.json()
    assert payload["status"] == "verified"
    assert payload["email_verified"] is True
    assert payload["user"]["email_verified"] is True

    me = client.get(
        "/api/v1/auth/me",
        headers={"Authorization": f"Bearer {registered['access_token']}"},
    )
    assert me.status_code == 200
    assert me.json()["email_verified"] is True


def test_verify_email_token_is_single_use(monkeypatch):
    sent = _capture_verification(monkeypatch)
    _register()
    token = sent[0]["token"]

    assert client.post("/api/v1/auth/verify-email", json={"token": token}).status_code == 200
    replay = client.post("/api/v1/auth/verify-email", json={"token": token})
    assert replay.status_code == 400


def test_verify_email_rejects_unknown_and_expired_tokens(monkeypatch):
    assert (
        client.post("/api/v1/auth/verify-email", json={"token": "nonsense-token-value"}).status_code
        == 400
    )

    sent = _capture_verification(monkeypatch)
    _, email = _register()
    token = sent[0]["token"]

    # Age the token past its TTL.
    with Session(engine) as session:
        user = session.exec(select(User).where(User.email == email)).one()
        row = session.exec(
            select(EmailVerificationToken).where(EmailVerificationToken.user_id == user.id)
        ).one()
        row.expires_at = utcnow() - timedelta(hours=1)
        session.add(row)
        session.commit()

    assert client.post("/api/v1/auth/verify-email", json={"token": token}).status_code == 400


def test_issuing_a_new_token_invalidates_the_previous_one(monkeypatch):
    sent = _capture_verification(monkeypatch)
    _, email = _register()
    first = sent[0]["token"]

    r = client.post("/api/v1/auth/resend-verification", headers={"Authorization": "Bearer x"})
    assert r.status_code == 401  # needs a real session; token issuing is covered below

    # Issue twice for the same user directly through the service.
    with Session(engine) as session:
        user = session.exec(select(User).where(User.email == email)).one()
        second = verification.issue(session, user)

    assert client.post("/api/v1/auth/verify-email", json={"token": first}).status_code == 400
    assert client.post("/api/v1/auth/verify-email", json={"token": second}).status_code == 200


# ---------------------------------------------------------------------------
# Resend
# ---------------------------------------------------------------------------


def test_resend_verification_is_throttled(monkeypatch):
    sent = _capture_verification(monkeypatch)
    registered, _ = _register()
    headers = {"Authorization": f"Bearer {registered['access_token']}"}

    # Immediately after registering, the cooldown is still active.
    throttled = client.post("/api/v1/auth/resend-verification", headers=headers)
    assert throttled.status_code == 429
    assert "Retry-After" in throttled.headers

    # Move the last-sent stamp into the past and it succeeds.
    with Session(engine) as session:
        user = session.exec(select(User).where(User.email == registered["user"]["email"])).one()
        user.email_verification_sent_at = utcnow() - timedelta(minutes=5)
        session.add(user)
        session.commit()

    ok = client.post("/api/v1/auth/resend-verification", headers=headers)
    assert ok.status_code == 200, ok.text
    assert ok.json()["status"] == "sent"
    assert len(sent) == 2


def test_resend_when_already_verified_is_a_noop(monkeypatch):
    sent = _capture_verification(monkeypatch)
    registered, _ = _register()
    headers = {"Authorization": f"Bearer {registered['access_token']}"}

    client.post("/api/v1/auth/verify-email", json={"token": sent[0]["token"]})

    r = client.post("/api/v1/auth/resend-verification", headers=headers)
    assert r.status_code == 200
    assert r.json()["status"] == "already_verified"
    assert r.json()["email_verified"] is True


# ---------------------------------------------------------------------------
# Password reset now emails a link
# ---------------------------------------------------------------------------


def test_forgot_password_emails_the_reset_link(monkeypatch):
    sent = _capture_reset(monkeypatch)
    _, email = _register()

    r = client.post("/api/v1/auth/forgot-password", json={"email": email})
    assert r.status_code == 200
    assert len(sent) == 1
    assert sent[0]["to"] == email

    # Non-production still returns the token so the flow is completable offline.
    token = r.json()["dev_reset_token"]
    assert token == sent[0]["token"]

    reset = client.post(
        "/api/v1/auth/reset-password", json={"token": token, "password": "NewSecret456"}
    )
    assert reset.status_code == 200


def test_forgot_password_does_not_email_unknown_addresses(monkeypatch):
    sent = _capture_reset(monkeypatch)
    r = client.post(
        "/api/v1/auth/forgot-password",
        json={"email": f"nobody-{uuid.uuid4().hex}@localiq.test"},
    )
    assert r.status_code == 200
    assert sent == []
    assert "dev_reset_token" not in r.json()


# ---------------------------------------------------------------------------
# Google
# ---------------------------------------------------------------------------


def test_google_without_a_verified_email_still_gets_a_link(monkeypatch):
    import base64
    import json

    sent = _capture_verification(monkeypatch)

    def b64(obj: dict) -> str:
        return base64.urlsafe_b64encode(json.dumps(obj).encode()).rstrip(b"=").decode()

    email = f"google-{uuid.uuid4().hex[:8]}@localiq.test"
    id_token = f"{b64({'alg': 'none'})}.{b64({'sub': 'g-1', 'email': email})}.sig"

    r = client.post("/api/v1/auth/google", json={"id_token": id_token})
    assert r.status_code == 200, r.text
    assert r.json()["user"]["email_verified"] is False
    assert len(sent) == 1
    assert sent[0]["to"] == email


def test_google_with_a_verified_email_skips_the_link(monkeypatch):
    import base64
    import json

    sent = _capture_verification(monkeypatch)

    def b64(obj: dict) -> str:
        return base64.urlsafe_b64encode(json.dumps(obj).encode()).rstrip(b"=").decode()

    email = f"google-{uuid.uuid4().hex[:8]}@localiq.test"
    id_token = (
        f"{b64({'alg': 'none'})}."
        f"{b64({'sub': 'g-2', 'email': email, 'email_verified': 'true'})}.sig"
    )

    r = client.post("/api/v1/auth/google", json={"id_token": id_token})
    assert r.status_code == 200, r.text
    assert r.json()["user"]["email_verified"] is True
    assert sent == []
