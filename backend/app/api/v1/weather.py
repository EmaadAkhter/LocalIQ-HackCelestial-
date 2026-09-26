"""Weather API endpoints."""

from fastapi import APIRouter

router = APIRouter()


@router.get("/")
async def get_weather():
    """Get current weather."""
    return {}