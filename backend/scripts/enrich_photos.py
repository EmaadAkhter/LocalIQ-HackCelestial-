#!/usr/bin/env python3
"""Backfill self-hosted cover photos for experiences.

Looks each experience up in Google Places, downloads its first photo, and
stores it in the configured object store (S3/MinIO or the filesystem fallback).
Resumable: experiences that already have an ``image_key`` are skipped.

Examples
--------
    # Enrich up to 50 experiences that have no photo yet.
    python scripts/enrich_photos.py --limit 50

    # Re-fetch photos even for experiences that already have one.
    python scripts/enrich_photos.py --limit 20 --force

    # Only specific ids.
    python scripts/enrich_photos.py --ids 1,2,3
"""

from __future__ import annotations

import argparse
import asyncio
import logging
import os
import sys
from pathlib import Path

BACKEND_ROOT = Path(__file__).resolve().parent.parent
if str(BACKEND_ROOT) not in sys.path:
    sys.path.insert(0, str(BACKEND_ROOT))


def _parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter
    )
    parser.add_argument("--limit", type=int, default=50, help="max experiences to process")
    parser.add_argument("--ids", default="", help="comma-separated experience ids")
    parser.add_argument("--force", action="store_true", help="re-fetch existing photos")
    parser.add_argument("--verbose", action="store_true")
    return parser.parse_args()


async def _run(args: argparse.Namespace) -> int:
    from sqlmodel import Session, select

    from app.database import engine, init_db
    from app.models import Experience
    from app.services import google_places, photo_enrichment, storage

    logging.basicConfig(
        level=logging.DEBUG if args.verbose else logging.INFO,
        format="%(levelname)s %(name)s: %(message)s",
    )
    init_db()

    if not google_places.is_configured():
        print("GOOGLE_PLACES_API_KEY is not set — nothing to fetch.")
        return 1

    print(f"Storage backend: {storage.backend_name()}")
    ids = [int(x) for x in args.ids.split(",") if x.strip()] or None

    with Session(engine) as session:
        if args.force:
            stmt = select(Experience)
            if ids:
                stmt = stmt.where(Experience.id.in_(ids))
            rows = list(session.exec(stmt.limit(max(1, args.limit))).all())
            enriched = 0
            for experience in rows:
                if await photo_enrichment.enrich_experience_photo(
                    session, experience, force=True
                ):
                    enriched += 1
            stats = {"attempted": len(rows), "enriched": enriched}
        else:
            stats = await photo_enrichment.enrich_missing_photos(
                session, limit=args.limit, only_ids=ids
            )

    print(f"\n=== Photo enrichment ===")
    print(f"  attempted: {stats['attempted']}")
    print(f"  enriched:  {stats['enriched']}")
    return 0


def main() -> int:
    return asyncio.run(_run(_parse_args()))


if __name__ == "__main__":
    raise SystemExit(main())
