"""Thin async client for the local Ollama server."""

from __future__ import annotations

import json

import httpx

from app.config import get_settings


class LLMError(RuntimeError):
    """Raised when the local LLM is unreachable or returns unusable output."""


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
            response = await client.post(url, json=payload)
            response.raise_for_status()
    except httpx.HTTPError as exc:
        raise LLMError(f"Ollama request failed: {exc}") from exc

    return response.json().get("response", "")


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
