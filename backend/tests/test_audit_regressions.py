"""Regression tests for the audit findings.

Each test here failed before the corresponding fix and pins the exact
behaviour that was wrong:

* ``test_recommend`` returning items that exceeded the requested time window or
  the distance cap once Google Routes data was attached (the local estimate used
  for screening is optimistic).
* ``accessibility="wheelchair-accessible"`` being satisfied by venues that only
  advertise ``step-free``.
* ``/parse`` and ``/chat`` freezing for ~8s per call while Ollama is down.
* seeded experiences having no image at all.
"""

from __future__ import annotations

import json
import time
from pathlib import Path

import pytest
from fastapi.testclient import TestClient
from sqlmodel import Session, select

from app.database import engine
from main import app
from app.models import Experience
from app.services import google_places, google_routes
from app.services.recommender import (
    MAX_CONSIDER_DISTANCE_KM,
    check_feasibility,
    haversine_km,
    missing_capabilities,
    recheck_with_route,
    required_accessibility,
    venue_capabilities,
)

client = TestClient(app)
DATA_DIR = Path(__file__).resolve().parent.parent / "data"


# ---------------------------------------------------------------------------
# 1. Hard constraints must survive route enrichment
# ---------------------------------------------------------------------------


def _exp(**kw) -> Experience:
    base = dict(
        name="T",
        category="food",
        lat=19.05,
        lng=72.82,
        avg_cost=500,
        duration_min=60,
        open_time="09:00",
        close_time="21:00",
        rating=4.5,
        description="t",
        tags=[],
        accessibility_flags=[],
    )
    base.update(kw)
    return Experience(**base)


class TestRouteRecheck:
    def test_slow_real_route_fails_a_result_the_estimate_passed(self):
        """The exact bug: 10 min estimate fits, 83 min real travel does not."""
        exp = _exp(duration_min=150)
        # Phase A used the local estimate and let it through.
        assert check_feasibility(
            exp,
            budget_inr=5000,
            time_hours=4,
            user_coords=(19.0596, 72.8295),
            accessibility=None,
            start_time=None,
        ).feasible

        # Real route data says 83 minutes each way.
        recheck = recheck_with_route(
            exp, distance_km=6.02, travel_minutes=83, time_hours=4
        )
        assert recheck.ok is False
        assert recheck.total_minutes == 150 + 83 * 2 + 20
        assert "over the 240min available" in recheck.reason

    def test_far_route_breaks_the_distance_cap(self):
        """33.9 km passed the local screen but is over the 30 km cap."""
        recheck = recheck_with_route(
            _exp(duration_min=30), distance_km=33.9, travel_minutes=286, time_hours=12
        )
        assert recheck.ok is False
        assert f"{MAX_CONSIDER_DISTANCE_KM:.0f}km limit" in recheck.reason

    def test_fast_near_route_still_passes(self):
        recheck = recheck_with_route(
            _exp(duration_min=45), distance_km=1.1, travel_minutes=12, time_hours=4
        )
        assert recheck.ok is True
        assert recheck.total_minutes == 45 + 12 * 2 + 20

    def test_custom_cap_is_honoured(self):
        recheck = recheck_with_route(
            _exp(duration_min=30),
            distance_km=8.0,
            travel_minutes=20,
            time_hours=12,
            max_distance_km=5.0,
        )
        assert recheck.ok is False


def test_recommend_never_returns_items_violating_hard_constraints(monkeypatch):
    """End-to-end: with include_route=true every item must still fit.

    Routes are mocked to be *optimistic* for nearby venues and slow for far
    ones, so some items survive and some must be dropped.
    """

    def route_for(lat, lng):
        distance_km = haversine_km(19.0596, 72.8295, lat, lng)
        # ~walking pace on the real distance, rounded.
        minutes = max(6, int(distance_km * 3))
        return google_routes.RouteResult(
            distance_m=int(distance_km * 1000),
            duration_s=minutes * 60,
            duration_min=minutes,
            polyline=None,
            travel_mode="WALK",
            source="google_routes",
        )

    async def fake_route_between_many(lat, lng, destinations, *, travel_mode="WALK"):
        return [route_for(dlat, dlng) for dlat, dlng in destinations]

    monkeypatch.setattr(google_places, "search_places", _async_return([]), raising=True)
    from app.api.v1 import recommendations as rec_api

    monkeypatch.setattr(rec_api.google_routes, "route_between_many", fake_route_between_many)
    rec_api.clear_recommend_cache()

    window_minutes = 240
    r = client.post(
        "/api/v1/recommend",
        json={
            "location": "Bandra",
            "time_hours": 4,
            "budget_inr": 2000,
            "include_route": True,
            "limit": 20,
        },
    )
    assert r.status_code == 200
    body = r.json()

    assert body["route_source"] == "google_routes"
    assert body["recommendations"], "expected at least one item to survive real routes"
    for item in body["recommendations"]:
        assert item["total_time_min"] <= window_minutes, (
            f"{item['name']} returned {item['total_time_min']}min for a "
            f"{window_minutes}min window"
        )
        assert item["distance_km"] <= MAX_CONSIDER_DISTANCE_KM
    # feasible_count must match what is actually returned.
    assert body["feasible_count"] == len(body["recommendations"])


def test_recommend_drops_everything_when_real_routes_are_too_slow(monkeypatch):
    """Extreme case: if nothing fits with real travel times, return nothing."""
    async def slow_routes(lat, lng, destinations, *, travel_mode="WALK"):
        return [
            google_routes.RouteResult(
                distance_m=6_020,
                duration_s=83 * 60,
                duration_min=83,
                travel_mode=travel_mode,
                source="google_routes",
            )
            for _ in destinations
        ]

    from app.api.v1 import recommendations as rec_api

    monkeypatch.setattr(rec_api.google_routes, "route_between_many", slow_routes)
    monkeypatch.setattr(google_places, "search_places", _async_return([]), raising=True)
    rec_api.clear_recommend_cache()

    r = client.post(
        "/api/v1/recommend",
        json={"location": "Bandra", "time_hours": 3, "budget_inr": 2000, "include_route": True},
    )
    assert r.status_code == 200
    body = r.json()
    assert body["recommendations"] == []
    assert body["feasible_count"] == 0
    assert body["total_candidates"] > 0  # candidates still reported
    rec_api.clear_recommend_cache()


def test_recommend_without_route_data_still_respects_the_window():
    r = client.post(
        "/api/v1/recommend",
        json={"location": "Bandra", "time_hours": 3, "budget_inr": 2000, "include_route": False},
    )
    assert r.status_code == 200
    for item in r.json()["recommendations"]:
        assert item["total_time_min"] <= 180


# ---------------------------------------------------------------------------
# 2. Accessibility must be strict
# ---------------------------------------------------------------------------


class TestAccessibilityStrictness:
    def test_step_free_alone_does_not_satisfy_wheelchair(self):
        assert missing_capabilities("wheelchair-accessible", ["step-free"]) == [
            "wheelchair-accessible"
        ]

    def test_wheelchair_flag_satisfies_wheelchair_request(self):
        assert missing_capabilities("wheelchair-accessible", ["wheelchair-accessible"]) == []
        assert missing_capabilities("wheelchair", ["wheelchair-accessible"]) == []

    def test_step_free_request_accepts_step_free_venue(self):
        assert missing_capabilities("step-free", ["step-free"]) == []

    def test_wheelchair_venue_satisfies_step_free_request(self):
        # A fully wheelchair-accessible venue is also step-free.
        assert missing_capabilities("step-free", ["wheelchair-accessible", "step-free"]) == []

    def test_combined_request_is_and_semantics(self):
        assert missing_capabilities(
            ["wheelchair-accessible", "step-free"], ["wheelchair-accessible"]
        ) == ["step-free"]
        assert missing_capabilities(
            ["wheelchair-accessible", "step-free"],
            ["wheelchair-accessible", "step-free"],
        ) == []

    def test_empty_request_has_no_requirements(self):
        assert missing_capabilities(None, []) == []
        assert missing_capabilities([], ["step-free"]) == []

    def test_normalisation_maps_variants(self):
        assert required_accessibility("Wheelchair Accessible") == ["wheelchair-accessible"]
        assert required_accessibility("step free") == ["step-free"]
        assert "wheelchair-accessible" in venue_capabilities(["Wheelchair-Accessible"])


def test_feasibility_rejects_step_free_only_for_wheelchair_request():
    exp = _exp(accessibility_flags=["step-free"])
    result = check_feasibility(
        exp,
        budget_inr=5000,
        time_hours=8,
        user_coords=(19.05, 72.82),
        accessibility="wheelchair-accessible",
        start_time=None,
    )
    assert result.feasible is False
    assert "missing accessibility" in result.reasons[0]

    ok = check_feasibility(
        _exp(accessibility_flags=["wheelchair-accessible", "step-free"]),
        budget_inr=5000,
        time_hours=8,
        user_coords=(19.05, 72.82),
        accessibility="wheelchair-accessible",
        start_time=None,
    )
    assert ok.feasible is True


def test_recommend_accessibility_endpoint_is_strict():
    r = client.post(
        "/api/v1/recommend",
        json={
            "time_hours": 12,
            "budget_inr": 99999,
            "accessibility": "wheelchair-accessible",
            "include_route": False,
        },
    )
    assert r.status_code == 200
    items = r.json()["recommendations"]
    assert items, "expected accessible venues to exist"
    for item in items:
        flags = " ".join(item["accessibility_flags"]).lower()
        assert "wheelchair" in flags, f"{item['name']} has no wheelchair flag: {flags}"

    r2 = client.post(
        "/api/v1/recommend",
        json={
            "time_hours": 12,
            "budget_inr": 99999,
            "accessibility": ["wheelchair-accessible", "step-free"],
            "include_route": False,
        },
    )
    for item in r2.json()["recommendations"]:
        flags = " ".join(item["accessibility_flags"]).lower()
        assert "wheelchair" in flags and "step-free" in flags


# ---------------------------------------------------------------------------
# 3. LLM circuit breaker
# ---------------------------------------------------------------------------


class TestLLMCircuitBreaker:
    def test_opens_after_repeated_failures_and_short_circuits(self):
        from app.services import llm

        llm.reset_circuit()
        assert llm.circuit_state()["open"] is False

        breaker = llm._circuit
        breaker.threshold = 3
        breaker.cooldown_seconds = 60.0
        breaker.reset()

        # Simulate the failure path three times (no network needed).
        for _ in range(3):
            breaker.record_failure()
        state = llm.circuit_state()
        assert state["open"] is True
        assert state["consecutive_failures"] == 3
        assert state["cooldown_remaining_s"] > 0

        # A call while open must fail immediately with the circuit message,
        # instead of paying the full retry ladder (~8s when Ollama is down).
        import asyncio

        started = time.perf_counter()
        with pytest.raises(llm.LLMError) as excinfo:
            asyncio.run(llm.generate("hello", max_tokens=1, timeout=5))
        elapsed = time.perf_counter() - started
        assert "circuit open" in str(excinfo.value)
        assert elapsed < 1.0, f"short-circuit still took {elapsed:.2f}s"

        llm.reset_circuit()
        assert llm.circuit_state()["open"] is False

    def test_success_resets_the_breaker(self):
        from app.services import llm

        breaker = llm._circuit
        breaker.threshold = 2
        breaker.cooldown_seconds = 60.0
        breaker.reset()
        breaker.record_failure()
        breaker.record_failure()
        assert breaker.state()["open"] is True
        breaker.record_success()
        assert breaker.state()["open"] is False
        assert breaker.state()["consecutive_failures"] == 0
        llm.reset_circuit()

    def test_cooldown_expiry_half_opens(self):
        from app.services import llm

        breaker = llm._circuit
        breaker.threshold = 1
        breaker.cooldown_seconds = 0.0
        breaker.reset()
        breaker.record_failure()
        # Cooldown of zero means the next check reports closed and retries.
        assert breaker.state()["open"] is False
        llm.reset_circuit()

    def test_parse_and_chat_fall_back_quickly_when_ollama_is_down(self):
        """The user-visible symptom: an ~8s freeze per AI request."""
        from app.services import llm

        llm.reset_circuit()
        # Trip the breaker so the test does not depend on the real network.
        llm._circuit.threshold = 1
        llm._circuit.cooldown_seconds = 30.0
        llm._circuit.reset()
        llm._circuit.record_failure()

        try:
            started = time.perf_counter()
            r = client.post("/api/v1/parse", json={"text": "4 hours 1500 food in Bandra"})
            parse_elapsed = time.perf_counter() - started
            assert r.status_code == 200
            assert r.json()["constraints"]["time_hours"] == 4
            assert parse_elapsed < 1.0, f"/parse took {parse_elapsed:.2f}s"

            started = time.perf_counter()
            c = client.post("/api/v1/chat", json={"experience_id": 1, "message": "hi"})
            chat_elapsed = time.perf_counter() - started
            assert c.status_code == 200
            assert c.json()["reply"]
            assert chat_elapsed < 1.0, f"/chat took {chat_elapsed:.2f}s"
        finally:
            llm._circuit.threshold = 3
            llm.reset_circuit()


# ---------------------------------------------------------------------------
# 4. Curated images
# ---------------------------------------------------------------------------


def test_every_seeded_experience_has_an_image():
    with Session(engine) as session:
        rows = session.exec(select(Experience)).all()
    assert len(rows) >= 48
    missing = [r.name for r in rows if not (r.image_url or "").strip()]
    assert not missing, f"{len(missing)} experiences have no image_url: {missing[:5]}"


def test_dataset_image_urls_point_at_real_local_files():
    dataset = json.loads(
        (DATA_DIR / "mumbai_experiences.json").read_text(encoding="utf-8")
    )
    experiences = dataset["experiences"]
    assert len(experiences) == 48
    for exp in experiences:
        url = exp.get("image_url") or ""
        assert url.startswith("/static/images/"), f"{exp['name']}: {url!r}"
        path = DATA_DIR / "images" / url.rsplit("/", 1)[-1]
        assert path.exists(), f"missing file for {exp['name']}: {path.name}"
        assert path.stat().st_size > 15_000
        with path.open("rb") as handle:
            assert handle.read(3) == b"\xff\xd8\xff", f"{path.name} is not a JPEG"


def test_image_manifest_records_attribution():
    manifest = json.loads((DATA_DIR / "images" / "manifest.json").read_text(encoding="utf-8"))
    assert len(manifest) == 48
    for name, entry in manifest.items():
        assert entry.get("source"), f"{name} has no source URL"
        assert entry.get("license"), f"{name} has no license"


def test_static_image_route_serves_a_curated_image():
    dataset = json.loads(
        (DATA_DIR / "mumbai_experiences.json").read_text(encoding="utf-8")
    )
    first = dataset["experiences"][0]["image_url"]
    response = client.get(first)
    assert response.status_code == 200
    assert response.headers["content-type"].startswith("image/")
    assert len(response.content) > 15_000


def test_experiences_api_exposes_images():
    r = client.get("/api/v1/experiences?limit=5")
    assert r.status_code == 200
    for item in r.json()["items"]:
        assert item["image_url"], f"{item['name']} missing image_url"


# ---------------------------------------------------------------------------
# 5. Nearby shape + integrations status caching
# ---------------------------------------------------------------------------


def test_nearby_returns_flat_items_plus_legacy_results():
    r = client.get("/api/v1/experiences/nearby?lat=19.0596&lng=72.8295&radius_km=5&limit=5")
    assert r.status_code == 200
    body = r.json()
    assert body["total"] >= 0
    if body["items"]:
        item = body["items"][0]
        # Flat: the usual experience fields are top-level.
        assert {"id", "name", "category", "lat", "lng", "avg_cost", "rating"} <= set(item)
        assert "distance_km" in item and "travel_time_min" in item
        assert "experience" not in item
        # Legacy nested shape still present for older clients.
        assert body["results"][0]["experience"]["name"] == body["items"][0]["name"]


def test_integrations_status_is_cached():
    from app.api.v1 import places as places_api

    places_api.clear_integrations_status_cache()
    first = client.get("/api/v1/integrations/status")
    assert first.status_code == 200
    assert first.json()["cached"] is False

    second = client.get("/api/v1/integrations/status")
    assert second.json()["cached"] is True

    forced = client.get("/api/v1/integrations/status?refresh=true")
    assert forced.json()["cached"] is False
    places_api.clear_integrations_status_cache()


def test_places_search_is_cached(monkeypatch):
    from app.api.v1 import places as places_api

    calls = {"n": 0}
    original = google_places.search_places

    async def counting(*args, **kwargs):
        calls["n"] += 1
        return await original(*args, **kwargs)

    monkeypatch.setattr(places_api.google_places, "search_places", counting)
    places_api.clear_places_cache()

    client.get("/api/v1/places/search?q=zzz-cache-test&limit=3")
    after_first = calls["n"]
    client.get("/api/v1/places/search?q=zzz-cache-test&limit=3")
    client.get("/api/v1/places/search?q=zzz-cache-test&limit=3")
    assert calls["n"] == after_first, "repeat searches must not re-call Google"
    places_api.clear_places_cache()


def _async_return(value):
    async def _inner(*args, **kwargs):
        return value

    return _inner
