"""Self-hosted embedding service via Ollama.

Falls back to a deterministic pseudo-embedding when Ollama is unavailable or
when running against SQLite in development.
"""

from __future__ import annotations

import hashlib
import logging
import math
from functools import lru_cache

import httpx

from app.config import get_settings
from app.services.llm import get_http_client

logger = logging.getLogger(__name__)

settings = get_settings()


class EmbeddingError(Exception):
    """Raised when embedding generation fails and no fallback is acceptable."""


async def embed_text(text: str) -> list[float]:
    """Embed a single text string.

    Uses Ollama's ``/api/embeddings`` endpoint. If Ollama is unreachable or
    returns an error, returns a deterministic fallback vector so the rest of
    the system keeps working.
    """
    if not text or not text.strip():
        return _zero_vector()

    cache_key = _cache_key(text)
    cached = _embedding_cache.get(cache_key)
    if cached is not None:
        return cached

    try:
        vector = await _ollama_embed(text)
    except Exception as exc:
        logger.warning("Ollama embed failed for %r: %s; using fallback", text[:40], exc)
        vector = _fallback_vector(text)

    _embedding_cache[cache_key] = vector
    return vector


async def embed_batch(texts: list[str]) -> list[list[float]]:
    """Embed multiple texts, sequentially (Ollama local models are small).

    For larger batches, switch to a batched endpoint or co-located embedding
    microservice.
    """
    results: list[list[float]] = []
    for text in texts:
        results.append(await embed_text(text))
    return results


async def _ollama_embed(text: str) -> list[float]:
    client = get_http_client()
    payload = {
        "model": settings.embedding_model,
        "prompt": text[:4000],
    }
    response = await client.post(
        f"{settings.ollama_url}/api/embeddings",
        json=payload,
        timeout=settings.embedding_timeout_seconds,
    )
    response.raise_for_status()
    data = response.json()
    vector = data.get("embedding")
    if not vector or not isinstance(vector, list):
        raise EmbeddingError(f"Ollama returned invalid embedding: {data.keys()}")
    return [float(v) for v in vector]


@lru_cache(maxsize=1024)
def _cache_key(text: str) -> str:
    return hashlib.sha256(text.encode("utf-8")).hexdigest()[:32]


def _zero_vector() -> list[float]:
    return [0.0] * settings.embedding_dimension


def _fallback_vector(text: str) -> list[float]:
    """Deterministic fallback embedding from the text hash.

    Not semantically meaningful, but stable per text so tests and offline dev
    don't break.
    """
    dim = settings.embedding_dimension
    # Produce dim pseudo-random floats in [-1, 1] deterministically from text.
    vector: list[float] = []
    seed = int(hashlib.sha256(text.encode("utf-8")).hexdigest(), 16)
    for i in range(dim):
        # Simple LCG-ish mixer.
        seed = (seed * 1103515245 + 12345) & 0xFFFFFFFF
        value = (seed % 200001) / 100000.0 - 1.0
        vector.append(round(value, 6))
    return vector


_embedding_cache: dict[str, list[float]] = {}


def clear_embedding_cache() -> None:
    _embedding_cache.clear()


def normalize_vector(vector: list[float]) -> list[float]:
    """L2-normalize a vector."""
    norm = math.sqrt(sum(v * v for v in vector))
    if norm == 0:
        return vector
    return [v / norm for v in vector]
