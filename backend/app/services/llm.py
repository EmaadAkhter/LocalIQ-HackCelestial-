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
import time
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
_client_loop: asyncio.AbstractEventLoop | None = None
_cache: TTLCache | None = None


class LLMError(RuntimeError):
    """Raised when the local LLM is unreachable or returns unusable output."""


# ---------------------------------------------------------------------------
# Shared HTTP client
# ---------------------------------------------------------------------------


def get_http_client() -> httpx.AsyncClient:
    """Return the shared connection-pooled client, creating it on first use.

    The client is bound to the event loop that created it. If the running loop
    has changed (e.g. successive ``asyncio.run`` calls in tests) the stale
    client is discarded and a fresh one is built, so we never await a client
    tied to an already-closed loop.
    """
    global _client, _client_loop
    try:
        loop: asyncio.AbstractEventLoop | None = asyncio.get_running_loop()
    except RuntimeError:
        loop = None
    if (
        _client is None
        or _client.is_closed
        or (_client_loop is not None and _client_loop is not loop)
    ):
        settings = get_settings()
        _client = httpx.AsyncClient(
            timeout=settings.ollama_timeout_seconds,
            limits=httpx.Limits(
                max_connections=settings.llm_http_max_connections,
                max_keepalive_connections=settings.llm_http_max_keepalive,
            ),
        )
        _client_loop = loop
    return _client


async def close_http_client() -> None:
    """Close the shared client (called on app shutdown)."""
    global _client, _client_loop
    if _client is not None and not _client.is_closed:
        await _client.aclose()
    _client = None
    _client_loop = None


def _auth_headers() -> dict[str, str]:
    """Attach the LLM key when one is configured.

    Local deployments sit behind Kong key-auth and read ``apikey``; Ollama
    Cloud reads a standard ``Authorization: Bearer`` header. Sending both keeps
    one code path working for either endpoint.
    """
    key = get_settings().ollama_api_key
    if not key:
        return {}
    return {"apikey": key, "Authorization": f"Bearer {key}"}


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


class _CircuitBreaker:
    """Stop hammering an unreachable local LLM.

    Without this, every ``/chat`` or ``/parse`` request pays the full retry
    ladder (3 attempts + exponential backoff) even though Ollama is simply not
    running — an ~8s freeze per click during a demo. After `threshold`
    consecutive connection failures the breaker opens for `cooldown` seconds and
    short-circuits to the caller's fallback immediately. A single success closes
    it again, so normal behaviour is restored as soon as Ollama comes back.
    """

    def __init__(self, threshold: int, cooldown_seconds: float) -> None:
        self.threshold = max(1, threshold)
        self.cooldown_seconds = max(0.0, cooldown_seconds)
        self.failures = 0
        self.opened_at: float | None = None

    @property
    def is_open(self) -> bool:
        if self.opened_at is None:
            return False
        if (time.monotonic() - self.opened_at) >= self.cooldown_seconds:
            # Cooldown elapsed: half-open and let the next call try again.
            self.opened_at = None
            self.failures = 0
            return False
        return True

    def record_failure(self) -> None:
        self.failures += 1
        if self.failures >= self.threshold and self.opened_at is None:
            self.opened_at = time.monotonic()
            logger.warning(
                "LLM circuit opened after %d failures; skipping calls for %.0fs",
                self.failures,
                self.cooldown_seconds,
            )

    def record_success(self) -> None:
        if self.failures or self.opened_at is not None:
            logger.info("LLM circuit closed; local model is reachable again")
        self.failures = 0
        self.opened_at = None

    def state(self) -> dict[str, object]:
        remaining = 0.0
        if self.opened_at is not None:
            remaining = max(0.0, self.cooldown_seconds - (time.monotonic() - self.opened_at))
        return {
            "open": self.is_open,
            "consecutive_failures": self.failures,
            "threshold": self.threshold,
            "cooldown_remaining_s": round(remaining, 1),
        }

    def reset(self) -> None:
        self.failures = 0
        self.opened_at = None


_circuit = _CircuitBreaker(
    get_settings().llm_circuit_failure_threshold,
    get_settings().llm_circuit_cooldown_seconds,
)


def circuit_state() -> dict[str, object]:
    """Introspection for tests and the status endpoints."""
    return _circuit.state()


def reset_circuit() -> None:
    """Force the breaker closed (used by tests and manual recovery)."""
    _circuit.reset()



async def _post_json(
    url: str, payload: dict, *, timeout: float, attempts_override: int | None = None
) -> httpx.Response:
    """POST JSON with retries + exponential backoff on transient failures.

    ``attempts_override`` lets latency-sensitive callers (e.g. batch discovery
    extraction) make a single attempt instead of the default retry budget.
    """
    settings = get_settings()
    client = get_http_client()
    attempts = max(1, attempts_override if attempts_override is not None else settings.llm_max_retries + 1)
    last_exc: Exception | None = None

    # Fast path: the local LLM is known to be down, so skip the retry ladder and
    # let the caller fall back to its heuristic/canned response immediately.
    if _circuit.is_open:
        logger.info("LLM circuit open; skipping call and falling back")
        raise LLMError("local LLM unavailable (circuit open)")

    for attempt in range(attempts):
        try:
            response = await client.post(
                url, json=payload, timeout=timeout, headers=_auth_headers()
            )
            if response.status_code in _RETRYABLE_STATUS and attempt < attempts - 1:
                await asyncio.sleep(settings.llm_retry_backoff_seconds * (2**attempt))
                continue
            response.raise_for_status()
            _circuit.record_success()
            return response
        except _RETRYABLE_EXC as exc:
            last_exc = exc
            if attempt < attempts - 1:
                await asyncio.sleep(settings.llm_retry_backoff_seconds * (2**attempt))
                continue
            # Last attempt: count the failure *before* re-raising, otherwise the
            # breaker never sees connection errors and the freeze persists.
            _circuit.record_failure()
            raise

    if last_exc is not None:
        _circuit.record_failure()
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
        num_predict: int | None = None,
        attempts: int | None = None,
    ) -> str | None:
        """Generate text. Returns None when unavailable instead of raising.

        ``num_predict`` caps output length (defaults to 600); ``attempts``
        overrides the retry budget for latency-sensitive callers.
        """
        if not self.configured:
            logger.info("Ollama model not configured; using deterministic fallback")
            return None

        payload: dict = {
            "model": self.model,
            "prompt": prompt,
            "stream": False,
            "options": {"temperature": 0.2, "num_predict": num_predict or 600},
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
                attempts_override=attempts,
            )
            text = (response.json().get("response") or "").strip() or None
        except Exception as exc:
            logger.warning("Ollama generate failed: %s", exc)
            return None

        if cache is not None and text is not None:
            cache.set(key, text)
        return text

    async def generate_json(
        self,
        prompt: str,
        system: str | None = None,
        *,
        timeout: float | None = None,
        num_predict: int | None = None,
        attempts: int | None = None,
    ) -> dict | None:
        """Generate + parse JSON. Returns None on any failure (caller falls back)."""
        text = await self.generate(
            prompt,
            system,
            json_mode=True,
            timeout=timeout,
            num_predict=num_predict,
            attempts=attempts,
        )
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


# ---------------------------------------------------------------------------
# Multi-provider chat completion with tool support
# ---------------------------------------------------------------------------


def _provider() -> str:
    return get_settings().llm_provider.lower()


def _groq_headers() -> dict[str, str]:
    return {
        "Authorization": f"Bearer {get_settings().groq_api_key}",
        "Content-Type": "application/json",
    }


def _normalize_messages(messages: list[dict[str, Any]]) -> list[dict[str, Any]]:
    out: list[dict[str, Any]] = []
    for m in messages:
        role = m.get("role")
        if role is None:
            continue
        item: dict[str, Any] = {"role": role}
        if m.get("content"):
            item["content"] = m["content"]
        if "tool_calls" in m:
            item["tool_calls"] = m["tool_calls"]
        if "tool_call_id" in m:
            item["tool_call_id"] = m["tool_call_id"]
        out.append(item)
    return out


async def _groq_chat_completion(
    messages: list[dict[str, Any]], tools: list[dict[str, Any]] | None
) -> dict[str, Any]:
    settings = get_settings()
    if not settings.groq_api_key:
        raise LLMError("LLM_PROVIDER=groq but GROQ_API_KEY is empty")

    payload: dict[str, Any] = {
        "model": settings.groq_model,
        "messages": _normalize_messages(messages),
        "temperature": 0.4,
    }
    if tools:
        payload["tools"] = tools
        payload["tool_choice"] = "auto"

    response = await get_http_client().post(
        "https://api.groq.com/openai/v1/chat/completions",
        headers=_groq_headers(),
        json=payload,
        timeout=settings.llm_chat_timeout_seconds,
    )
    response.raise_for_status()
    return response.json()


def _ollama_messages(messages: list[dict[str, Any]]) -> list[dict[str, Any]]:
    """Convert OpenAI-style tool messages to Ollama's native shape.

    Ollama takes ``tool_calls: [{function: {name, arguments}}]`` with arguments
    as an object, and tool results as ``{role: "tool", content}`` — no ``id``,
    ``type`` or ``tool_call_id``.
    """
    out: list[dict[str, Any]] = []
    for m in messages:
        role = m.get("role")
        if role is None:
            continue
        item: dict[str, Any] = {"role": role}
        if m.get("content"):
            item["content"] = m["content"]
        if role == "assistant" and m.get("tool_calls"):
            calls = []
            for c in m["tool_calls"]:
                fn = c.get("function", {})
                args = fn.get("arguments", {})
                if isinstance(args, str):
                    try:
                        args = json.loads(args)
                    except json.JSONDecodeError:
                        args = {}
                calls.append({"function": {"name": fn.get("name", ""), "arguments": args}})
            item["tool_calls"] = calls
        if role == "tool":
            item.pop("tool_call_id", None)
        out.append(item)
    return out


async def _ollama_chat_completion(
    messages: list[dict[str, Any]], tools: list[dict[str, Any]] | None
) -> dict[str, Any]:
    settings = get_settings()
    payload: dict[str, Any] = {
        "model": settings.ollama_model,
        "messages": _ollama_messages(messages),
        "stream": False,
        "options": {"temperature": 0.4, "num_predict": 800},
    }
    if tools:
        payload["tools"] = tools

    response = await _post_json(
        f"{settings.ollama_url.rstrip('/')}/api/chat",
        payload,
        timeout=settings.llm_chat_timeout_seconds,
    )
    data = response.json()
    msg = data.get("message", {})
    return {
        "choices": [{"message": msg}],
        "model": settings.ollama_model,
    }


async def chat_completion(
    messages: list[dict[str, Any]],
    tools: list[dict[str, Any]] | None = None,
) -> dict[str, Any]:
    """Call the configured LLM and return a raw completion-shaped response.

    The response mirrors OpenAI's chat completion so callers can read
    ``choices[0].message`` uniformly.
    """
    provider = _provider()
    if provider == "groq":
        return await _groq_chat_completion(messages, tools)
    if provider == "ollama":
        return await _ollama_chat_completion(messages, tools)
    raise LLMError(f"Unknown LLM provider: {provider}")


def extract_message(response: dict[str, Any]) -> dict[str, Any]:
    choices = response.get("choices", [])
    if not choices:
        return {"role": "assistant", "content": ""}
    return choices[0].get("message", {"role": "assistant", "content": ""})


def extract_tool_calls(message: dict[str, Any]) -> list[dict[str, Any]]:
    calls = message.get("tool_calls") or []
    out: list[dict[str, Any]] = []
    for c in calls:
        fn = c.get("function", {})
        args = fn.get("arguments", "{}")
        if isinstance(args, str):
            try:
                args = json.loads(args)
            except json.JSONDecodeError:
                args = {}
        out.append({
            "id": c.get("id", ""),
            "name": fn.get("name", ""),
            "arguments": args,
        })
    return out
