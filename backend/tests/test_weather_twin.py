"""Weather Digital Twin tests: state, simulation, cascades, social signals."""

from fastapi.testclient import TestClient

from app.services import twin
from main import app

client = TestClient(app)

SOUTH_MUMBAI = {"lat": 18.927, "lng": 72.833, "radius_km": 8}


def _fake_weather(monkeypatch, condition="clear", temp=30, chance=10):
    async def fake_fetch(lat, lon):
        return {
            "available": True,
            "condition": condition,
            "temp_c": temp,
            "is_rainy": condition in ("rain", "storm", "drizzle"),
            "suitable_outdoor": condition not in ("rain", "storm"),
            "precipitation_chance": chance,
        }

    monkeypatch.setattr("app.api.v1.twin.fetch_weather", fake_fetch)


def _simulate(rain_level, **extra):
    payload = {"rain_level": rain_level, **SOUTH_MUMBAI, **extra}
    return client.post("/api/v1/twin/simulate", json=payload).json()


def test_state_returns_experiences_areas_and_summary(monkeypatch):
    _fake_weather(monkeypatch)
    resp = client.get("/api/v1/twin/state", params=SOUTH_MUMBAI)
    assert resp.status_code == 200
    body = resp.json()
    assert body["experiences"], "twin must score real experiences"
    assert body["areas"], "twin must score real areas"
    assert body["scenario"]["rain_level"] in twin.RAIN_LEVELS
    assert body["summary"]["narrative"]


def test_rain_pushes_outdoor_suitability_down(monkeypatch):
    _fake_weather(monkeypatch)
    dry = _simulate("none")
    wet = _simulate("storm")

    dry_outdoor = [e for e in dry["experiences"] if e["indoor_ratio"] < 0.5]
    wet_outdoor = [e for e in wet["experiences"] if e["indoor_ratio"] < 0.5]
    assert dry_outdoor and wet_outdoor
    assert max(e["weather_suitability_score"] for e in wet_outdoor) < max(
        e["weather_suitability_score"] for e in dry_outdoor
    )


def test_storm_marks_outdoor_experiences_infeasible(monkeypatch):
    _fake_weather(monkeypatch)
    wet = _simulate("storm", duration_hours=3)
    infeasible = [e for e in wet["experiences"] if e["infeasible"]]
    assert infeasible, "a storm should make some experiences infeasible"
    # Fully-indoor venues survive; outdoor and mixed ones can fail.
    assert all(e["indoor_ratio"] <= 0.5 for e in infeasible)
    assert wet["summary"]["outdoor_impacted_pct"] > 0


def test_indoor_demand_rises_with_rain(monkeypatch):
    _fake_weather(monkeypatch)
    wet = _simulate("storm")
    indoor = [e for e in wet["experiences"] if e["indoor_ratio"] >= 0.5]
    assert indoor, "need indoor experiences to measure demand"
    assert max(e["demand_multiplier"] for e in indoor) > 2.0


def test_clear_weather_keeps_outdoors_feasible(monkeypatch):
    _fake_weather(monkeypatch)
    dry = _simulate("none")
    outdoors = [e for e in dry["experiences"] if e["indoor_ratio"] < 0.5]
    assert outdoors
    assert all(e["weather_suitability_score"] >= twin.INFEASIBLE_SCORE for e in outdoors)


def test_social_signals_raise_marine_drive_flood_risk(monkeypatch):
    _fake_weather(monkeypatch)
    body = _simulate("heavy", duration_hours=2)
    marine = next((a for a in body["areas"] if a["name"] == "Marine Drive"), None)
    assert marine is not None, "Marine Drive is in the South Mumbai pilot"
    assert marine["mentions"] >= 1, "curated demo feed must feed the twin"
    assert marine["flood_risk_level"] in ("MEDIUM", "HIGH")


def test_duration_increases_flood_risk(monkeypatch):
    _fake_weather(monkeypatch)
    short = _simulate("heavy", duration_hours=1)
    long = _simulate("heavy", duration_hours=6)
    short_avg = sum(a["flood_risk_score"] for a in short["areas"]) / len(short["areas"])
    long_avg = sum(a["flood_risk_score"] for a in long["areas"]) / len(long["areas"])
    assert long_avg >= short_avg


def test_summarize_suggests_indoor_switch_when_outdoors_blocked(monkeypatch):
    _fake_weather(monkeypatch)
    wet = _simulate("storm", duration_hours=3)
    switch = wet["summary"]["suggested_switch"]
    assert switch is not None
    assert switch["from"] != switch["to"]
