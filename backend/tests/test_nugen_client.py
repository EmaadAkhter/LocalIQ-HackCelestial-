"""Nugen integration tests.

The model endpoint itself is off by default (``NUGEN_ENABLED=false``), so these
tests cover the parts that must be correct without a live Nugen account: the
kill-switch, the schema bridge, and the parser's fallback behaviour.
"""

from app.services import nugen
from app.services.nugen import to_parsed_constraints


def test_nugen_is_disabled_by_default():
    # No NUGEN_MODEL_ID and NUGEN_ENABLED=false in the test env.
    assert nugen.configured() is False


def test_constraints_bridge_maps_time_and_interests():
    mapped = to_parsed_constraints(
        {
            "location": "Bandra",
            "time_minutes": 120,
            "budget_inr": 800,
            "interests": ["food", "history"],
            "preferences": ["local", "indoor"],
        }
    )
    assert mapped["location"] == "Bandra"
    assert mapped["time_hours"] == 2.0
    assert mapped["budget_inr"] == 800
    # history folds into culture; unknown preferences do not leak into interests.
    assert mapped["interests"] == ["food", "culture"]


def test_constraints_bridge_maps_accessibility_preference():
    mapped = to_parsed_constraints(
        {"interests": ["culture"], "preferences": ["wheelchair", "quiet"]}
    )
    assert mapped["accessibility"] == "wheelchair-accessible"
    assert mapped["time_hours"] is None


def test_parse_endpoint_falls_back_when_nugen_off():
    from fastapi.testclient import TestClient

    from main import app

    client = TestClient(app)
    resp = client.post("/api/v1/parse", json={"text": "2 hours in Bandra, ₹800, food"})
    assert resp.status_code == 200
    body = resp.json()
    # Must never be "nugen" while the integration is switched off.
    assert body["source"] in ("heuristic", "ollama")
