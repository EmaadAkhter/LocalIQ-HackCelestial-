"""Tests for taste signals from likes/plans and the A-to-Z itinerary planner."""

import uuid

from fastapi.testclient import TestClient
from sqlmodel import Session, select

from app.database import engine
from app.models import Experience
from main import app

client = TestClient(app)


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------


def _register() -> tuple[str, int]:
    email = f"planner-{uuid.uuid4().hex[:10]}@localiq.test"
    r = client.post(
        "/api/v1/auth/register",
        json={"name": "Planner User", "email": email, "password": "Secret123"},
    )
    assert r.status_code == 201, r.text
    body = r.json()
    return body["access_token"], body["user"]["id"]


def _auth(token: str) -> dict:
    return {"Authorization": f"Bearer {token}"}


def _all_experiences() -> list[Experience]:
    with Session(engine) as session:
        return list(session.exec(select(Experience)).all())


def _tagged(n: int = 4) -> list[Experience]:
    tagged = [e for e in _all_experiences() if e.tags]
    assert len(tagged) >= n, "seed data needs tagged experiences"
    return tagged[:n]


def _taste_interactions(token: str) -> dict:
    r = client.get("/api/v1/me/taste", headers=_auth(token))
    assert r.status_code == 200, r.text
    return r.json()["interactions"]


# ---------------------------------------------------------------------------
# Part 1 — likes / feedback / plans feed taste
# ---------------------------------------------------------------------------


def test_interaction_weights_include_like_and_plan_actions():
    from app.models import INTERACTION_WEIGHTS

    assert INTERACTION_WEIGHTS["like"] > 0
    assert INTERACTION_WEIGHTS["add_to_itinerary"] > 0
    assert INTERACTION_WEIGHTS["unlike"] < 0
    assert INTERACTION_WEIGHTS["remove_from_itinerary"] < 0


def test_favorite_records_like_signal():
    token, _ = _register()
    exp = _tagged(1)[0]
    before = _taste_interactions(token).get("like", 0)

    r = client.post(f"/api/v1/me/favorites/{exp.id}", headers=_auth(token))
    assert r.status_code == 201, r.text

    after = _taste_interactions(token)
    assert after.get("like", 0) == before + 1

    taste = client.get("/api/v1/me/taste", headers=_auth(token)).json()
    assert taste["vector"], "a like should populate the taste vector"


def test_idempotent_favorite_does_not_double_count():
    token, _ = _register()
    exp = _tagged(1)[0]
    client.post(f"/api/v1/me/favorites/{exp.id}", headers=_auth(token))
    client.post(f"/api/v1/me/favorites/{exp.id}", headers=_auth(token))
    assert _taste_interactions(token).get("like", 0) == 1


def test_unfavorite_records_unlike():
    token, _ = _register()
    exp = _tagged(1)[0]
    client.post(f"/api/v1/me/favorites/{exp.id}", headers=_auth(token))
    r = client.delete(f"/api/v1/me/favorites/{exp.id}", headers=_auth(token))
    assert r.status_code == 204
    assert _taste_interactions(token).get("unlike", 0) == 1


def test_thumbs_feedback_records_like_and_dismiss():
    token, _ = _register()
    exp = _tagged(1)[0]

    up = client.post(
        f"/api/v1/recommendations/{exp.id}/feedback",
        json={"helpful": True},
        headers=_auth(token),
    )
    assert up.status_code == 200, up.text
    assert _taste_interactions(token).get("like", 0) == 1

    down = client.post(
        f"/api/v1/recommendations/{exp.id}/feedback",
        json={"helpful": False},
        headers=_auth(token),
    )
    assert down.status_code == 200, down.text
    assert _taste_interactions(token).get("dismiss", 0) == 1


def test_creating_itinerary_records_add_to_itinerary():
    token, _ = _register()
    exps = _tagged(2)
    r = client.post(
        "/api/v1/itineraries",
        json={
            "name": "Taste plan",
            "stops": [{"experience_id": e.id} for e in exps],
        },
        headers=_auth(token),
    )
    assert r.status_code == 201, r.text
    assert _taste_interactions(token).get("add_to_itinerary", 0) >= 2


def test_updating_itinerary_records_added_and_removed():
    token, _ = _register()
    exps = _tagged(3)
    created = client.post(
        "/api/v1/itineraries",
        json={"name": "Two stop", "stops": [{"experience_id": exps[0].id}, {"experience_id": exps[1].id}]},
        headers=_auth(token),
    )
    itinerary_id = created.json()["id"]

    client.put(
        f"/api/v1/itineraries/{itinerary_id}",
        json={"stops": [{"experience_id": exps[1].id}, {"experience_id": exps[2].id}]},
        headers=_auth(token),
    )
    counts = _taste_interactions(token)
    assert counts.get("add_to_itinerary", 0) >= 3  # 2 initial + 1 added
    assert counts.get("remove_from_itinerary", 0) >= 1


# ---------------------------------------------------------------------------
# Part 2 — planner service
# ---------------------------------------------------------------------------


def test_plan_day_builds_ordered_feasible_stops():
    from app.services import itinerary_planner

    with Session(engine) as session:
        plan = itinerary_planner.plan_day(
            session,
            None,
            start_location="Bandra",
            start_time="10:00",
            duration_hours=10.0,
            max_stops=4,
        )

    assert plan.stops, "planner should produce at least one stop"
    assert len(plan.stops) <= 4
    assert [s.sequence for s in plan.stops] == list(range(len(plan.stops)))
    # Each stop starts after the previous one ends (travel is baked into start).
    for earlier, later in zip(plan.stops, plan.stops[1:]):
        assert earlier.end_min <= later.start_min
    assert plan.total_cost == sum(s.experience.avg_cost for s in plan.stops)


def test_plan_day_reports_when_nothing_fits():
    from app.services import itinerary_planner, recommender

    # Find a venue that is shut at 10:00, then plan around only that venue.
    with Session(engine) as session:
        closed = next(
            (
                e
                for e in session.exec(select(Experience)).all()
                if not recommender.is_open_at(e, 10 * 60, e.duration_min)
            ),
            None,
        )
        if closed is None:
            import pytest

            pytest.skip("no evening-only venue in the seed data")
        plan = itinerary_planner.plan_day(
            session,
            None,
            start_time="10:00",
            duration_hours=8.0,
            max_stops=3,
            candidate_ids=[closed.id],
        )
    assert plan.stops == []
    assert plan.notes


def test_optimize_order_keeps_all_and_fixes_first_stop():
    from app.services import itinerary_planner

    exps = _tagged(4)
    plan = itinerary_planner.optimize_order(exps, origin=None, start_time="10:00")
    assert len(plan) == len(exps)
    assert {s.experience.id for s in plan} == {e.id for e in exps}
    assert plan[0].experience.id == exps[0].id, "first stop is the anchor"
    assert [s.start_min for s in plan] == sorted(s.start_min for s in plan)


def test_parse_itinerary_text_handles_common_formats():
    from app.services import itinerary_planner

    rows = itinerary_planner.parse_itinerary_text(
        "10:00 Gateway of India\n"
        "- 12:30pm Leopold Cafe\n"
        "2 PM Marine Drive\n"
        "Elephanta Caves\n"
        "10 places to eat\n"
    )
    assert [r["name"] for r in rows] == [
        "Gateway of India",
        "Leopold Cafe",
        "Marine Drive",
        "Elephanta Caves",
        "10 places to eat",
    ]
    assert rows[0]["start_time"] == "10:00"
    assert rows[1]["start_time"].lower() == "12:30pm"
    assert rows[3]["start_time"] == ""
    assert rows[4]["start_time"] == "", "a bare number is not a time"


def test_itinerary_to_ics_emits_events():
    from app.models import Itinerary
    from app.services import itinerary_planner

    exps = _tagged(1)
    itinerary = Itinerary(id=42, name="Test day")
    body = itinerary_planner.itinerary_to_ics(
        itinerary, [(exps[0], "10:00", "11:00")]
    )
    assert "BEGIN:VCALENDAR" in body
    assert "BEGIN:VEVENT" in body
    assert "SUMMARY:" in body
    assert "END:VCALENDAR" in body


# ---------------------------------------------------------------------------
# Part 2 — planner endpoints
# ---------------------------------------------------------------------------


def test_generate_itinerary_endpoint_and_records_taste():
    token, _ = _register()
    r = client.post(
        "/api/v1/itineraries/generate",
        json={
            "name": "Bandra day",
            "start_location": "Bandra",
            "start_time": "10:00",
            "duration_hours": 9,
            "max_stops": 4,
        },
        headers=_auth(token),
    )
    assert r.status_code == 201, r.text
    body = r.json()
    assert body["stops"], "generated plan should have stops"
    assert all(s["start_time"] for s in body["stops"])
    assert _taste_interactions(token).get("add_to_itinerary", 0) >= 1

    fetched = client.get(f"/api/v1/itineraries/{body['id']}", headers=_auth(token))
    assert fetched.status_code == 200
    assert len(fetched.json()["stops"]) == len(body["stops"])


def test_import_by_id_and_name():
    token, _ = _register()
    exps = _tagged(2)
    r = client.post(
        "/api/v1/itineraries/import",
        json={
            "name": "Imported",
            "format": "json",
            "stops": [
                {"experience_id": exps[0].id, "start_time": "09:30"},
                {"name": exps[1].name},
            ],
        },
        headers=_auth(token),
    )
    assert r.status_code == 201, r.text
    body = r.json()
    assert len(body["itinerary"]["stops"]) == 2
    assert body["unresolved"] == []


def test_import_from_text():
    token, _ = _register()
    exp = _tagged(1)[0]
    r = client.post(
        "/api/v1/itineraries/import",
        json={"name": "Text plan", "format": "text", "text": f"10:00 {exp.name}"},
        headers=_auth(token),
    )
    assert r.status_code == 201, r.text
    assert len(r.json()["itinerary"]["stops"]) == 1


def test_import_reports_unresolved_names():
    token, _ = _register()
    exp = _tagged(1)[0]
    r = client.post(
        "/api/v1/itineraries/import",
        json={
            "name": "Partly imported",
            "stops": [
                {"experience_id": exp.id},
                {"name": "Definitely Not A Real Place XYZ"},
            ],
        },
        headers=_auth(token),
    )
    assert r.status_code == 201, r.text
    assert r.json()["unresolved"] == ["Definitely Not A Real Place XYZ"]


def test_export_json_ics_and_text():
    token, _ = _register()
    exps = _tagged(2)
    created = client.post(
        "/api/v1/itineraries",
        json={"name": "Export me", "stops": [{"experience_id": e.id} for e in exps]},
        headers=_auth(token),
    ).json()
    itinerary_id = created["id"]

    as_json = client.get(
        f"/api/v1/itineraries/{itinerary_id}/export?format=json", headers=_auth(token)
    )
    assert as_json.status_code == 200
    assert as_json.json()["name"] == "Export me"

    as_ics = client.get(
        f"/api/v1/itineraries/{itinerary_id}/export?format=ics&date=2026-10-01",
        headers=_auth(token),
    )
    assert as_ics.status_code == 200
    assert as_ics.headers["content-type"].startswith("text/calendar")
    assert "BEGIN:VEVENT" in as_ics.text

    as_text = client.get(
        f"/api/v1/itineraries/{itinerary_id}/export?format=text", headers=_auth(token)
    )
    assert as_text.status_code == 200
    assert exps[0].name in as_text.text


def test_share_link_is_public():
    token, _ = _register()
    exp = _tagged(1)[0]
    created = client.post(
        "/api/v1/itineraries",
        json={"name": "Shareable", "stops": [{"experience_id": exp.id}]},
        headers=_auth(token),
    ).json()

    share = client.post(f"/api/v1/itineraries/{created['id']}/share", headers=_auth(token))
    assert share.status_code == 200, share.text
    token_value = share.json()["share_token"]
    assert token_value

    # Fetching the shared plan needs no authentication.
    public = client.get(f"/api/v1/itineraries/shared/{token_value}")
    assert public.status_code == 200
    assert public.json()["id"] == created["id"]


def test_optimize_endpoint_preserves_stops():
    token, _ = _register()
    exps = _tagged(3)
    created = client.post(
        "/api/v1/itineraries",
        json={"name": "Messy order", "stops": [{"experience_id": e.id} for e in exps]},
        headers=_auth(token),
    ).json()

    r = client.post(
        f"/api/v1/itineraries/{created['id']}/optimize",
        headers=_auth(token),
    )
    assert r.status_code == 200, r.text
    body = r.json()
    assert len(body["stops"]) == 3
    assert body["stops"][0]["experience"]["id"] == exps[0].id


def test_itinerary_endpoints_require_auth():
    assert client.get("/api/v1/itineraries").status_code == 401
    assert (
        client.post("/api/v1/itineraries/generate", json={"start_location": "Bandra"}).status_code
        == 401
    )
