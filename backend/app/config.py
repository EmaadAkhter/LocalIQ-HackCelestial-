"""Application configuration loaded from environment / .env."""

from __future__ import annotations

from functools import lru_cache

from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    """Typed application settings. Env var names are case-insensitive."""

    model_config = SettingsConfigDict(env_file=".env", extra="ignore")

    # App
    app_env: str = "development"
    cors_origins: str = (
        "http://localhost:8080,http://localhost:3000,https://localiq.tavesglobal.com"
    )
    demo_mode: bool = False

    # Observability
    log_json: bool = True

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
    google_maps_api_key: str = ""

    # Caching (in-memory, per process)
    weather_cache_ttl_seconds: int = 600
    recommend_cache_enabled: bool = True
    recommend_cache_ttl_seconds: int = 60
    recommend_cache_maxsize: int = 256

    # Images: {seed} is replaced with a slug of the experience name.
    image_placeholder_url_template: str = "https://picsum.photos/seed/{seed}/800/600"

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


@lru_cache
def get_settings() -> Settings:
    """Return cached application settings."""
    return Settings()


settings = get_settings()
