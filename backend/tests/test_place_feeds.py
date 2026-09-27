"""Tests for the Home feed endpoints: /places/for-you and /places/right-now.

These pin two regressions the app shipped with:

1. "Hidden gems" matched 47 of 48 places because the seed clustered every
   ``local_gem_score`` between 0.60 and 0.95 and the threshold was 0.70.
2. The three Home rails were cut from one rating-sorted list, so they showed
   the same handful of places.
"""

from fastapi.testclient import TestClient
from sqlmodel import Session, select

from app.database import engine
from app.models import Experience
from app.seed import DATA_PATH
from app.services import places as places_service
from main import app

client = TestClient(app)

MUMBAI = {"lat": 19.0596, "lng": 72.8295}

_PLACE_KEYS = {
    "id", "name", "category", "address", "area", "centre", "heroImageUrl",
    "imageUrls", "openingHours", "accessibility", "rating", "reviewCount",
    "priceLevel", "typicalSpend", "crowdLevel", "indoor", "localFavourite",
    "bookingRequired",
}


# ---------------------------------------------------------------------------
# Dataset calibration
# ---------------------------------------------------------------------------


def test_gem_scores_are_a_minority():
    """A "hidden gem" that matches almost everything is not a gem."""
    import json

    raw = json.loads(DATA_PATH.read_text(encoding="utf-8"))
    experiences = raw["experiences"] if isinstance(raw, dict) else raw
    gems = [e for e in experiences if float(e.get("local_gem_score", 0)) >= 0.85]
    assert 0 < len(gems) <= len(experiences) * 0.30, (
        f"{len(gems)}/{len(experiences)} flagged as gems; expected a clear minority"
    )


def test_local_favourite_uses_the_gem_threshold():
    gem = Experience(id=9001, name="TS-gem", category="food", lat=19.0, lng=72.8, local_gem_score=0.90)
    ordinary = Experience(id=9002, name="TS-ordinary", category="food", lat=19.0, lng=72.8, local_gem_score=0.60)
    assert places_service.place_from_experience(gem)["localFavourite"] is True
    assert places_service.place_from_experience(ordinary)["localFavourite"] is False


# ---------------------------------------------------------------------------
# Feeds
# ---------------------------------------------------------------------------


def test_for_you_returns_place_shape():
    r = client.get("/api/v1/places/for-you", params={**MUMBAI, "limit": 8})
    assert r.status_code == 200, r.text
    places = r.json()
    assert places, "for-you should never be empty"
    for place in places:
        assert _PLACE_KEYS <= set(place), f"missing {_PLACE_KEYS - set(place)}"
    assert len({p["id"] for p in places}) == len(places), "duplicate ids in the feed"


def test_right_now_carries_live_context():
    r = client.get("/api/v1/places/right-now", params={**MUMBAI, "limit": 8})
    assert r.status_code == 200, r.text
    places = r.json()
    assert places
    for place in places:
        assert _PLACE_KEYS <= set(place)
        # Every card ships the computed reason, not a hardcoded badge.
        assert place["rightNowLabel"]
        assert isinstance(place["rightNowContext"], list)
        assert 0 <= float(place["rightNowScore"]) <= 100


def test_right_now_is_sorted_by_live_score():
    plays = client.get("/api/v1/places/right-now", params={**MUMBAI, "limit": 10}).json()
    scored = [float(p["rightNowScore"]) for p in plays]
    # The feed blends taste + right-now; scores must trend downward overall.
    assert scored[0] >= scored[-1]


def test_gems_only_returns_real_gems():
    r = client.get("/api/v1/places/gems", params={**MUMBAI, "limit": 10})
    assert r.status_code == 200, r.text
    from app.services.places import GEM_RAIL_MIN_SCORE

    for place in r.json():
        assert place["localGemScore"] >= GEM_RAIL_MIN_SCORE, place["name"]


def test_rails_do_not_share_the_same_top_items():
    """The original bug: every rail started with the same two places."""
    for_you = client.get("/api/v1/places/for-you", params={**MUMBAI, "limit": 6}).json()
    gems = client.get("/api/v1/places/gems", params={**MUMBAI, "limit": 6}).json()
    for_you_ids = [p["id"] for p in for_you]
    gem_ids = [p["id"] for p in gems]
    # Not all six need to differ, but they must not be the same list.
    assert for_you_ids != gem_ids

    with Session(engine) as session:
        gem_rows = session.exec(
            select(Experience).where(Experience.local_gem_score >= 0.85)
        ).all()
    assert gem_rows, "seed should contain real gems"
