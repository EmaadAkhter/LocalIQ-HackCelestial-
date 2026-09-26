"""Phase 1 hardening tests: errors, request ids, logging, rate limits,
readiness, CORS, password policy and login lockout.
"""

import io
import json
import logging
import uuid

from fastapi import FastAPI, Request, Response
from fastapi.responses import JSONResponse
from fastapi.testclient import TestClient
from pythonjsonlogger.json import JsonFormatter
from slowapi.errors import RateLimitExceeded
from slowapi.middleware import SlowAPIMiddleware

from app.logging_config import _RequestIDFilter
from app.rate_limit import create_limiter
from app.services import lockout
from main import app

client = TestClient(app)


# ---------------------------------------------------------------------------
# 1.1 Unified error schema
# ---------------------------------------------------------------------------


def test_error_schema_validation():
    r = client.post("/api/v1/parse", json={})
    assert r.status_code == 422
    body = r.json()
    assert body["error"] == "ValidationError"
    assert body["status_code"] == 422
    assert body["request_id"]
    assert body["path"].endswith("/parse")
    assert body["details"]


def test_error_schema_404():
    r = client.get("/api/v1/experiences/999999")
    assert r.status_code == 404
    body = r.json()
    assert body["error"] == "HTTPException"
    assert body["message"]
    assert body["status_code"] == 404
    assert body["path"].endswith("/999999")


# ---------------------------------------------------------------------------
# 1.2 Request ID
# ---------------------------------------------------------------------------


def test_request_id_header_returned():
    r = client.get("/health")
    assert r.status_code == 200
    assert r.headers.get("x-request-id")


def test_request_id_header_preserved():
    r = client.get("/health", headers={"X-Request-ID": "trace-abc-123"})
    assert r.headers["x-request-id"] == "trace-abc-123"


# ---------------------------------------------------------------------------
# 1.3 Structured logging
# ---------------------------------------------------------------------------


def test_json_log_line_is_valid_json():
    stream = io.StringIO()
    handler = logging.StreamHandler(stream)
    handler.setFormatter(
        JsonFormatter(
            "%(asctime)s %(levelname)s %(name)s %(message)s %(request_id)s",
            rename_fields={"asctime": "timestamp", "levelname": "level", "name": "logger"},
        )
    )
    handler.addFilter(_RequestIDFilter())

    logger = logging.getLogger("localiq.test.json")
    logger.handlers.clear()
    logger.addHandler(handler)
    logger.propagate = False
    logger.setLevel(logging.INFO)

    logger.info(
        "hello",
        extra={"method": "GET", "path": "/x", "status_code": 200, "duration_ms": 1.5},
    )

    data = json.loads(stream.getvalue().strip())
    assert data["message"] == "hello"
    assert data["level"] == "INFO"
    assert data["method"] == "GET"
    assert data["status_code"] == 200
    assert "request_id" in data


# ---------------------------------------------------------------------------
# 1.4 Rate limiting
# ---------------------------------------------------------------------------


def test_rate_limit_returns_429():
    limiter = create_limiter(enabled=True)
    test_app = FastAPI()
    test_app.state.limiter = limiter
    test_app.add_middleware(SlowAPIMiddleware)

    @test_app.exception_handler(RateLimitExceeded)
    async def _handler(request: Request, exc: RateLimitExceeded):
        return JSONResponse(status_code=429, content={"error": "RateLimitExceeded"})

    @test_app.get("/limited")
    @limiter.limit("2/minute")
    async def limited(request: Request, response: Response):
        return {"ok": True}

    c = TestClient(test_app)
    assert c.get("/limited").status_code == 200
    assert c.get("/limited").status_code == 200
    assert c.get("/limited").status_code == 429


# ---------------------------------------------------------------------------
# 1.5 Readiness
# ---------------------------------------------------------------------------


def test_readyz_reports_database():
    r = client.get("/readyz")
    assert r.status_code == 200
    body = r.json()
    assert body["status"] == "ready"
    assert body["checks"]["database"] is True
    assert "ollama" in body["checks"]


# ---------------------------------------------------------------------------
# 1.6 CORS
# ---------------------------------------------------------------------------


def test_cors_allows_known_origin():
    r = client.get(
        "/api/v1/experiences?limit=1",
        headers={"Origin": "https://localiq.tavesglobal.com"},
    )
    assert r.headers.get("access-control-allow-origin") == "https://localiq.tavesglobal.com"


def test_cors_rejects_unknown_origin():
    r = client.get(
        "/api/v1/experiences?limit=1",
        headers={"Origin": "https://evil.example.com"},
    )
    assert "access-control-allow-origin" not in r.headers


# ---------------------------------------------------------------------------
# 1.7 Password policy
# ---------------------------------------------------------------------------


def test_password_too_weak():
    email = f"weak-{uuid.uuid4().hex[:8]}@localiq.test"
    r = client.post(
        "/api/v1/auth/register",
        json={"name": "Weak User", "email": email, "password": "weakpass"},
    )
    assert r.status_code == 422
    assert r.json()["error"] == "ValidationError"


def test_password_strong_accepted():
    email = f"strong-{uuid.uuid4().hex[:8]}@localiq.test"
    r = client.post(
        "/api/v1/auth/register",
        json={"name": "Strong User", "email": email, "password": "Strong123"},
    )
    assert r.status_code == 201, r.text


# ---------------------------------------------------------------------------
# 1.8 Login lockout
# ---------------------------------------------------------------------------


def test_login_lockout_after_five_failures():
    lockout.reset()
    email = f"lock-{uuid.uuid4().hex[:8]}@localiq.test"
    payload = {"email": email, "password": "Wrong123"}

    for _ in range(5):
        r = client.post("/api/v1/auth/login", json=payload)
        assert r.status_code == 401, r.text

    locked = client.post("/api/v1/auth/login", json=payload)
    assert locked.status_code == 403
    assert "locked" in locked.json()["message"].lower()

    lockout.reset()
