"""Prometheus metrics.

Served at ``GET /metrics`` on the backend. The Caddy edge deliberately does
**not** route ``/metrics``, so it is scraped from inside the network (Docker /
Kubernetes) rather than exposed on the public tunnel.
"""

from __future__ import annotations

from prometheus_client import CONTENT_TYPE_LATEST, Counter, Gauge, Histogram, generate_latest

REQUEST_TOTAL = Counter(
    "localiq_http_requests_total",
    "HTTP requests handled",
    ["method", "path", "status"],
)
REQUEST_DURATION = Histogram(
    "localiq_http_request_duration_seconds",
    "HTTP request duration in seconds",
    ["method", "path"],
    buckets=(0.005, 0.01, 0.025, 0.05, 0.1, 0.25, 0.5, 1.0, 2.5, 5.0, 10.0),
)

LLM_CACHE_SIZE = Gauge("localiq_llm_cache_entries", "LLM response cache entries")
LLM_CACHE_HITS = Gauge("localiq_llm_cache_hits_total", "LLM response cache hits")
LLM_CACHE_MISSES = Gauge("localiq_llm_cache_misses_total", "LLM response cache misses")

WEATHER_CACHE_SIZE = Gauge("localiq_weather_cache_entries", "Weather cache entries")

RECOMMEND_CACHE_SIZE = Gauge("localiq_recommend_cache_entries", "Recommendation cache entries")
RECOMMEND_CACHE_HITS = Gauge("localiq_recommend_cache_hits_total", "Recommendation cache hits")
RECOMMEND_CACHE_MISSES = Gauge("localiq_recommend_cache_misses_total", "Recommendation cache misses")

DB_POOL_CHECKED_OUT = Gauge("localiq_db_pool_checked_out", "DB connections currently checked out")


def init_metrics() -> None:
    """Bind gauges to live values. Imported lazily to avoid cycles."""
    from app.api.v1 import recommendations
    from app.database import engine
    from app.services import llm, weather

    LLM_CACHE_SIZE.set_function(lambda: llm.cache_stats().get("size", 0))
    LLM_CACHE_HITS.set_function(lambda: llm.cache_stats().get("hits", 0))
    LLM_CACHE_MISSES.set_function(lambda: llm.cache_stats().get("misses", 0))
    WEATHER_CACHE_SIZE.set_function(lambda: weather.weather_cache_stats().get("size", 0))
    RECOMMEND_CACHE_SIZE.set_function(lambda: recommendations.recommend_cache_stats().get("size", 0))
    RECOMMEND_CACHE_HITS.set_function(lambda: recommendations.recommend_cache_stats().get("hits", 0))
    RECOMMEND_CACHE_MISSES.set_function(lambda: recommendations.recommend_cache_stats().get("misses", 0))

    def _checked_out() -> int:
        try:
            return int(engine.pool.checkedout())  # type: ignore[attr-defined]
        except Exception:
            return 0

    DB_POOL_CHECKED_OUT.set_function(_checked_out)


def metrics_payload() -> tuple[bytes, str]:
    """Return (body, content_type) for the /metrics endpoint."""
    return generate_latest(), CONTENT_TYPE_LATEST
