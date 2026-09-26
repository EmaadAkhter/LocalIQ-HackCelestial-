"""Weather API endpoints."""

from fastapi import APIRouter, Query

from app.schemas import WeatherResponse
from app.services.weather import MUMBAI_LAT, MUMBAI_LON, fetch_weather

router = APIRouter()


@router.get("/weather", response_model=WeatherResponse, summary="Current Mumbai weather")
async def get_weather(
    lat: float = Query(default=MUMBAI_LAT, ge=-90, le=90),
    lon: float = Query(default=MUMBAI_LON, ge=-180, le=180),
):
    """Normalized Open-Meteo response; never fails — falls back to neutral."""
    data = await fetch_weather(lat=lat, lon=lon)
    return WeatherResponse(
        available=data.get("available", False),
        temp_c=data.get("temp_c"),
        condition=data.get("condition", "unknown"),
        is_rainy=data.get("is_rainy", False),
        suitable_outdoor=data.get("suitable_outdoor", True),
        description=data.get("description", ""),
    )
