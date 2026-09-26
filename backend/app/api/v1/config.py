"""Public client configuration.

Clients (Flutter web / Android / iOS, Next.js) need a handful of settings that
must never be hardcoded in the app binary. The backend is the single source of
truth: it reads them from its own environment and hands out only what is safe
to expose publicly.
"""

from fastapi import APIRouter
from pydantic import BaseModel, Field

from app.config import get_settings

router = APIRouter()


class ClientConfig(BaseModel):
    """Everything a client needs to boot, sourced from the backend."""

    google_maps_api_key: str = Field(
        default="",
        description="Maps JavaScript API key. Empty means maps stay offline.",
    )
    maps_enabled: bool = Field(
        default=False,
        description="True when a Google Maps key is configured on the backend.",
    )
    open_meteo_enabled: bool = Field(
        default=True,
        description="True when weather lookups are configured.",
    )


@router.get("/config", response_model=ClientConfig, summary="Public client config")
async def get_client_config() -> ClientConfig:
    """Serve the browser-safe config.

    Only the Maps JavaScript key is returned: it is already public by design
    (HTTP referrer restricted in the Google Cloud console). The Android and iOS
    keys are deliberately not served here - they are baked into the native
    builds by the release scripts.
    """
    settings = get_settings()
    key = settings.google_maps_api_key_web.strip()
    return ClientConfig(
        google_maps_api_key=key,
        maps_enabled=bool(key),
        open_meteo_enabled=bool(settings.open_meteo_url.strip()),
    )
