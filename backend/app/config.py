"""Application configuration loaded from environment / .env."""

from __future__ import annotations

from functools import lru_cache

from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    """Typed application settings. Env var names are case-insensitive."""

    model_config = SettingsConfigDict(env_file=".env", extra="ignore")

    # App
    app_env: str = "development"
    cors_origins: str = "http://localhost:3000"
    demo_mode: bool = False

    # Database
    database_url: str = "sqlite:///./data/localiq.db"

    # Auth (local, self-hosted)
    auth_secret_key: str = "localiq-dev-secret-change-me"
    auth_token_ttl_minutes: int = 60 * 24 * 7

    # Local LLM (Ollama)
    ollama_url: str = "http://localhost:11434"
    ollama_model: str = "llama3.2:3b"
    ollama_timeout_seconds: float = 30.0
    # API key for a shared/tunnelled Ollama behind Kong key-auth.
    ollama_api_key: str = ""
    # Set when using a shared/tunnelled Ollama behind Kong key-auth.
    ollama_api_key: str = ""

    # External services (optional)
    open_meteo_url: str = "https://api.open-meteo.com/v1/forecast"
    google_maps_api_key: str = ""

    @property
    def cors_origin_list(self) -> list[str]:
        return [origin.strip() for origin in self.cors_origins.split(",") if origin.strip()]

    @property
    def open_meteo_base_url(self) -> str:
        """Alias kept for the weather service."""
        return self.open_meteo_url


@lru_cache
def get_settings() -> Settings:
    """Return cached application settings."""
    return Settings()


settings = get_settings()
