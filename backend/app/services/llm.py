"""Ollama client for LocalIQ.

Three layers, all non-fatal:
  * ``OllamaClient`` — never raises; returns ``None`` on any failure so callers
    fall back to heuristics/canned text. This is what the routers use.
  * module-level ``generate`` / ``chat`` / ``generate_json`` + ``LLMError`` —
    raise-on-failure helpers used by the AI service modules.
  * ``_auth_headers`` — attaches the shared-LLM API key when the Ollama endpoint
    sits behind Kong key-auth (docker/tunnel setups).

Reliability comes from four things: one shared connection-pooled HTTP client,
retries with exponential backoff on transient failures, an in-memory TTL cache
for identical prompts, and per-endpoint timeouts.
"""

from __future__ import annotations

import asyncio
import hashlib
import json
import logging

import httpx

from app.config import get_settings
from app.services.cache import TTLCache

logger = logging.getLogger(__name__)

QUICK_TIMEOUT_S = 12.0
_RETRYABLE_STATUS = {429, 500, 502, 503, 504}
_RETRYABLE_EXC = (
    httpx.ConnectError,
    httpx.ConnectTimeout,
    httpx.ReadTimeout,
    httpx.WriteError,
    httpx.RemoteProtocolError,
    httpx.PoolTimeout,
)

_client: httpx.AsyncClient | None = None
_cache: TTLCache | None = None


class LLMError(RuntimeError):
    """Raised when the local LLM is unreachable or returns unusable output."""


# ---------------------------------------------------------------------------
# Shared HTTP client
# ---------------------------------------------------------------------------


def get_http_client() -> httpx.AsyncClient:
    """Return the shared connection-pooled client, creating it on first use."""
    global _client
    if _client is None or _client.is_closed:
        settings = get_settings()
        _client = httpx.AsyncClient(
            timeout=settings.ollama_timeout_seconds,
            limits=httpx.Limits(
                max_connections=settings.llm_http_max_connections,
                max_keepalive_connections=settings.llm_http_max_keepalive,
            ),
        )
    return _client


async def close_http_client() -> None:
    """Close the shared client (called on app shutdown)."""
    global _client
    if _client is not None and not _client.is_closed:
        await _client.aclose()
    _client = None


def _auth_headers() -> dict[str, str]:
    """Send the shared-LLM API key when one is configured (Kong key-auth)."""
    key = get_settings().ollama_api_key
    return {"apikey": key} if key else {}


# ---------------------------------------------------------------------------
# Response cache
# ---------------------------------------------------------------------------


def _get_cache() -> TTLCache | None:
    global _cache
    settings = get_settings()
    if not settings.llm_cache_enabled:
        return None
    if _cache is None:
        _cache = TTLCache(
            maxsize=settings.llm_cache_maxsize, ttl_seconds=settings.llm_cache_ttl_seconds
        )
    return _cache


def clear_llm_cache() -> None:
    """Drop cached responses (used by tests)."""
    if _cache is not None:
        _cache.clear()


def reset_llm_cache() -> None:
    """Discard the cache instance so it is rebuilt from current settings."""
    global _cache
    _cache = None


def cache_stats() -> dict[str, int]:
    return _cache.stats() if _cache is not None else {"size": 0, "hits": 0, "misses": 0}


def _cache_key(kind: str, model: str, payload: dict) -> str:
    blob = json.dumps(
        {"kind": kind, "model": model, "payload": payload}, sort_keys=True, default=str
    )
    return hashlib.sha256(blob.encode("utf-8")).hexdigest()


# ---------------------------------------------------------------------------
# HTTP with retries
# ---------------------------------------------------------------------------


async def _post_json(url: str, payload: dict, *, timeout: float) -> httpx.Response:
    """POST JSON with retries + exponential backoff on transient failures."""
    settings = get_settings()
    client = get_http_client()
    attempts = max(1, settings.llm_max_retries + 1)
    last_exc: Exception | None = None

    for attempt in range(attempts):
        try:
            response = await client.post(
                url, json=payload, timeout=timeout, headers=_auth_headers()
            )
            if response.status_code in _RETRYABLE_STATUS and attempt < attempts - 1:
                await asyncio.sleep(settings.llm_retry_backoff_seconds * (2**attempt))
                continue
            response.raise_for_status()
            return response
        except _RETRYABLE_EXC as exc:
            last_exc = exc
            if attempt < attempts - 1:
                await asyncio.sleep(settings.llm_retry_backoff_seconds * (2**attempt))
                continue
            raise

    if last_exc is not None:
        raise last_exc
    raise LLMError("LLM request failed")


# ---------------------------------------------------------------------------
# Client
# ---------------------------------------------------------------------------


class OllamaClient:
    """Reusable Ollama HTTP wrapper with graceful degradation."""

    def __init__(self, base_url: str | None = None, model: str | None = None):
        self.base_url = (base_url or get_settings().ollama_url).rstrip("/")
        self.model = model if model is not None else get_settings().ollama_model

    @property
    def configured(self) -> bool:
        return bool(self.model)

    async def health(self) -> dict:
        """Check Ollama availability + configured model. Never raises."""
        if not self.base_url:
            return {"available": False, "reason": "no_url"}
        try:
            response = await get_http_client().get(
                f"{self.base_url}/api/tags", timeout=QUICK_TIMEOUT_S, headers=_auth_headers()
            )
            if response.status_code != 200:
                return {"available": False, "reason": f"status_{response.status_code}"}
            data = response.json() if response.content else {}
            models = [m.get("name", "") for m in data.get("models", [])]
            has_model = (
                any(self.model in m or m in self.model for m in models) if self.model else True
            )
            return {
                "available": True,
                "model": self.model,
                "model_found": has_model,
                "models": models[:10],
            }
        except Exception as exc:
            logger.warning("Ollama health check failed: %s", exc)
            return {"available": False, "reason": "unreachable"}

    async def generate(
        self,
        prompt: str,
        system: str | None = None,
        *,
        json_mode: bool = False,
        timeout: float | None = None,
    ) -> str | None:
        """Generate text. Returns None when unavailable instead of raising."""
        if not self.configured:
            logger.info("Ollama model not configured; using deterministic fallback")
            return None

        payload: dict = {
            "model": self.model,
            "prompt": prompt,
            "stream": False,
            "options": {"temperature": 0.2, "num_predict": 600},
        }
        if system:
            payload["system"] = system
        if json_mode:
            payload["format"] = "json"

        cache = _get_cache()
        key = _cache_key(f"generate:{self.base_url}", self.model, payload)
        if cache is not None:
            cached = cache.get(key)
            if cached is not None:
                return cached

        try:
            response = await _post_json(
                f"{self.base_url}/api/generate",
                payload,
                timeout=timeout or get_settings().ollama_timeout_seconds,
            )
            text = (response.json().get("response") or "").strip() or None
        except Exception as exc:
            logger.warning("Ollama generate failed: %s", exc)
            return None

        if cache is not None and text is not None:
            cache.set(key, text)
        return text

    async def generate_json(
        self, prompt: str, system: str | None = None, *, timeout: float | None = None
    ) -> dict | None:
        """Generate + parse JSON. Returns None on any failure (caller falls back)."""
        text = await self.generate(prompt, system, json_mode=True, timeout=timeout)
        if not text:
            return None
        try:
            cleaned = text.strip()
            if cleaned.startswith("```"):
                cleaned = cleaned.strip("`")
                if cleaned.lower().startswith("json"):
                    cleaned = cleaned[4:].strip()
            return json.loads(cleaned)
        except (json.JSONDecodeError, ValueError) as exc:
            logger.warning("Ollama returned invalid JSON: %s | text=%.200s", exc, text)
            return None


def get_client() -> OllamaClient:
    return OllamaClient()


# ---------------------------------------------------------------------------
# Raising helpers (used by AI service modules)
# ---------------------------------------------------------------------------


async def generate(
    prompt: str,
    *,
    system: str | None = None,
    json_mode: bool = False,
    temperature: float = 0.1,
    max_tokens: int = 256,
    timeout: float | None = None,
) -> str:
    """Call Ollama's /api/generate and return the raw text response."""
    settings = get_settings()
    payload: dict = {
        "model": settings.ollama_model,
        "prompt": prompt,
        "stream": False,
        "options": {"temperature": temperature, "num_predict": max_tokens},
    }
    if system:
        payload["system"] = system
    if json_mode:
        payload["format"] = "json"

    url = f"{settings.ollama_url.rstrip('/')}/api/generate"
    try:
        response = await _post_json(
            url, payload, timeout=timeout or settings.ollama_timeout_seconds
        )
    except httpx.HTTPError as exc:
        raise LLMError(f"Ollama request failed: {exc}") from exc

    return response.json().get("response", "")


async def chat(
    messages: list[dict],
    *,
    temperature: float = 0.4,
    max_tokens: int = 300,
    timeout: float | None = None,
) -> str:
    """Call Ollama's multi-turn /api/chat and return the assistant text."""
    settings = get_settings()
    payload = {
        "model": settings.ollama_model,
        "messages": messages,
        "stream": False,
        "options": {"temperature": temperature, "num_predict": max_tokens},
    }

    url = f"{settings.ollama_url.rstrip('/')}/api/chat"
    try:
        response = await _post_json(
            url, payload, timeout=timeout or settings.ollama_timeout_seconds
        )
    except httpx.HTTPError as exc:
        raise LLMError(f"Ollama chat failed: {exc}") from exc

    return response.json().get("message", {}).get("content", "")


async def generate_json(prompt: str, *, timeout: float | None = None, **kwargs) -> dict:
    """Call Ollama in JSON mode and parse the response into a dict."""
    raw = await generate(prompt, json_mode=True, timeout=timeout, **kwargs)
    try:
        parsed = json.loads(raw)
    except json.JSONDecodeError as exc:
        raise LLMError(f"Model did not return valid JSON: {raw[:200]!r}") from exc
    if not isinstance(parsed, dict):
        raise LLMError(f"Expected a JSON object, got {type(parsed).__name__}")
    return parsed
