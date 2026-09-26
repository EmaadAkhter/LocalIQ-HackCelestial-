"""LocalIQ FastAPI Application Entry Point."""

from contextlib import asynccontextmanager

from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware

from app.api.v1 import chat, experiences, guides, parse, recommendations, weather
from app.config import get_settings
from app.services.llm import LLMError, generate


@asynccontextmanager
async def lifespan(app: FastAPI):
    """Warm the local model so the first real request is fast."""
    settings = get_settings()
    if settings.app_env != "test":
        try:
            await generate("ping", max_tokens=1, timeout=5)
            print(f"[localiq] warmed Ollama model: {settings.ollama_model}")
        except LLMError as exc:
            print(f"[localiq] Ollama warm-up skipped (fallbacks active): {exc}")
    yield


app = FastAPI(title="LocalIQ API", version="0.1.0", lifespan=lifespan)

settings = get_settings()
app.add_middleware(
    CORSMiddleware,
    allow_origins=settings.cors_origin_list,
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

app.include_router(experiences.router, prefix="/api/v1/experiences", tags=["experiences"])
app.include_router(recommendations.router, prefix="/api/v1/recommendations", tags=["recommendations"])
app.include_router(guides.router, prefix="/api/v1/guides", tags=["guides"])
app.include_router(parse.router, prefix="/api/v1/parse", tags=["parse"])
app.include_router(chat.router, prefix="/api/v1/chat", tags=["chat"])
app.include_router(weather.router, prefix="/api/v1/weather", tags=["weather"])


@app.get("/health")
async def health_check():
    """Health check endpoint."""
    return {"status": "ok"}
