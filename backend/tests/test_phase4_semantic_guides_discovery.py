"""Tests for semantic search, tag taxonomy, guide packages and discovery."""

import asyncio

from fastapi.testclient import TestClient
from sqlmodel import Session, select

from app.database import engine, init_db
from app.models import Experience, Guide, GuidePackage, GuidePackageStop, Tag
from app.seed import seed_database, seed_guide_packages
from main import app

client = TestClient(app)


def setup_module(module):
    init_db()
    seed_database()
    seed_guide_packages()


# --- Tags ------------------------------------------------------------------


def test_list_tags_and_categories():
    r = client.get("/api/v1/tags")
    assert r.status_code == 200
    tags = r.json()
    assert len(tags) > 50
    assert {"id", "name", "category"} <= set(tags[0].keys())

    r = client.get("/api/v1/tags/categories")
    assert r.status_code == 200
    assert len(r.json()) >= 3


def test_experience_tags_and_by_tag():
    r = client.get("/api/v1/experiences/1/tags")
    assert r.status_code == 200

    with Session(engine) as s:
        tag = s.exec(select(Tag)).first()
        assert tag is not None
        tag_name = tag.name

    r = client.get(f"/api/v1/experiences/by-tag/{tag_name}")
    assert r.status_code == 200
    assert isinstance(r.json(), list)


def test_composite_tags():
    r = client.get("/api/v1/composite-tags")
    assert r.status_code == 200
    assert isinstance(r.json(), list)


# --- Semantic recommendations ---------------------------------------------


def test_semantic_recommend_returns_results_with_reason():
    r = client.post(
        "/api/v1/recommend",
        json={
            "location": "Bandra",
            "time_hours": 3,
            "budget_inr": 1000,
            "use_semantic": True,
            "semantic_query": "quiet photogenic heritage spot",
            "limit": 3,
        },
    )
    assert r.status_code == 200
    data = r.json()
    assert data["feasible_count"] >= 1
    assert len(data["recommendations"]) >= 1
    assert "semantically matched" in data["recommendations"][0]["why_this_fits"]


def test_recommend_without_semantic_still_works():
    r = client.post(
        "/api/v1/recommend",
        json={"location": "Colaba", "time_hours": 4, "budget_inr": 2000, "limit": 5},
    )
    assert r.status_code == 200
    assert r.json()["feasible_count"] >= 1


# --- Guide packages --------------------------------------------------------


def test_list_and_get_guide_packages():
    with Session(engine) as s:
        guide = s.exec(select(Guide)).first()
        assert guide is not None
        guide_id = guide.id

    r = client.get(f"/api/v1/guides/{guide_id}/packages")
    assert r.status_code == 200
    packages = r.json()
    assert len(packages) >= 1
    package_id = packages[0]["id"]
    assert len(packages[0]["stops"]) >= 1

    r = client.get(f"/api/v1/guide-packages/{package_id}")
    assert r.status_code == 200
    assert r.json()["id"] == package_id


def test_create_book_and_review_package():
    with Session(engine) as s:
        guide = s.exec(select(Guide)).first()
        exp = s.exec(select(Experience)).first()
        assert guide is not None and exp is not None
        guide_id = guide.id
        exp_id = exp.id

    r = client.post(
        f"/api/v1/guides/{guide_id}/packages",
        json={
            "title": "Test Package",
            "description": "A test route.",
            "total_duration_hours": 3,
            "price_per_person": 999,
            "max_group_size": 6,
            "stops": [
                {"sequence": 1, "experience_id": exp_id, "location_name": "Stop 1", "duration_min": 60}
            ],
        },
    )
    assert r.status_code == 201
    package = r.json()
    assert len(package["stops"]) == 1
    package_id = package["id"]

    r = client.post(
        f"/api/v1/guide-packages/{package_id}/book",
        json={"package_id": package_id, "date": "2026-10-01", "group_size": 2},
    )
    assert r.status_code == 201
    booking = r.json()
    assert booking["status"] == "pending"
    assert booking["booking_ref"].startswith("LQ-")

    r = client.post(
        f"/api/v1/guide-packages/{package_id}/reviews",
        json={"booking_id": booking["id"], "rating": 5.0, "review_text": "Loved it"},
    )
    assert r.status_code == 201

    r = client.get(f"/api/v1/guide-packages/{package_id}/reviews")
    assert r.status_code == 200
    assert any(rev["booking_id"] == booking["id"] for rev in r.json())

    # Clean up so other tests aren't affected by the extra package. The dev DB
    # persists across runs, so remove the child rows explicitly.
    from app.models import GuideBooking, GuideReview

    with Session(engine) as s:
        for review in s.exec(select(GuideReview).where(GuideReview.package_id == package_id)).all():
            s.delete(review)
        for bk in s.exec(select(GuideBooking).where(GuideBooking.package_id == package_id)).all():
            s.delete(bk)
        for stop in s.exec(
            select(GuidePackageStop).where(GuidePackageStop.package_id == package_id)
        ).all():
            s.delete(stop)
        pkg = s.get(GuidePackage, package_id)
        if pkg is not None:
            s.delete(pkg)
        s.commit()


def test_booking_rejects_oversized_group():
    with Session(engine) as s:
        package = s.exec(select(GuidePackage)).first()
        assert package is not None
        package_id = package.id
        max_size = package.max_group_size

    r = client.post(
        f"/api/v1/guide-packages/{package_id}/book",
        json={"package_id": package_id, "date": "2026-10-01", "group_size": max_size + 1},
    )
    assert r.status_code == 400


def test_guide_availability_roundtrip():
    with Session(engine) as s:
        guide_id = s.exec(select(Guide)).first().id

    r = client.post(
        f"/api/v1/guides/{guide_id}/availability",
        json={"available_date": "2026-11-01", "start_time": "10:00", "end_time": "14:00"},
    )
    assert r.status_code == 201

    r = client.get(f"/api/v1/guides/{guide_id}/availability")
    assert r.status_code == 200
    assert any(a["start_time"] == "10:00" for a in r.json())


# --- Discovery -------------------------------------------------------------


def test_discovery_degrades_gracefully(monkeypatch):
    """When SearXNG has no results the endpoint returns an empty list, not 500."""

    async def fake_search(query, max_results=None):
        return []

    monkeypatch.setattr("app.services.discovery.search_searxng", fake_search)
    r = client.post("/api/v1/discover", json={"query": "street food walk", "area": "Dadar"})
    assert r.status_code == 200
    assert r.json()["candidates"] == []


def test_discovery_stores_candidates(monkeypatch):
    """A mocked SearXNG + page gives a stored candidate with normalized tags."""

    async def fake_search(query, max_results=None):
        return [{"url": "https://example.com/mumbai", "title": "Mumbai guide", "content": ""}]

    async def fake_scrape(url):
        return {
            "url": url,
            "title": "Mumbai guide",
            "text": (
                "Visit the ancient Sri Heritage Temple in Bandra for a peaceful morning. "
                "The temple is a heritage site worth exploring."
            ),
            "ok": True,
        }

    monkeypatch.setattr("app.services.discovery.search_searxng", fake_search)
    monkeypatch.setattr("app.services.discovery.scrape_page", fake_scrape)

    r = client.post(
        "/api/v1/discover",
        json={"query": "temples", "area": "Bandra", "store": True},
    )
    assert r.status_code == 200
    candidates = r.json()["candidates"]
    assert len(candidates) >= 1
    assert candidates[0]["raw_title"]


# --- Admin reindex ---------------------------------------------------------


def test_llm_candidate_normalization_filters_bad_values():
    """Normalization rejects area names, clamps confidence and validates tags."""
    from app.services import discovery

    page = {"url": "https://x.test/a", "title": "T"}

    # A neighbourhood name is not a place.
    assert (
        discovery._normalize_llm_candidate(
            {"name": "Bandra", "area": "Bandra", "tags": ["food"]}, page, "Bandra"
        )
        is None
    )
    # Empty/too-short names are rejected.
    assert discovery._normalize_llm_candidate({"name": "ab"}, page, None) is None

    candidate = discovery._normalize_llm_candidate(
        {
            "name": "Jaico House",
            "area": "Fort",
            "category": "heritage",
            "tags": ["heritage", "not_a_real_tag"],
            "description": "An old bookstore.",
            "confidence": 1.5,
        },
        page,
        "Bandra",
    )
    assert candidate is not None
    assert candidate["raw_title"] == "Jaico House"
    assert "not_a_real_tag" not in candidate["extracted_data"]["tags"]
    assert "heritage" in candidate["extracted_data"]["tags"]
    assert candidate["llm_confidence"] == 1.0
    assert candidate["area"] == "Fort"
    assert candidate["extracted_data"]["extraction_method"] == "llm"


def test_extract_candidates_prefers_llm(monkeypatch):
    """When the LLM extractor returns results, heuristics are not used."""
    from app.services import discovery

    async def fake_llm(page, area):
        return [
            {
                "raw_title": "From LLM",
                "url": page.get("url"),
                "area": area,
                "extracted_data": {
                    "sentence": "x",
                    "tags": ["heritage"],
                    "extraction_method": "llm",
                },
                "llm_confidence": 0.9,
            }
        ]

    monkeypatch.setattr(discovery, "_extract_candidates_llm", fake_llm)
    page = {"url": "https://x.test/a", "title": "T", "text": "text", "ok": True}
    candidates = asyncio.run(discovery.extract_candidates(page, "Bandra"))
    assert [c["raw_title"] for c in candidates] == ["From LLM"]


def test_extract_candidates_falls_back_to_heuristic(monkeypatch):
    """When the LLM is unavailable, the heuristic extractor still runs."""
    from app.services import discovery

    async def no_llm(page, area):
        return None

    monkeypatch.setattr(discovery, "_extract_candidates_llm", no_llm)
    page = {
        "url": "https://x.test/a",
        "title": "T",
        "text": "On Sunday, visit the Foo Heritage Place in Bandra for a quiet tour.",
        "ok": True,
    }
    candidates = asyncio.run(discovery.extract_candidates(page, "Bandra"))
    assert candidates
    assert candidates[0]["extracted_data"]["extraction_method"] == "heuristic"
    assert candidates[0]["area"] == "Bandra"


def test_admin_candidate_curation(monkeypatch):
    """A stored candidate can be listed, approved into an experience and cleaned up."""
    monkeypatch.setenv("ADMIN_API_KEY", "curate-key")
    from app.config import get_settings

    get_settings.cache_clear()
    headers = {"X-Admin-Key": "curate-key"}

    async def fake_search(query, max_results=None):
        return [{"url": "https://example.org/gems", "title": "Gems", "content": ""}]

    async def fake_scrape(url):
        return {
            "url": url,
            "title": "Gems",
            "text": "Explore the quiet Kotachi Wadi Heritage Lane in Girgaon this weekend.",
            "ok": True,
        }

    monkeypatch.setattr("app.services.discovery.search_searxng", fake_search)
    monkeypatch.setattr("app.services.discovery.scrape_page", fake_scrape)

    try:
        r = client.post("/api/v1/discover", json={"query": "hidden gems", "area": "Girgaon"})
        assert r.status_code == 200
        candidates = r.json()["candidates"]
        assert candidates
        candidate_id = candidates[0]["id"]

        r = client.get("/api/v1/admin/candidates", headers=headers)
        assert r.status_code == 200
        assert any(c["id"] == candidate_id for c in r.json())

        r = client.post(f"/api/v1/admin/candidates/{candidate_id}/approve", headers=headers)
        assert r.status_code == 201
        experience_id = r.json()["id"]

        r = client.post(f"/api/v1/admin/candidates/{candidate_id}/reject", headers=headers)
        assert r.status_code == 200
        assert r.json()["status"] == "rejected"

        # Clean up the promoted experience and candidate.
        from app.models import HiddenGemCandidate

        with Session(engine) as s:
            exp = s.get(Experience, experience_id)
            if exp is not None:
                s.delete(exp)
            cand = s.get(HiddenGemCandidate, candidate_id)
            if cand is not None:
                s.delete(cand)
            s.commit()
    finally:
        get_settings.cache_clear()


def test_admin_reindex_requires_key(monkeypatch):
    monkeypatch.setenv("ADMIN_API_KEY", "test-admin-key")
    from app.config import get_settings

    get_settings.cache_clear()
    try:
        r = client.post("/api/v1/admin/reindex")
        assert r.status_code == 401

        r = client.post("/api/v1/admin/reindex", headers={"X-Admin-Key": "test-admin-key"})
        assert r.status_code == 200
        assert r.json()["regenerated"] >= 1
    finally:
        get_settings.cache_clear()
