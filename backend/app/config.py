"""Application configuration loaded from environment / .env."""

from __future__ import annotations

import logging
import os
from functools import lru_cache
from pathlib import Path

from pydantic_settings import BaseSettings, SettingsConfigDict

logger = logging.getLogger(__name__)

# Secrets that may be provided as files (Docker/K8s secrets):
#   DATABASE_URL_FILE=/run/secrets/database_url  -> DATABASE_URL
_SECRET_KEYS = ("DATABASE_URL", "AUTH_SECRET_KEY", "OLLAMA_API_KEY", "ADMIN_API_KEY", "S3_ACCESS_KEY", "S3_SECRET_KEY", "RESEND_API_KEY")


def _load_secret_files() -> None:
    """Populate ``<KEY>`` from ``<KEY>_FILE`` when present.

    An explicit environment value always wins, so file-based secrets are opt-in.
    """
    for key in _SECRET_KEYS:
        path = os.environ.get(f"{key}_FILE")
        if not path or os.environ.get(key):
            continue
        try:
            os.environ[key] = Path(path).read_text(encoding="utf-8").strip()
            logger.info("Loaded %s from %s", key, path)
        except OSError as exc:
            logger.warning("Could not read %s_FILE (%s): %s", key, path, exc)


class Settings(BaseSettings):
    """Typed application settings. Env var names are case-insensitive."""

    model_config = SettingsConfigDict(env_file=".env", extra="ignore")

    # App
    app_env: str = "development"
    cors_origins: str = (
        "http://localhost:8080,http://localhost:3000,https://localiq.tavesglobal.com"
    )
    demo_mode: bool = False
    #: Public origin used to build absolute URLs (images, email links) that must
    #: be reachable from outside the container network. Empty falls back to the
    #: incoming request's base URL, which is correct for a direct dev server but
    #: wrong behind a proxy (where the Host is an internal service name).
    public_base_url: str = ""

    # Email (Resend). Same integration shape as taves-website: a plain REST call
    # to api.resend.com, no SDK. An empty key disables sending, and the auth
    # endpoints keep their dev fallbacks so the app works without a provider.
    resend_api_key: str = ""
    #: Must be on a domain verified in Resend; onboarding@resend.dev works for
    #: testing until a domain is added.
    resend_from: str = "LocalIQ <onboarding@resend.dev>"
    #: Origin used in emailed links. Empty falls back to ``public_base_url``.
    app_public_url: str = ""
    email_verification_ttl_hours: int = 48
    #: Minimum gap between verification emails for one account.
    email_resend_cooldown_seconds: int = 60

    # Observability
    log_json: bool = True
    metrics_enabled: bool = True

    # Rate limiting (per client IP)
    rate_limit_enabled: bool = True

    # Login lockout
    login_max_attempts: int = 5
    login_lockout_minutes: int = 15

    # Database
    database_url: str = "sqlite:///./data/localiq.db"
    # Connection pool (Postgres/other; SQLite uses StaticPool and ignores these).
    db_pool_size: int = 5
    db_max_overflow: int = 10
    db_pool_recycle_seconds: int = 1800

    # Auth (local, self-hosted)
    auth_secret_key: str = "localiq-dev-secret-change-me"
    auth_token_ttl_minutes: int = 60 * 24 * 7
    # Refresh tokens outlive access tokens; the app exchanges one on cold start.
    auth_refresh_ttl_days: int = 30
    # Google Sign-In: when set, /auth/google verifies the ID token against
    # Google's tokeninfo endpoint. Empty falls back to dev-mode claim decoding.
    google_oauth_client_id: str = ""

    # Local LLM (Ollama)
    ollama_url: str = "http://localhost:11434"
    ollama_model: str = "llama3.2:3b"
    ollama_timeout_seconds: float = 30.0
    # API key for a shared/tunnelled Ollama behind Kong key-auth.
    ollama_api_key: str = ""

    # LLM robustness
    llm_parse_timeout_seconds: float = 20.0
    llm_chat_timeout_seconds: float = 30.0
    llm_warm_timeout_seconds: float = 5.0
    llm_max_retries: int = 2
    llm_retry_backoff_seconds: float = 0.5
    llm_cache_enabled: bool = True
    llm_cache_ttl_seconds: int = 300
    llm_cache_maxsize: int = 256
    llm_http_max_connections: int = 20
    llm_http_max_keepalive: int = 10

    # External services (optional)
    open_meteo_url: str = "https://api.open-meteo.com/v1/forecast"

    # Google Maps keys, one per platform. Keys are restricted per application in
    # the Google Cloud console, so each target needs its own key:
    #   GOOGLE_MAPS_API_KEY_WEB     -> Maps JavaScript API (Flutter web, Next.js)
    #   GOOGLE_MAPS_API_KEY_ANDROID -> Android app (package + SHA-1 restricted)
    #   GOOGLE_MAPS_API_KEY_IOS     -> iOS app (bundle id restricted)
    # The web key is served to browsers by GET /api/v1/config; the native keys are
    # injected into the native builds at compile time. None of them are committed.
    google_maps_api_key_web: str = ""
    google_maps_api_key_android: str = ""
    google_maps_api_key_ios: str = ""

    # --- Embeddings / semantic search (self-hosted) -------------------------
    embedding_model: str = "nomic-embed-text"
    embedding_dimension: int = 768
    embedding_batch_size: int = 16
    embedding_timeout_seconds: float = 30.0

    # --- SearXNG discovery pipeline (self-hosted) ---------------------------
    searxng_url: str = "http://localhost:8080"
    searxng_timeout_seconds: float = 30.0
    searxng_max_results: int = 10
    searxng_enabled: bool = True
    # Use the local LLM to extract structured candidates from scraped pages.
    # Falls back to the heuristic extractor when the model is unavailable.
    discovery_use_llm: bool = True
    discovery_llm_timeout_seconds: float = 45.0
    # Cap output tokens for extraction (JSON is small); keeps latency low.
    discovery_llm_num_predict: int = 384
    # Max pages to process per discovery run (LLM extraction is the bottleneck).
    discovery_max_results: int = 5
    # How many pages may hit the LLM concurrently. A single laptop Ollama
    # serializes generations, so >1 mostly causes queued requests to time out.
    discovery_llm_concurrency: int = 1
    discovery_max_candidates_per_page: int = 5
    # Page text is truncated to this many characters before prompting.
    discovery_page_chars: int = 2000

    # --- Geocoding (OpenStreetMap Nominatim; free, no key) ------------------
    geocode_enabled: bool = True
    geocode_base_url: str = "https://nominatim.openstreetmap.org/search"
    geocode_user_agent: str = "LocalIQBot/0.1 (+https://localiq.example.com)"
    geocode_timeout_seconds: float = 10.0
    # Nominatim usage policy: at most one request per second.
    geocode_min_interval_seconds: float = 1.1

    # --- Server-side Google APIs (never sent to any client) -----------------
    # These are *different* keys from the client map keys above: restrict them
    # by IP (and keep the Places/Routes APIs enabled) so they are useless if
    # leaked. They are only ever used inside this process.
    #   GOOGLE_PLACES_API_KEY -> Places API (New): search, nearby, photos
    #   GOOGLE_ROUTES_API_KEY  -> Routes API: travel time, distance, polyline
    # Leave empty to run fully offline on the SQLite dataset.
    google_places_api_key: str = ""
    google_routes_api_key: str = ""

    @property
    def google_maps_api_key(self) -> str:
        """Alias kept for callers that just want one Maps key."""
        return self.google_maps_api_key_web

    @property
    def google_server_keys_configured(self) -> bool:
        """True when at least one server-side Google key is present."""
        return bool(self.google_places_api_key.strip() or self.google_routes_api_key.strip())

    # Caching (in-memory, per process)
    weather_cache_ttl_seconds: int = 600
    recommend_cache_enabled: bool = True
    recommend_cache_ttl_seconds: int = 60
    recommend_cache_maxsize: int = 256
    # Google Places text/nearby search: repeated identical queries are common
    # (typing in the search box), so results are cached briefly.
    places_cache_enabled: bool = True
    places_cache_ttl_seconds: int = 120
    places_cache_maxsize: int = 128
    # Integration health probes: cached so /integrations/status never calls
    # Google on every request.
    integrations_cache_ttl_seconds: int = 300

    # LLM circuit breaker: after N consecutive connection failures, stop trying
    # for `cooldown` seconds and fall back immediately.
    llm_circuit_failure_threshold: int = 3
    llm_circuit_cooldown_seconds: float = 60.0

    # Images: {seed} is replaced with a slug of the experience name.
    image_placeholder_url_template: str = "https://picsum.photos/seed/{seed}/800/600"

    # Admin API (content management). Empty disables the admin endpoints.
    admin_api_key: str = ""

    # --- Object storage (S3-compatible: MinIO / s3mock) ---------------------
    # Self-hosted media store for experience photos and generated share cards.
    # When S3 is unreachable the storage service transparently falls back to the
    # filesystem, so local dev and the test suite never require a running store.
    s3_enabled: bool = True
    s3_endpoint: str = "http://localhost:9000"
    s3_access_key: str = "minioadmin"
    s3_secret_key: str = "minioadmin"
    s3_bucket: str = "localiq"
    s3_region: str = "us-east-1"
    s3_use_ssl: bool = False
    # "path" works with MinIO and s3mock (and most non-AWS endpoints).
    s3_addressing_style: str = "path"
    # Public base for object URLs (e.g. a CDN). Empty -> serve via /media/{key}.
    s3_public_base_url: str = ""
    # Filesystem fallback root when S3 is disabled or unreachable.
    media_root: str = "./data/media"

    # Google Places photo enrichment: download the first place photo and store
    # it in object storage so cards are self-hosted.
    photo_enrich_enabled: bool = True
    photo_max_width_px: int = 1200

    # Ranking: weight applied to aggregated user feedback (score in -1..1).
    feedback_weight: float = 4.0

    @property
    def cors_origin_list(self) -> list[str]:
        return [origin.strip() for origin in self.cors_origins.split(",") if origin.strip()]

    @property
    def open_meteo_base_url(self) -> str:
        """Alias kept for the weather service."""
        return self.open_meteo_url

    @property
    def rate_limiting_on(self) -> bool:
        """Rate limiting is disabled in tests so the suite is never throttled."""
        return self.rate_limit_enabled and self.app_env != "test"

    @property
    def email_enabled(self) -> bool:
        """True when a Resend API key is configured."""
        return bool(self.resend_api_key.strip())

    @property
    def app_public_origin(self) -> str:
        """Origin used to build links for email (never has a trailing slash)."""
        origin = (self.app_public_url or self.public_base_url).strip()
        return (origin or "http://localhost:8080").rstrip("/")


@lru_cache
def get_settings() -> Settings:
    """Return cached application settings."""
    _load_secret_files()
    return Settings()


settings = get_settings()
