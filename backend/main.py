"""LocalIQ FastAPI Application Entry Point."""

from fastapi import FastAPI

from app.api.v1 import experiences, recommendations, guides, parse, chat, weather

app = FastAPI(title="LocalIQ API", version="0.1.0")

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