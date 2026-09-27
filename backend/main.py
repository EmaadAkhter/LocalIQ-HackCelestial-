"""LocalIQ FastAPI Application Entry Point."""

import logging
from contextlib import asynccontextmanager
from pathlib import Path

from dotenv import load_dotenv
from fastapi import Depends, FastAPI, Request, Response
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import JSONResponse
from fastapi.staticfiles import StaticFiles
from slowapi.errors import RateLimitExceeded
from sqlalchemy import text
from sqlmodel import Session

load_dotenv()

from app.api.v1 import (  # noqa: E402
    admin,
    agent,
    auth,
    chat,
    config,
    conversations,
    director,
    discovery,
    driver,
    experiences,
    favorites,
    gems,
    groups,
    guide_onboarding,
    guide_packages,
    guides,
    guides_ops,
    itineraries,
    media,
    meetup,
    notifications,
    onboarding,
    parse,
    personalization,
    place_discovery,
    places,
    quests,
    recommendations,
    right_now,
    solo,
    tags,
    trust,
    twin,
    wallet,
    weather,
)
from app.config import get_settings  # noqa: E402
from app.database import get_session, init_db  # noqa: E402
import app.models_prd  # noqa: E402,F401  (registers PRD v2 tables)
from app.errors import error_response, register_exception_handlers  # noqa: E402
from app.logging_config import configure_logging  # noqa: E402
from app.metrics import init_metrics, metrics_payload  # noqa: E402
from app.middleware.access_log import AccessLogMiddleware  # noqa: E402
from app.migrations import upgrade_to_head  # noqa: E402
from app.middleware.request_id import RequestIDMiddleware  # noqa: E402
from app.rate_limit import limiter  # noqa: E402
from app.seed import generate_missing_embeddings, seed_if_empty  # noqa: E402
from app.services.llm import LLMError, close_http_client, generate, get_client  # noqa: E402

settings = get_settings()
configure_logging("INFO", json_output=settings.log_json and settings.app_env != "test")
logger = logging.getLogger("localiq")

if settings.metrics_enabled:
    init_metrics()


@asynccontextmanager
async def lifespan(app: FastAPI):
    logger.info("Starting LocalIQ backend...")
    try:
        if settings.app_env == "test":
            init_db()
        else:
            try:
                upgrade_to_head()
                logger.info("Database migrations applied")
            except Exception as exc:  # pragma: no cover - defensive
                logger.exception("Migrations failed; falling back to create_all: %s", exc)
                init_db()
        seeded = seed_if_empty()
        if seeded is not None:
            logger.info("Seeded %d experiences, %d guides", seeded["experiences"], seeded["guides"])
        logger.info("Database ready")
    except Exception as exc:
        logger.exception("Startup DB init failed: %s", exc)

    # Generate semantic embeddings for any experience that doesn't have one.
    # Runs in the background so startup isn't blocked; failures are logged only.
    if settings.app_env != "test":
        try:
            embedding_count = await generate_missing_embeddings()
            if embedding_count:
                logger.info("Generated embeddings for %d experiences on startup", embedding_count)
        except Exception as exc:  # pragma: no cover - defensive
            logger.exception("Startup embedding generation failed: %s", exc)

    # Warm the local model so the first real request is fast. Failure is fine.
    if settings.app_env != "test":
        try:
            await generate("ping", max_tokens=1, timeout=settings.llm_warm_timeout_seconds)
            logger.info("Warmed Ollama model: %s", settings.ollama_model)
        except LLMError as exc:
            logger.info("Ollama warm-up skipped (fallbacks active): %s", exc)

    yield
    logger.info("Shutting down LocalIQ backend...")
    await close_http_client()


app = FastAPI(
    title="LocalIQ API",
    version="0.2.0",
    description=(
        "Local-first Mumbai experience recommender with local storage, "
        "optional Ollama + Open-Meteo enhancements, and graceful fallbacks."
    ),
    lifespan=lifespan,
)


def _rate_limit_handler(request: Request, exc: RateLimitExceeded):
    return error_response(
        request, 429, "RateLimitExceeded", f"Rate limit exceeded: {exc.detail}"
    )


# --- Middleware (last added = outermost) -----------------------------------
# Limits are applied per route with @limiter.limit (see app/rate_limit.py).
app.state.limiter = limiter
app.add_middleware(AccessLogMiddleware)
app.add_middleware(RequestIDMiddleware)

_origins = settings.cors_origin_list
_allow_all = "*" in _origins
app.add_middleware(
    CORSMiddleware,
    allow_origins=_origins,
    allow_credentials=not _allow_all,
    allow_methods=["*"],
    allow_headers=["*"],
)

# --- Error handling --------------------------------------------------------
register_exception_handlers(app)
app.add_exception_handler(RateLimitExceeded, _rate_limit_handler)

# --- Curated experience images (static assets) -----------------------------
# The 48 curated experiences ship with locally hosted, freely-licensed photos so
# the demo looks complete even when the Google Places key is not configured.
# Google's photo proxy still takes priority at request time.
_IMAGE_DIR = Path(__file__).resolve().parent / "data" / "images"
if _IMAGE_DIR.is_dir():
    # Mounted at /static/images so a dataset value of "/static/images/x.jpg"
    # resolves to <data>/images/x.jpg.
    app.mount("/static/images", StaticFiles(directory=str(_IMAGE_DIR)), name="static-images")
    logger.info("Serving curated images from %s at /static/images", _IMAGE_DIR)

# --- Routes ----------------------------------------------------------------
# All v1 routers share /api/v1 so routes match the API contract:
# GET /api/v1/experiences, POST /api/v1/recommend, POST /api/v1/parse, ...
app.include_router(auth.router, prefix="/api/v1/auth", tags=["auth"])
app.include_router(config.router, prefix="/api/v1", tags=["config"])
app.include_router(places.router, prefix="/api/v1", tags=["places"])
# PRD v2 journeys (sections 4-6). Mounted under /api/v1 so the whole client
# surface is one base URL.
app.include_router(solo.router, prefix="/api/v1", tags=["journey-solo"])
app.include_router(meetup.router, prefix="/api/v1", tags=["journey-meetup"])
app.include_router(groups.router, prefix="/api/v1", tags=["journey-groups"])
app.include_router(quests.router, prefix="/api/v1", tags=["journey-quests"])
app.include_router(guides_ops.router, prefix="/api/v1", tags=["journey-guides"])
app.include_router(gems.router, prefix="/api/v1", tags=["journey-gems"])
app.include_router(trust.router, prefix="/api/v1", tags=["journey-trust"])

app.include_router(experiences.router, prefix="/api/v1", tags=["experiences"])
app.include_router(recommendations.router, prefix="/api/v1", tags=["recommendations"])
app.include_router(right_now.router, prefix="/api/v1", tags=["right-now"])
app.include_router(twin.router, prefix="/api/v1", tags=["twin"])
app.include_router(personalization.router, prefix="/api/v1", tags=["personalization"])
app.include_router(place_discovery.router, prefix="/api/v1", tags=["place-discovery"])
app.include_router(media.router, tags=["media"])
app.include_router(agent.router, prefix="/api/v1", tags=["agent"])
app.include_router(onboarding.router, prefix="/api/v1", tags=["onboarding"])
app.include_router(guide_onboarding.router, prefix="/api/v1", tags=["guide-onboarding"])
app.include_router(driver.router, prefix="/api/v1", tags=["driver"])
app.include_router(wallet.router, prefix="/api/v1", tags=["wallet"])
app.include_router(director.router, prefix="/api/v1", tags=["director"])
app.include_router(tags.router, prefix="/api/v1", tags=["tags"])
app.include_router(discovery.router, prefix="/api/v1", tags=["discovery"])
app.include_router(guides.router, prefix="/api/v1", tags=["guides"])
app.include_router(guide_packages.router, prefix="/api/v1", tags=["guide-packages"])
app.include_router(parse.router, prefix="/api/v1", tags=["parse"])
app.include_router(chat.router, prefix="/api/v1", tags=["chat"])
app.include_router(conversations.router, prefix="/api/v1", tags=["conversations"])
app.include_router(weather.router, prefix="/api/v1", tags=["weather"])
app.include_router(itineraries.router, prefix="/api/v1", tags=["itineraries"])
app.include_router(favorites.router, prefix="/api/v1", tags=["favorites"])
app.include_router(notifications.router, prefix="/api/v1", tags=["notifications"])
app.include_router(admin.router, prefix="/api/v1", tags=["admin"])


if settings.metrics_enabled:

    @app.get("/metrics", include_in_schema=False)
    async def metrics_endpoint():
        body, content_type = metrics_payload()
        return Response(content=body, media_type=content_type)


@app.get("/health", summary="Liveness check")
@app.get("/healthz", summary="Liveness check (alias)")
async def health_check():
    """Process is up. Does not touch dependencies."""
    return {"status": "ok"}


@app.get("/readyz", summary="Readiness check")
async def readyz(session: Session = Depends(get_session)):
    """Ready to serve traffic: database must answer.

    Ollama is reported but not required — the app degrades to heuristics.
    """
    checks = {"database": False, "ollama": False}
    try:
        session.execute(text("SELECT 1"))
        checks["database"] = True
    except Exception as exc:  # pragma: no cover - defensive
        logger.warning("Readiness: database check failed: %s", exc)

    try:
        health = await get_client().health()
        checks["ollama"] = bool(health.get("available"))
    except Exception as exc:  # pragma: no cover - defensive
        logger.warning("Readiness: ollama check failed: %s", exc)

    ready = checks["database"]
    return JSONResponse(
        status_code=200 if ready else 503,
        content={"status": "ready" if ready else "not_ready", "checks": checks},
    )
