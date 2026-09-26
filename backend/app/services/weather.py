"""Weather service for LocalIQ (Open-Meteo, graceful fallback + TTL cache)."""

import logging

import httpx

from app.config import settings
from app.services.cache import TTLCache

logger = logging.getLogger(__name__)

MUMBAI_LAT = 19.0760
MUMBAI_LON = 72.8777
TIMEOUT_S = 8.0

# Weather changes slowly; one upstream call per coordinate per TTL is plenty.
_weather_cache = TTLCache(maxsize=64, ttl_seconds=settings.weather_cache_ttl_seconds)


def clear_weather_cache() -> None:
    """Drop cached weather (used by tests)."""
    _weather_cache.clear()


def weather_cache_stats() -> dict[str, int]:
    return _weather_cache.stats()


def neutral_weather(reason: str = "unavailable") -> dict:
    """Neutral context so recommendations never fail without weather."""
    return {
        "available": False,
        "temp_c": None,
        "condition": "unknown",
        "is_rainy": False,
        "suitable_outdoor": True,
        "description": f"Weather unavailable ({reason}); showing all indoor/outdoor options.",
        "reason": reason,
    }


def _weathercode_to_condition(code: int | None) -> tuple[str, bool]:
    """Map Open-Meteo weathercode to (condition, is_rainy)."""
    if code is None:
        return "unknown", False
    if code in (0, 1):
        return "clear", False
    if code == 2:
        return "partly_cloudy", False
    if code == 3:
        return "overcast", False
    if code in (45, 48):
        return "fog", False
    if code in (51, 53, 55, 56, 57, 80, 81, 82):
        return "drizzle", True
    if code in (61, 63, 65, 66, 67, 95, 96, 99):
        return "rain", True
    if code in (71, 73, 75, 77, 85, 86):
        return "rain", True
    return "cloudy", False


async def _fetch_weather_live(lat: float, lon: float) -> dict:
    """Fetch current weather from Open-Meteo. Never raises."""
    url = settings.open_meteo_base_url
    params = {
        "latitude": lat,
        "longitude": lon,
        "current": "temperature_2m,relative_humidity_2m,apparent_temperature,weathercode,rain",
        "timezone": "Asia/Kolkata",
    }
    try:
        async with httpx.AsyncClient(timeout=TIMEOUT_S) as client:
            resp = await client.get(url, params=params)
            resp.raise_for_status()
            data = resp.json()
    except Exception as exc:
        logger.warning("Weather fetch failed: %s", exc)
        return neutral_weather(reason="fetch_failed")

    try:
        current = data.get("current", {}) or {}
        temp = current.get("temperature_2m")
        code = current.get("weathercode")
        rain = float(current.get("rain", 0) or 0)
        condition, is_rainy = _weathercode_to_condition(code)
        if rain and rain > 0.2:
            is_rainy = True
            condition = "rain"
        suitable = not is_rainy and condition not in ("storm",)
        desc = f"{condition.replace('_', ' ').title()}, {temp}°C" if temp is not None else condition
        return {
            "available": True,
            "temp_c": temp,
            "humidity": current.get("relative_humidity_2m"),
            "feels_like_c": current.get("apparent_temperature"),
            "condition": condition,
            "weathercode": code,
            "is_rainy": is_rainy,
            "suitable_outdoor": suitable,
            "description": desc,
            "lat": lat,
            "lon": lon,
        }
    except Exception as exc:
        logger.warning("Weather parse failed: %s", exc)
        return neutral_weather(reason="parse_failed")


async def fetch_weather(lat: float = MUMBAI_LAT, lon: float = MUMBAI_LON) -> dict:
    """Current weather, cached per coordinate for the configured TTL.

    Only successful responses are cached; failures fall back to neutral values
    and are retried on the next call.
    """
    key = f"{lat:.4f},{lon:.4f}"
    cached = _weather_cache.get(key)
    if cached is not None:
        return cached

    data = await _fetch_weather_live(lat, lon)
    if data.get("available"):
        _weather_cache.set(key, data)
    return data
