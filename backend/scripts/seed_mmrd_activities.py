#!/usr/bin/env python3
"""Aggressively discover MMR (Mumbai Metropolitan Region) activities via
SearXNG + the local LLM, geocode them, and fill the local vector database.

No paid APIs. The pipeline is the same one the live endpoint uses, run in bulk:

    generate queries (area x activity)
      -> SearXNG JSON search
      -> scrape each page (or its search snippet when a site blocks bots)
      -> local-LLM extraction, constrained to the tag taxonomy
      -> geocode with Nominatim (MMR-bounded)
      -> dedupe across the run and against the DB
      -> insert into `experiences` (embeddings generated) or into
         `scraped_candidates` for curation

Examples
--------
    # Dry run: show the plan and resolve a couple of pages, write nothing.
    python scripts/seed_mmrd_activities.py --dry-run --max-queries 3

    # Fill the DB directly with up to 1000 new experiences.
    python scripts/seed_mmrd_activities.py --target 1000 --store experiences

    # Only collect raw candidates for the admin curation UI.
    python scripts/seed_mmrd_activities.py --target 200 --store candidates

It is resumable: existing experience/candidate names are skipped, so re-running
continues where the last run stopped.
"""

from __future__ import annotations

import argparse
import asyncio
import difflib
import logging
import os
import re
import sys
from pathlib import Path

BACKEND_ROOT = Path(__file__).resolve().parent.parent
if str(BACKEND_ROOT) not in sys.path:
    sys.path.insert(0, str(BACKEND_ROOT))

# --- MMR areas (Mumbai + MMR towns) ----------------------------------------
MMR_AREAS: list[str] = [
    "bandra", "khar", "santacruz", "vile parle", "andheri", "jogeshwari",
    "juhu", "versova", "goregaon", "malad", "kandivali", "borivali", "dahisar",
    "mira road", "bhayandar", "vasai", "virar", "nalasopara", "thane", "mulund",
    "bhandup", "vikhroli", "powai", "ghatkopar", "chembur", "kurla", "sion",
    "wadala", "matunga", "dadar", "mahim", "worli", "lower parel", "parel",
    "prabhadevi", "byculla", "mazgaon", "fort", "colaba", "churchgate",
    "marine drive", "nariman point", "kala ghoda", "malabar hill", "haji ali",
    "mahalaxmi", "tardeo", "grant road", "csmt", "ballard estate", "kalyan",
    "dombivli", "ambernath", "badlapur", "ulhasnagar", "panvel", "kamothe",
    "kharghar", "vashi", "nerul", "belapur", "airoli", "ghansoli", "rabale",
    "kopar khairane", "sanpada", "juinagar", "seawoods", "gorai", "manori",
    "marve", "erangal", "akshi", "alibaug", "lonavala", "khandala", "matheran",
    "karjat", "khopoli", "elephanta", "kanheri",
]

ACTIVITIES: list[str] = [
    "street food", "cafes", "heritage walk", "sunset points", "nightlife",
    "markets", "temples", "art galleries", "beaches", "trekking",
    "cycling routes", "photography spots", "budget eats", "brunch",
    "live music", "bookstores", "theatre", "museums", "parks", "waterfront",
]

TEMPLATES: list[str] = [
    "things to do in {area} mumbai",
    "hidden gems in {area} mumbai",
    "best {activity} in {area} mumbai",
    "underrated {activity} in {area} mumbai",
    "local {activity} spots in {area} mumbai",
]

# Category inference from tags (coarse `Experience.category`).
_CATEGORY_HINTS: list[tuple[str, tuple[str, ...]]] = [
    ("food", ("food", "street_food", "chaat", "cafe", "coffee", "seafood",
              "kebabs", "vegetarian", "non_veg", "dining", "breakfast",
              "lunch", "dinner", "snacks", "mithai")),
    ("nightlife", ("nightlife", "bars", "brewery", "beer", "cocktails",
                   "dive_bars", "lounge", "jazz", "karaoke", "live_music")),
    ("art", ("street_art", "murals", "galleries", "gallery", "modern_art",
             "painting", "theatre", "performance", "opera")),
    ("shopping", ("shopping", "market", "bazaar", "boutiques", "fashion",
                  "antiques", "brands", "mall", "souvenirs", "spices")),
    ("nature", ("nature", "beach", "park", "lake", "forest", "wildlife",
                "gardens", "views", "sunset", "sunrise", "trek", "hiking")),
    ("culture", ("heritage", "history", "historic", "museum", "temple",
                 "dargah", "church", "spiritual", "unesco", "fort", "caves",
                 "architecture", "culture", "festival", "shrine")),
]

_OUTDOOR_TAGS = {
    "outdoor", "beach", "nature", "views", "sunset", "sunrise", "walking",
    "cycling", "hiking", "sea_face", "sea_view", "park", "gardens", "forest",
}

_GENERIC_WORDS = {
    "the", "a", "an", "mumbai", "best", "top", "hidden", "famous", "popular",
    "and", "of", "in", "at", "near", "guide", "review", "reviews",
}


def _norm_name(name: str) -> str:
    text = re.sub(r"[^a-z0-9\s]", " ", (name or "").lower())
    tokens = [t for t in text.split() if t and t not in _GENERIC_WORDS]
    return " ".join(tokens[:6])


def _infer_category(tags: list[str], fallback: str = "culture") -> str:
    tagset = {t.lower() for t in tags}
    for category, hints in _CATEGORY_HINTS:
        if tagset & set(hints):
            return category
    return fallback


def _infer_indoor_outdoor(tags: list[str]) -> str:
    return "outdoor" if {t.lower() for t in tags} & _OUTDOOR_TAGS else "indoor"


def _build_queries(areas: list[str], activities: list[str]) -> list[tuple[str, str]]:
    """Return (query, area) pairs, interleaved so coverage is broad early."""
    pairs: list[tuple[str, str]] = []
    for area in areas:
        for template in TEMPLATES:
            if "{activity}" in template:
                for activity in activities:
                    pairs.append((template.format(area=area, activity=activity), area))
            else:
                pairs.append((template.format(area=area), area))
    return pairs


def _parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--target", type=int, default=1000, help="new rows to add (default 1000)")
    parser.add_argument("--store", choices=["experiences", "candidates"], default="experiences")
    parser.add_argument("--areas", default="", help="comma-separated subset of areas")
    parser.add_argument("--activities", default="", help="comma-separated subset of activities")
    parser.add_argument("--max-results-per-query", type=int, default=8)
    parser.add_argument("--max-queries", type=int, default=0, help="0 = all")
    parser.add_argument("--concurrency", type=int, default=1, help="page fetches in flight")
    parser.add_argument("--no-llm", action="store_true", help="heuristic extraction only")
    parser.add_argument("--no-embed", action="store_true", help="skip embedding generation")
    parser.add_argument(
        "--no-enrich-photos",
        action="store_true",
        help="skip Google Places cover photos -> object storage",
    )
    parser.add_argument("--dry-run", action="store_true", help="extract but write nothing")
    parser.add_argument("--verbose", action="store_true")
    return parser.parse_args()


async def _run(args: argparse.Namespace) -> int:
    # Env must be set before the app settings are first read.
    if args.no_llm:
        os.environ["DISCOVERY_USE_LLM"] = "false"

    from sqlmodel import Session, select

    from app.config import get_settings
    from app.database import engine, init_db
    from app.models import Experience, ScrapedCandidate
    from app.services.discovery import (
        extract_candidates,
        scrape_or_snippet,
        search_searxng,
    )
    from app.services.embeddings import embed_text
    from app.services.geocode import geocode, in_mmr
    from app.services import google_places, photo_enrichment

    settings = get_settings()
    enrich_photos = not args.no_enrich_photos
    init_db()

    areas = [a.strip().lower() for a in args.areas.split(",") if a.strip()] or MMR_AREAS
    activities = [a.strip().lower() for a in args.activities.split(",") if a.strip()] or ACTIVITIES
    queries = _build_queries(areas, activities)
    if args.max_queries:
        queries = queries[: args.max_queries]

    # Seed known names so re-runs skip work.
    known_names: set[str] = set()
    with Session(engine) as session:
        for name in session.exec(select(Experience.name)).all():
            row = name[0] if isinstance(name, tuple) else name
            known_names.add(_norm_name(str(row)))
        if args.store == "candidates":
            for name in session.exec(select(ScrapedCandidate.raw_title)).all():
                row = name[0] if isinstance(name, tuple) else name
                known_names.add(_norm_name(str(row)))

    print(f"Plan: {len(queries)} queries over {len(areas)} areas x {len(activities)} activities")
    print(f"Mode: store={args.store} llm={not args.no_llm} embed={not args.no_embed} "
          f"dry_run={args.dry_run} target={args.target}")
    print(f"Already known: {len(known_names)} names")

    stats = {"queries": 0, "pages": 0, "candidates": 0, "added": 0, "skipped": 0,
             "geocode_failed": 0}
    added: list[str] = []
    seen_urls: set[str] = set()
    semaphore = asyncio.Semaphore(max(1, args.concurrency))
    stop = False

    async def _process_page(page, area):
        async with semaphore:
            return await extract_candidates(page, area)

    for query, area in queries:
        if stop or (args.target and stats["added"] >= args.target):
            break
        stats["queries"] += 1
        try:
            results = await search_searxng(query, max_results=args.max_results_per_query)
        except Exception as exc:  # pragma: no cover - network
            logging.warning("Search failed for %r: %s", query, exc)
            continue
        fresh = [r for r in results if r["url"] not in seen_urls]
        for r in fresh:
            seen_urls.add(r["url"])

        pages = await asyncio.gather(*[scrape_or_snippet(r) for r in fresh])
        extracted = await asyncio.gather(*[_process_page(p, area) for p in pages])
        stats["pages"] += len(pages)

        # Collect candidates from this query's pages.
        batch: list[dict] = [c for _page, cands in zip(pages, extracted) for c in cands]
        stats["candidates"] += len(batch)

        for cand in batch:
            if args.target and stats["added"] >= args.target:
                stop = True
                break
            name = str(cand.get("raw_title") or "").strip()
            key = _norm_name(name)
            if len(key) < 3:
                continue
            # Near-duplicate guard against everything seen/known.
            if key in known_names:
                stats["skipped"] += 1
                continue
            close = difflib.get_close_matches(key, list(known_names), n=1, cutoff=0.92)
            if close:
                stats["skipped"] += 1
                continue

            data = cand.get("extracted_data") or {}
            tags = list(data.get("tags") or [])
            cand_area = cand.get("area") or data.get("area") or area
            coords = await geocode(name, area=str(cand_area))
            if coords is None:
                stats["geocode_failed"] += 1
                continue
            lat, lng = coords
            if not in_mmr(lat, lng):
                continue

            known_names.add(key)
            if args.dry_run:
                stats["added"] += 1
                added.append(f"{name}  [{cand_area}]  {lat:.4f},{lng:.4f}")
                continue

            if args.store == "candidates":
                with Session(engine) as session:
                    session.add(
                        ScrapedCandidate(
                            raw_title=name[:300],
                            url=cand.get("url"),
                            area=str(cand_area)[:100] if cand_area else None,
                            extracted_data={**data, "tags": tags, "lat": lat, "lng": lng},
                            llm_confidence=float(cand.get("llm_confidence") or 0.0),
                            mention_count=1,
                            authenticity_signals={"source": cand.get("url")},
                            status="pending",
                        )
                    )
                    session.commit()
            else:
                description = str(data.get("sentence") or name)[:1000]
                embedding = None
                if not args.no_embed:
                    embedding = await embed_text(
                        f"{name}. {_infer_category(tags)}. {description}. Tags: {', '.join(tags)}"
                    )
                with Session(engine) as session:
                    exp = Experience(
                        name=name[:200],
                        category=_infer_category(tags),
                        lat=lat,
                        lng=lng,
                        avg_cost=int(data.get("avg_cost") or 0),
                        duration_min=60,
                        rating=4.2,
                        description=description,
                        tags=tags,
                        indoor_outdoor=_infer_indoor_outdoor(tags),
                        # Extraction confidence is not a local-gem signal: a
                        # confident parse of a mall is still a mall. Neutral 0.5
                        # keeps scraped rows out of the "Hidden gems" rail.
                        local_gem_score=0.5,
                        embedding=embedding,
                    )
                    session.add(exp)
                    session.commit()
                    session.refresh(exp)
                    # Provenance: keep the raw candidate linked to the experience.
                    session.add(
                        ScrapedCandidate(
                            raw_title=name[:300],
                            url=cand.get("url"),
                            area=str(cand_area)[:100] if cand_area else None,
                            extracted_data={**data, "tags": tags, "lat": lat, "lng": lng},
                            llm_confidence=float(cand.get("llm_confidence") or 0.0),
                            mention_count=1,
                            authenticity_signals={"source": cand.get("url")},
                            status="approved",
                            experience_id=exp.id,
                        )
                    )
                    session.commit()

                    # Self-host the cover photo (Google Places -> S3/MinIO).
                    if enrich_photos and google_places.is_configured():
                        try:
                            await photo_enrichment.enrich_experience_photo(session, exp)
                        except Exception as exc:
                            logger.warning("Photo enrichment failed for %s: %s", name, exc)

            stats["added"] += 1
            added.append(f"{name}  [{cand_area}]")

        if args.verbose or stats["queries"] % 10 == 0:
            print(f"  q={stats['queries']}/{len(queries)} added={stats['added']} "
                  f"candidates={stats['candidates']} skipped={stats['skipped']}")

    print("\n=== Summary ===")
    for k, v in stats.items():
        print(f"  {k:15s} {v}")
    for line in added[:25]:
        print(f"   + {line}")
    if len(added) > 25:
        print(f"   ... and {len(added) - 25} more")
    return 0


def main() -> int:
    args = _parse_args()
    logging.basicConfig(
        level=logging.DEBUG if args.verbose else logging.INFO,
        format="%(levelname)s %(name)s: %(message)s",
    )
    return asyncio.run(_run(args))


if __name__ == "__main__":
    raise SystemExit(main())
