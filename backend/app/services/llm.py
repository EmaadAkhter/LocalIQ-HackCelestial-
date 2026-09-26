"""Ollama client for LocalIQ.

Three layers, all non-fatal:
  * ``OllamaClient`` — never raises; returns ``None`` on any failure so callers
    fall back to heuristics/canned text. This is what the routers use.
  * module-level ``generate`` / ``chat`` / ``generate_json`` + ``LLMError`` —
    raise-on-failure helpers used by the AI service modules.
  * ``_auth_headers`` — attaches the shared-LLM API key when the Ollama endpoint
    sits behind Kong key-auth (docker/tunnel setups).
"""

from __future__ import annotations

import json
import logging

import httpx

from app.config import get_settings

logger = logging.getLogger(__name__)

GENERATE_TIMEOUT_S = 25.0
QUICK_TIMEOUT_S = 12.0


class LLMError(RuntimeError):
    """Raised when the local LLM is unreachable or returns unusable output."""


def _auth_headers() -> dict[str, str]:
    """Send the shared-LLM API key when one is configured (Kong key-auth)."""
    key = get_settings().ollama_api_key
    return {"apikey": key} if key else {}


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
            async with httpx.AsyncClient(timeout=QUICK_TIMEOUT_S) as client:
                resp = await client.get(f"{self.base_url}/api/tags", headers=_auth_headers())
                if resp.status_code != 200:
                    return {"available": False, "reason": f"status_{resp.status_code}"}
                data = resp.json() if resp.content else {}
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
        timeout: float = GENERATE_TIMEOUT_S,
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
        try:
            async with httpx.AsyncClient(timeout=timeout) as client:
                resp = await client.post(
                    f"{self.base_url}/api/generate", json=payload, headers=_auth_headers()
                )
                resp.raise_for_status()
                data = resp.json()
                text = (data.get("response") or "").strip()
                return text or None
        except Exception as exc:
            logger.warning("Ollama generate failed: %s", exc)
            return None

    async def generate_json(self, prompt: str, system: str | None = None) -> dict | None:
        """Generate + parse JSON. Returns None on any failure (caller falls back)."""
        text = await self.generate(prompt, system, json_mode=True)
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
# Raising helpers (used by services/parser.py and services/guide.py)
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
        async with httpx.AsyncClient(timeout=timeout or settings.ollama_timeout_seconds) as client:
            response = await client.post(url, json=payload, headers=_auth_headers())
            response.raise_for_status()
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
        async with httpx.AsyncClient(timeout=timeout or settings.ollama_timeout_seconds) as client:
            response = await client.post(url, json=payload, headers=_auth_headers())
            response.raise_for_status()
    except httpx.HTTPError as exc:
        raise LLMError(f"Ollama chat failed: {exc}") from exc

    return response.json().get("message", {}).get("content", "")


async def generate_json(prompt: str, **kwargs) -> dict:
    """Call Ollama in JSON mode and parse the response into a dict."""
    raw = await generate(prompt, json_mode=True, **kwargs)
    try:
        parsed = json.loads(raw)
    except json.JSONDecodeError as exc:
        raise LLMError(f"Model did not return valid JSON: {raw[:200]!r}") from exc
    if not isinstance(parsed, dict):
        raise LLMError(f"Expected a JSON object, got {type(parsed).__name__}")
    return parsed
