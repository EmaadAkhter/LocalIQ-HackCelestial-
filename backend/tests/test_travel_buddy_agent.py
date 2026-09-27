"""Unit tests for the Travel Buddy agent's degenerate-response handling.

Ollama occasionally answers a tool result with an empty assistant turn, which
used to render as a blank chat bubble in the app. The agent must always produce
something grounded in what the tools actually returned.
"""

from app.services.agent import _summarize_results
from app.services.llm import extract_tool_calls


def test_ollama_tool_calls_get_synthesised_ids():
    # Ollama's native shape has no id, unlike OpenAI's.
    message = {
        "role": "assistant",
        "tool_calls": [
            {"function": {"name": "search_places", "arguments": {"query": "cafe"}}},
            {"function": {"name": "search_guides", "arguments": {"area": "Bandra"}}},
        ],
    }
    calls = extract_tool_calls(message)
    assert [c["name"] for c in calls] == ["search_places", "search_guides"]
    assert calls[0]["arguments"] == {"query": "cafe"}
    assert all(c["id"] for c in calls), "ids must be synthesised when Ollama omits them"
    assert len({c["id"] for c in calls}) == 2, "ids must be unique within a turn"


def test_openai_tool_calls_keep_their_ids():
    message = {
        "tool_calls": [
            {"id": "call_abc", "function": {"name": "search_places", "arguments": "{}"}},
        ]
    }
    calls = extract_tool_calls(message)
    assert calls[0]["id"] == "call_abc"


def test_summarize_results_lists_real_places():
    results = [
        {
            "tool_call_id": "call_0",
            "result": [
                {"name": "Britannia & Co", "category": "food", "rating": 4.6, "avg_cost": 700},
                {"name": "Chor Bazaar", "category": "shopping", "rating": 4.2, "avg_cost": 0},
            ],
        }
    ]
    text = _summarize_results(results)
    assert "Britannia & Co" in text
    assert "Chor Bazaar" in text
    assert "4.6/5" in text


def test_summarize_results_handles_empty_payloads():
    assert _summarize_results([]) == ""
    assert _summarize_results([{"tool_call_id": "x", "result": []}]) == ""
    assert _summarize_results([{"tool_call_id": "x", "result": {"error": "boom"}}]).startswith(
        "I could not complete"
    )
