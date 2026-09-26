"""Live context for the app: weather + heuristic traffic.

The Flutter client renders a context strip from ``WeatherSnapshot`` and
``TrafficSnapshot`` — camelCase keys, with ``condition`` limited to
``clear | cloudy | rain | storm | hot``. Our internal weather dict uses different
names and a finer condition taxonomy, so this module translates it.

Traffic is a deterministic heuristic (IST hour-of-day x weekday + a small
density nudge by area), not a live feed: it exists so the UI can show and use a
travel-time multiplier without a paid Traffic API.
"""

from __future__ import annotations

from datetime import datetime, timedelta, timezone
from typing import Any

from app.services.recommender import KNOWN_AREAS, haversine_km

#: Asia/Kolkata. Traffic bands are meaningful in local time.
IST = timezone(timedelta(hours=5, minutes=30))

_APP_CONDITION: dict[str, str] = {
    "clear": "clear",
    "partly_cloudy": "cloudy",
    "overcast": "cloudy",
    "cloudy": "cloudy",
    "fog": "cloudy",
    "drizzle": "rain",
    "rain": "rain",
    "storm": "storm",
    "hot": "hot",
    "unknown": "cloudy",
}


def app_condition(condition: str | None) -> str:
    """Map our condition vocabulary onto the app's enum."""
    return _APP_CONDITION.get((condition or "").strip().lower(), "cloudy")


def _num(value: Any, fallback: float) -> float:
    return round(float(value), 1) if isinstance(value, (int, float)) else fallback


def _iso(value: Any, fallback: datetime) -> str:
    return str(value) if value else fallback.isoformat()


def app_weather(
    weather: dict[str, Any] | None, *, now: datetime | None = None
) -> dict[str, Any]:
    """Translate our weather dict into the app's ``WeatherSnapshot`` shape."""
    data = weather or {}
    moment = now or datetime.now(IST)
    temp = _num(data.get("temp_c"), 28.0)
    feels = _num(data.get("feels_like_c"), temp)
    rainy = bool(data.get("is_rainy"))
    sunrise_default = moment.replace(hour=6, minute=30, second=0, microsecond=0)
    sunset_default = moment.replace(hour=18, minute=30, second=0, microsecond=0)
    return {
        "temperatureC": temp,
        "condition": app_condition(data.get("condition")),
        "apparentTemperatureC": feels,
        "humidity": int(data.get("humidity") or 70),
        "precipitationChance": int(
            data.get("precipitation_chance") or (60 if rainy else 20)
        ),
        "windKph": _num(data.get("wind_kph"), 12.0),
        "uvIndex": _num(data.get("uv_index"), 5.0),
        "observedAt": _iso(data.get("observed_at"), moment),
        "sunrise": _iso(data.get("sunrise"), sunrise_default),
        "sunset": _iso(data.get("sunset"), sunset_default),
    }


def _traffic_band(hour: int, weekday: int) -> tuple[str, float]:
    """(level, speed_multiplier) for an IST hour and weekday (Mon=0)."""
    weekend = weekday >= 5
    if hour < 6:
        return "light", 0.9
    if 7 <= hour <= 10:  # morning peak
        return ("moderate", 1.2) if weekend else ("heavy", 1.45)
    if 17 <= hour <= 21:  # evening peak
        if weekend:
            return "heavy", 1.45
        return ("severe", 1.8) if hour in (18, 19, 20) else ("heavy", 1.45)
    if 11 <= hour <= 16:
        return "moderate", 1.15
    return "light", 0.95  # 06:00 and 22:00-23:00


def _density_nudge(lat: float | None, lng: float | None) -> float:
    """Nudge the multiplier up slightly near a dense known area."""
    if lat is None or lng is None:
        return 0.0
    nearest = min(
        (haversine_km(lat, lng, alat, alng) for alat, alng in KNOWN_AREAS.values()),
        default=99.0,
    )
    return 0.05 if nearest <= 2.0 else 0.0


def app_traffic(
    *, lat: float | None = None, lng: float | None = None, now: datetime | None = None
) -> dict[str, Any]:
    """Heuristic ``TrafficSnapshot`` for a coordinate and moment."""
    moment = now or datetime.now(IST)
    level, multiplier = _traffic_band(moment.hour, moment.weekday())
    return {
        "level": level,
        "speedMultiplier": round(multiplier + _density_nudge(lat, lng), 2),
        "updatedAt": moment.isoformat(),
    }


def app_context(
    weather: dict[str, Any] | None,
    *,
    lat: float | None = None,
    lng: float | None = None,
    now: datetime | None = None,
) -> dict[str, Any]:
    """One payload for the app's combined ``/context/live`` call."""
    return {
        "weather": app_weather(weather, now=now),
        "traffic": app_traffic(lat=lat, lng=lng, now=now),
    }
