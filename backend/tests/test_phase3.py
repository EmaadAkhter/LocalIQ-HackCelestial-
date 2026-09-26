"""Phase 3 LLM tests: cache, retries, shared client, prompt quality,
structured-output normalisation, timeouts."""

import asyncio
import time

import httpx

from app.api.v1.parse import PARSE_SYSTEM, heuristic_parse
from app.config import get_settings
from app.schemas import ParsedConstraints
from app.services import llm
from app.services.cache import TTLCache


# ---------------------------------------------------------------------------
# Cache
# ---------------------------------------------------------------------------


def test_ttl_cache_set_get_and_stats():
    cache = TTLCache(maxsize=4, ttl_seconds=60)
    assert cache.get("missing") is None
    cache.set("a", 1)
    assert cache.get("a") == 1
    stats = cache.stats()
    assert stats["size"] == 1
    assert stats["hits"] == 1
    assert stats["misses"] == 1


def test_ttl_cache_expires():
    cache = TTLCache(maxsize=4, ttl_seconds=0.05)
    cache.set("a", 1)
    time.sleep(0.08)
    assert cache.get("a") is None


def test_ttl_cache_evicts_oldest():
    cache = TTLCache(maxsize=2, ttl_seconds=60)
    cache.set("a", 1)
    cache.set("b", 2)
    cache.set("c", 3)
    assert cache.get("a") is None
    assert cache.get("c") == 3


# ---------------------------------------------------------------------------
# Retries + cache around the HTTP call
# ---------------------------------------------------------------------------


def _patch_llm(monkeypatch, handler, *, retries=2, cache_enabled=False):
    """Point the LLM client at a MockTransport and zero-out backoff."""
    from app.services import llm as llm_module

    client = httpx.AsyncClient(transport=httpx.MockTransport(handler))
    base = get_settings()
    patched = base.model_copy(
        update={
            "llm_retry_backoff_seconds": 0.0,
            "llm_max_retries": retries,
            "llm_cache_enabled": cache_enabled,
        }
    )
    monkeypatch.setattr(llm_module, "get_settings", lambda: patched)
    monkeypatch.setattr(llm_module, "get_http_client", lambda: client)
    llm_module.reset_llm_cache()
    return client, llm_module


def test_generate_retries_transient_then_succeeds(monkeypatch):
    calls = {"n": 0}

    def handler(request):
        calls["n"] += 1
        if calls["n"] == 1:
            return httpx.Response(503, json={"error": "busy"})
        return httpx.Response(200, json={"response": "hello"})

    client, module = _patch_llm(monkeypatch, handler)

    async def run():
        result = await module.OllamaClient().generate("hi", timeout=1)
        await client.aclose()
        return result

    assert asyncio.run(run()) == "hello"
    assert calls["n"] == 2


def test_generate_does_not_retry_on_4xx(monkeypatch):
    calls = {"n": 0}

    def handler(request):
        calls["n"] += 1
        return httpx.Response(400, json={"error": "bad request"})

    client, module = _patch_llm(monkeypatch, handler)

    async def run():
        result = await module.OllamaClient().generate("hi", timeout=1)
        await client.aclose()
        return result

    assert asyncio.run(run()) is None
    assert calls["n"] == 1


def test_generate_cache_hit_avoids_second_call(monkeypatch):
    calls = {"n": 0}

    def handler(request):
        calls["n"] += 1
        return httpx.Response(200, json={"response": "cached"})

    client, module = _patch_llm(monkeypatch, handler, cache_enabled=True)

    async def run():
        client_obj = module.OllamaClient()
        first = await client_obj.generate("same prompt", timeout=1)
        second = await client_obj.generate("same prompt", timeout=1)
        await client.aclose()
        return first, second

    first, second = asyncio.run(run())
    assert first == second == "cached"
    assert calls["n"] == 1


def test_shared_http_client_is_reused():
    async def run():
        first = llm.get_http_client()
        second = llm.get_http_client()
        assert first is second
        await llm.close_http_client()
        third = llm.get_http_client()
        assert third is not first
        await llm.close_http_client()

    asyncio.run(run())


# ---------------------------------------------------------------------------
# Prompt quality + structured output
# ---------------------------------------------------------------------------


def test_parse_prompt_has_few_shot_examples():
    assert "Examples:" in PARSE_SYSTEM
    assert PARSE_SYSTEM.count("Output:") >= 3
    assert "never the string" in PARSE_SYSTEM


def test_parsed_constraints_normalize_llm_shapes():
    parsed = ParsedConstraints.model_validate(
        {
            "location": "Bandra",
            "time_hours": "4",
            "budget_inr": "₹1,500",
            "group_type": "Friends",
            "interests": "food, art",
            "accessibility": "None",
            "start_time": "7:5",
        }
    )
    assert parsed.location == "Bandra"
    assert parsed.time_hours == 4.0
    assert parsed.budget_inr == 1500
    assert parsed.group_type == "friends"
    assert parsed.interests == ["food", "art"]
    assert parsed.accessibility is None
    assert parsed.start_time is None


def test_parsed_constraints_nullish_and_lists():
    parsed = ParsedConstraints.model_validate(
        {
            "location": "null",
            "group_type": "null",
            "interests": ["food", "null", "Art"],
            "accessibility": ["wheelchair-accessible", "step-free"],
            "start_time": "7:05",
        }
    )
    assert parsed.location is None
    assert parsed.group_type is None
    assert parsed.interests == ["food", "art"]
    assert parsed.accessibility == "wheelchair-accessible, step-free"
    assert parsed.start_time == "07:05"


def test_heuristic_parse_accuracy_on_examples():
    cases = [
        ("4 hours in bandra with 1500 rupees for food and art",
         {"location": "Bandra", "time_hours": 4.0, "budget_inr": 1500}),
        ("2 hours near colaba under Rs 800 for shopping",
         {"location": "Colaba", "time_hours": 2.0, "budget_inr": 800}),
        ("half day heritage walk in fort",
         {"location": "Fort", "time_hours": 4.0}),
        ("full day outdoor cycling in powai with 2000 budget",
         {"location": "Powai", "time_hours": 8.0, "budget_inr": 2000}),
        ("couple date bar hopping in bandra for 3 hours",
         {"location": "Bandra", "time_hours": 3.0, "group_type": "couple"}),
        ("wheelchair accessible food near juhu for 2h",
         {"location": "Juhu", "time_hours": 2.0, "accessibility": "wheelchair-accessible"}),
        ("solo traveller wants street food and history in colaba for 5 hours",
         {"location": "Colaba", "time_hours": 5.0, "group_type": "solo"}),
        ("family friendly shopping market in bandra west 1200 rupees",
         {"location": "Bandra West", "budget_inr": 1200, "group_type": "family"}),
        ("sunset walk at marine drive in the evening for 1 hour",
         {"location": "Marine Drive", "time_hours": 1.0, "start_time": "18:00"}),
        ("cheap eats for 300 rupees in dadar for 1.5 hours",
         {"location": "Dadar", "time_hours": 1.5, "budget_inr": 300}),
    ]

    correct = 0
    checks = 0
    for sentence, expected in cases:
        parsed = heuristic_parse(sentence)
        for field, value in expected.items():
            checks += 1
            if getattr(parsed, field) == value:
                correct += 1
            else:
                print(f"MISS {field}: {sentence!r} -> {getattr(parsed, field)!r} != {value!r}")

    accuracy = correct / checks
    assert accuracy >= 0.9, f"heuristic parse accuracy {accuracy:.0%} (< 90%)"


def test_per_endpoint_timeouts_configured():
    settings = get_settings()
    assert settings.llm_parse_timeout_seconds > 0
    assert settings.llm_chat_timeout_seconds > 0
    assert settings.llm_warm_timeout_seconds > 0
    assert settings.llm_max_retries >= 1
