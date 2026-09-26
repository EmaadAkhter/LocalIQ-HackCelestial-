"""Phase 6 observability + resilience tests: Prometheus metrics, LLM
fallbacks, concurrency, auth edge cases."""

import uuid
from concurrent.futures import ThreadPoolExecutor

import pytest
from fastapi.testclient import TestClient
from sqlmodel import Session, select

from app.config import get_settings
from app.database import engine
from app.models import Experience, Guide
from main import app

client = TestClient(app)


# ---------------------------------------------------------------------------
# 6.1 Metrics
# ---------------------------------------------------------------------------


def _metrics_text() -> str:
    response = client.get("/metrics")
    assert response.status_code == 200
    return response.text


def _sum_metric(name: str, contains: str = "") -> float:
    total = 0.0
    for line in _metrics_text().splitlines():
        if line.startswith(name + "{") and contains in line:
            total += float(line.rsplit(" ", 1)[1])
    return total


def test_metrics_expose_expected_series():
    text = _metrics_text()
    for name in (
        "localiq_http_requests_total",
        "localiq_http_request_duration_seconds",
        "localiq_llm_cache_entries",
        "localiq_weather_cache_entries",
        "localiq_recommend_cache_entries",
        "localiq_db_pool_checked_out",
    ):
        assert name in text, f"missing metric {name}"


def test_request_counter_increments():
    # Route labels use the router-relative template path (e.g. /experiences),
    # which keeps cardinality low.
    before = _sum_metric("localiq_http_requests_total", "path=\"/experiences\"")
    client.get("/api/v1/experiences?limit=1")
    after = _sum_metric("localiq_http_requests_total", "path=\"/experiences\"")
    assert after >= before + 1


# ---------------------------------------------------------------------------
# 6.2 LLM failure fallbacks
# ---------------------------------------------------------------------------


def test_parse_falls_back_when_llm_unusable(monkeypatch):
    from app.api.v1 import parse as parse_module

    class Broken:
        async def generate_json(self, *args, **kwargs):
            return None

    monkeypatch.setattr(parse_module, "get_client", lambda: Broken())
    response = client.post(
        "/api/v1/parse", json={"text": "food for 2 hours under 500 rupees near bandra"}
    )
    assert response.status_code == 200
    assert response.json()["source"] == "heuristic"
    assert response.json()["constraints"]["budget_inr"] == 500


def test_chat_falls_back_when_llm_unusable(monkeypatch):
    from app.api.v1 import chat as chat_module

    class Broken:
        async def generate(self, *args, **kwargs):
            return None

    monkeypatch.setattr(chat_module, "get_client", lambda: Broken())
    with Session(engine) as session:
        experience_id = session.exec(select(Experience)).first().id

    response = client.post(
        "/api/v1/chat",
        json={"experience_id": experience_id, "message": "How do I reach there?"},
    )
    assert response.status_code == 200
    body = response.json()
    assert body["fallback"] is True
    assert body["source"] == "canned"
    assert body["reply"]


# ---------------------------------------------------------------------------
# 6.2 Concurrency
# ---------------------------------------------------------------------------


@pytest.mark.skipif(
    get_settings().database_url.startswith("sqlite"),
    reason="SQLite + StaticPool cannot serve concurrent writers; run against Postgres",
)
def test_concurrent_guide_requests_get_unique_refs():
    with Session(engine) as session:
        guide_id = session.exec(select(Guide)).first().id

    def book(_: int):
        return client.post(
            f"/api/v1/guides/{guide_id}/request", json={"hours": 2, "group_size": 2}
        )

    with ThreadPoolExecutor(max_workers=8) as pool:
        responses = list(pool.map(book, range(12)))

    assert all(r.status_code == 200 for r in responses)
    refs = {r.json()["booking_ref"] for r in responses}
    assert len(refs) == 12, "every booking needs a unique reference"


# ---------------------------------------------------------------------------
# 6.2 Auth edge cases
# ---------------------------------------------------------------------------


def test_logout_revokes_token():
    email = f"p6-{uuid.uuid4().hex[:8]}@localiq.test"
    registered = client.post(
        "/api/v1/auth/register",
        json={"name": "P6", "email": email, "password": "Strong123"},
    ).json()
    headers = {"Authorization": f"Bearer {registered['access_token']}"}

    assert client.get("/api/v1/auth/me", headers=headers).status_code == 200
    assert client.post("/api/v1/auth/logout", headers=headers).status_code == 200
    assert client.get("/api/v1/auth/me", headers=headers).status_code == 401


def test_invalid_token_is_rejected():
    response = client.get(
        "/api/v1/auth/me", headers={"Authorization": "Bearer not-a-real-token"}
    )
    assert response.status_code == 401
    assert response.json()["error"] == "HTTPException"
