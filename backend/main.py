"""LocalIQ FastAPI Application Entry Point."""

import logging
from contextlib import asynccontextmanager

from dotenv import load_dotenv
from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware

load_dotenv()

from app.api.v1 import auth, chat, experiences, guides, parse, recommendations, weather  # noqa: E402
from app.config import get_settings  # noqa: E402
from app.database import init_db  # noqa: E402
from app.services.llm import LLMError, generate  # noqa: E402

settings = get_settings()
logging.basicConfig(level=logging.INFO, format="%(levelname)s %(name)s: %(message)s")
logger = logging.getLogger("localiq")


@asynccontextmanager
async def lifespan(app: FastAPI):
    logger.info("Starting LocalIQ backend...")
    try:
        init_db()
        logger.info("Database ready")
    except Exception as exc:
        logger.exception("Startup DB init failed: %s", exc)

    # Warm the local model so the first real request is fast. Failure is fine.
    if settings.app_env != "test":
        try:
            await generate("ping", max_tokens=1, timeout=5)
            logger.info("Warmed Ollama model: %s", settings.ollama_model)
        except LLMError as exc:
            logger.info("Ollama warm-up skipped (fallbacks active): %s", exc)

    yield
    logger.info("Shutting down LocalIQ backend...")


app = FastAPI(
    title="LocalIQ API",
    version="0.1.0",
    description=(
        "Local-first Mumbai experience recommender with local SQLite storage, "
        "optional Ollama + Open-Meteo enhancements, and graceful fallbacks."
    ),
    lifespan=lifespan,
)

app.add_middleware(
    CORSMiddleware,
    allow_origins=settings.cors_origin_list,
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# All v1 routers share /api/v1 so routes match the API contract:
# GET /api/v1/experiences, POST /api/v1/recommend, POST /api/v1/parse, ...
app.include_router(auth.router, prefix="/api/v1/auth", tags=["auth"])
app.include_router(experiences.router, prefix="/api/v1", tags=["experiences"])
app.include_router(recommendations.router, prefix="/api/v1", tags=["recommendations"])
app.include_router(guides.router, prefix="/api/v1", tags=["guides"])
app.include_router(parse.router, prefix="/api/v1", tags=["parse"])
app.include_router(chat.router, prefix="/api/v1", tags=["chat"])
app.include_router(weather.router, prefix="/api/v1", tags=["weather"])


@app.get("/health", summary="Health check")
async def health_check():
    """Simple health endpoint for demos and monitoring."""
    return {"status": "ok"}
