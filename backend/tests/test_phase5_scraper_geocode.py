"""Tests for the scraper helpers and the geocoding guardrails (no network)."""

import importlib.util
from pathlib import Path


def _load_scraper():
    path = Path(__file__).resolve().parent.parent / "scripts" / "seed_mmrd_activities.py"
    spec = importlib.util.spec_from_file_location("seed_mmrd", path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def test_in_mmr_bounds():
    from app.services.geocode import in_mmr

    assert in_mmr(19.076, 72.8777)  # Mumbai
    assert in_mmr(19.218, 72.978)  # Thane
    assert not in_mmr(28.6139, 77.2090)  # Delhi
    assert not in_mmr(15.2993, 74.1240)  # Goa


def test_scraper_category_inference():
    scraper = _load_scraper()
    assert scraper._infer_category(["street_food", "chaat"]) == "food"
    assert scraper._infer_category(["nightlife", "bars"]) == "nightlife"
    assert scraper._infer_category(["street_art"]) == "art"
    assert scraper._infer_category(["heritage"]) == "culture"
    assert scraper._infer_category(["beach", "sunset"]) == "nature"
    assert scraper._infer_category(["unknown_tag"]) == "culture"


def test_scraper_indoor_outdoor():
    scraper = _load_scraper()
    assert scraper._infer_indoor_outdoor(["beach", "views"]) == "outdoor"
    assert scraper._infer_indoor_outdoor(["cafe", "museum"]) == "indoor"


def test_scraper_name_normalisation():
    scraper = _load_scraper()
    assert scraper._norm_name("The Best Bandra Fort!") == "bandra fort"
    assert scraper._norm_name("Mumbai") == ""
    assert scraper._norm_name("Gateway of India, Colaba") == "gateway india colaba"


def test_scraper_query_build_is_broad():
    scraper = _load_scraper()
    queries = scraper._build_queries(["bandra", "thane"], ["street food", "cafes"])
    assert queries
    assert all(area in ("bandra", "thane") for _, area in queries)
    assert any("street food" in q for q, _ in queries)
    assert len(queries) >= 2 * len(scraper.TEMPLATES)
