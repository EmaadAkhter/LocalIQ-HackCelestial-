"""Weather Digital Twin endpoints.

    GET  /twin/state     -> current twin state, driven by live weather
    POST /twin/simulate  -> what-if scenario (rain intensity, duration, flood)

The twin is a simulation layer over the existing experience graph: it scores
each experience's weather suitability and each area's flood/movement risk, then
reports the cascading effects. South Mumbai is the pilot; any area in
`recommender.KNOWN_AREAS` is scored, so Bandra/Colaba already work.
"""

from fastapi import APIRouter, Depends, Query, Request, Response
from pydantic import BaseModel, Field
from sqlmodel import Session

from app.database import get_session
from app.rate_limit import PUBLIC_LIMIT, limiter
from app.services import twin
from app.services.weather import MUMBAI_LAT, MUMBAI_LON, fetch_weather

router = APIRouter()


class SimulateRequest(BaseModel):
    """What-if knobs. Defaults reproduce a typical monsoon downpour."""

    rain_level: str = Field(default="heavy", pattern="^(none|light|heavy|storm)$")
    duration_hours: float = Field(default=2.0, ge=0.5, le=12.0)
    flood_multiplier: float = Field(default=1.0, ge=0.5, le=2.0)
    heat_level: str | None = Field(default=None, pattern="^(normal|hot|extreme)$")
    lat: float = Field(default=MUMBAI_LAT, ge=-90, le=90)
    lng: float = Field(default=MUMBAI_LON, ge=-180, le=180)
    radius_km: float = Field(default=8.0, ge=1.0, le=30.0)


@router.get("/twin/state", summary="Current weather-driven twin state")
@limiter.limit(PUBLIC_LIMIT)
async def twin_state(
    request: Request,
    response: Response,
    lat: float = Query(default=MUMBAI_LAT, ge=-90, le=90),
    lng: float = Query(default=MUMBAI_LON, ge=-180, le=180),
    radius_km: float = Query(default=8.0, ge=1.0, le=30.0),
    session: Session = Depends(get_session),
):
    """Score every nearby experience and area from the live weather right now."""
    weather = await fetch_weather(lat=lat, lon=lng)
    return twin.build_state(
        session, lat=lat, lng=lng, radius_km=radius_km, weather=weather
    )


@router.post("/twin/simulate", summary="Run a what-if weather scenario")
@limiter.limit(PUBLIC_LIMIT)
async def twin_simulate(
    request: Request,
    response: Response,
    payload: SimulateRequest,
    session: Session = Depends(get_session),
):
    """Apply a weather scenario and return the reshaped experience ecosystem."""
    weather = await fetch_weather(lat=payload.lat, lon=payload.lng)
    return twin.build_state(
        session,
        lat=payload.lat,
        lng=payload.lng,
        radius_km=payload.radius_km,
        rain_level=payload.rain_level,
        duration_hours=payload.duration_hours,
        flood_multiplier=payload.flood_multiplier,
        heat_level=payload.heat_level,
        weather=weather,
    )
