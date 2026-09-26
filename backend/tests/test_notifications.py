"""Notification endpoints, and the events that raise them."""

import uuid
from datetime import date

from fastapi.testclient import TestClient
from sqlmodel import Session, select

from app.api.v1.guides_ops import _BOOKING_NOTIFICATIONS, _notify_booking_status
from app.database import engine
from app.models import Notification
from app.models_prd import GuideBooking
from app.services import notifications as notification_service
from main import app

client = TestClient(app)


def _register() -> tuple[dict, int]:
    email = f"notify-{uuid.uuid4().hex[:10]}@localiq.test"
    r = client.post(
        "/api/v1/auth/register",
        json={"name": "Notif Tester", "email": email, "password": "Secret123"},
    )
    assert r.status_code == 201, r.text
    body = r.json()
    return {
        "Authorization": f"Bearer {body['access_token']}"
    }, body["user"]["id"]


def _seed(user_id: int, body: str, *, kind: str = "system") -> int:
    with Session(engine) as session:
        row = notification_service.create(
            session, user_id=user_id, title="Heads up", body=body, kind=kind
        )
        assert row is not None
        return row.id


# ---------------------------------------------------------------------------
# Endpoints
# ---------------------------------------------------------------------------


def test_list_returns_newest_first():
    headers, uid = _register()
    _seed(uid, "first")
    _seed(uid, "second")

    r = client.get("/api/v1/notifications", headers=headers)
    assert r.status_code == 200, r.text
    bodies = [n["body"] for n in r.json()]
    assert bodies == ["second", "first"]


def test_unread_count_tracks_read_state():
    headers, uid = _register()
    first = _seed(uid, "a")
    _seed(uid, "b")

    assert client.get("/api/v1/notifications/unread-count", headers=headers).json() == {
        "unread": 2
    }

    assert client.post(f"/api/v1/notifications/{first}/read", headers=headers).status_code == 200
    assert client.get("/api/v1/notifications/unread-count", headers=headers).json() == {
        "unread": 1
    }


def test_marking_read_twice_is_404():
    headers, uid = _register()
    nid = _seed(uid, "once")
    assert client.post(f"/api/v1/notifications/{nid}/read", headers=headers).status_code == 200
    assert client.post(f"/api/v1/notifications/{nid}/read", headers=headers).status_code == 404


def test_cannot_read_another_users_notification():
    _, alice = _register()
    bob_headers, _ = _register()
    nid = _seed(alice, "for alice only")

    # Bob knows the id but it is not his.
    assert client.post(f"/api/v1/notifications/{nid}/read", headers=bob_headers).status_code == 404
    assert client.get("/api/v1/notifications", headers=bob_headers).json() == []


def test_read_all_marks_everything():
    headers, uid = _register()
    _seed(uid, "a")
    _seed(uid, "b")

    r = client.post("/api/v1/notifications/read-all", headers=headers)
    assert r.status_code == 200
    assert r.json()["updated"] == 2
    assert client.get("/api/v1/notifications/unread-count", headers=headers).json() == {
        "unread": 0
    }


def test_notifications_require_authentication():
    assert client.get("/api/v1/notifications").status_code == 401
    assert client.get("/api/v1/notifications/unread-count").status_code == 401


def test_deleting_an_account_removes_its_notifications():
    headers, uid = _register()
    _seed(uid, "gone soon")

    assert client.delete("/api/v1/auth/me", headers=headers).status_code == 204
    with Session(engine) as session:
        assert session.exec(select(Notification).where(Notification.user_id == uid)).all() == []


# ---------------------------------------------------------------------------
# Events that raise notifications
# ---------------------------------------------------------------------------


def test_create_is_a_noop_without_a_user():
    """Guest guide requests have no account to notify."""
    with Session(engine) as session:
        assert notification_service.create(session, user_id=None, title="x", body="y") is None


def test_every_booking_transition_has_traveller_copy():
    """No transition may silently skip notifying the traveller."""
    expected = {"accepted", "confirmed", "in_progress", "completed", "declined", "cancelled"}
    assert expected <= set(_BOOKING_NOTIFICATIONS)


def test_booking_transition_creates_a_notification():
    _, uid = _register()
    with Session(engine) as session:
        booking = GuideBooking(user_id=uid, guide_id=1, date=date.today())
        session.add(booking)
        session.commit()
        session.refresh(booking)
        booking_id = booking.id

        _notify_booking_status(session, booking, "accepted")

        rows = session.exec(select(Notification).where(Notification.user_id == uid)).all()
        assert len(rows) == 1
        # Read the fields while still attached: ``create`` commits, which expires
        # the instances, and the session closes right after.
        created_kind = rows[0].kind
        created_data = dict(rows[0].data)

    assert created_kind == "booking"
    assert created_data == {"booking_id": booking_id, "status": "accepted"}
