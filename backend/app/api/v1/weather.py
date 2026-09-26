"""Weather + live-context API endpoints for the app.

    GET /weather?lat=&lng=        -> flat snapshot (also ``lon`` for legacy)
    GET /traffic?lat=&lng=        -> { traffic: {...} }
    GET /context/live?lat=&lng=   -> { weather: {...}, traffic: {...} }

All three degrade gracefully: weather comes from Open-Meteo with a neutral
fallback, traffic is a deterministic IST hour-of-day heuristic.
"""

from fastapi import APIRouter, Query, Request, Response

from app.rate_limit import PUBLIC_LIMIT, limiter
from app.schemas import WeatherResponse
from app.services import context as context_service
from app.services.weather import MUMBAI_LAT, MUMBAI_LON, fetch_weather

router = APIRouter()


@router.get("/weather", response_model=WeatherResponse, summary="Current weather")
@limiter.limit(PUBLIC_LIMIT)
async def get_weather(
    request: Request,
    response: Response,
    lat: float = Query(default=MUMBAI_LAT, ge=-90, le=90),
    lng: float | None = Query(default=None, ge=-180, le=180),
    lon: float = Query(default=MUMBAI_LON, ge=-180, le=180),
):
    """Normalized Open-Meteo response; never fails — falls back to neutral."""
    longitude = lng if lng is not None else lon
    data = await fetch_weather(lat=lat, lon=longitude)
    app = context_service.app_weather(data)
    return WeatherResponse(
        available=bool(data.get("available", False)),
        temp_c=data.get("temp_c"),
        condition=app["condition"],
        is_rainy=bool(data.get("is_rainy", False)),
        suitable_outdoor=bool(data.get("suitable_outdoor", True)),
        description=str(data.get("description", "")),
        temperature_c=app["temperatureC"],
        apparent_temperature_c=app["apparentTemperatureC"],
        humidity=app["humidity"],
        precipitation_chance=app["precipitationChance"],
        wind_kph=app["windKph"],
        uv_index=app["uvIndex"],
        observed_at=app["observedAt"],
        sunrise=app["sunrise"],
        sunset=app["sunset"],
    )


@router.get("/traffic", summary="Heuristic traffic for a point")
@limiter.limit(PUBLIC_LIMIT)
def get_traffic(
    request: Request,
    response: Response,
    lat: float | None = Query(default=None, ge=-90, le=90),
    lng: float | None = Query(default=None, ge=-180, le=180),
):
    return {"traffic": context_service.app_traffic(lat=lat, lng=lng)}


@router.get("/context/live", summary="Weather + traffic in one call")
@limiter.limit(PUBLIC_LIMIT)
async def live_context(
    request: Request,
    response: Response,
    lat: float = Query(default=MUMBAI_LAT, ge=-90, le=90),
    lng: float | None = Query(default=None, ge=-180, le=180),
    lon: float = Query(default=MUMBAI_LON, ge=-180, le=180),
):
    longitude = lng if lng is not None else lon
    data = await fetch_weather(lat=lat, lon=longitude)
    return context_service.app_context(data, lat=lat, lng=longitude)
