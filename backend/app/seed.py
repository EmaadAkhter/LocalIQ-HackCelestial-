"""Database seeding utilities for LocalIQ."""

import json
import logging
from pathlib import Path

from sqlmodel import Session, delete, func, select

from app.database import engine, init_db
from app.models import Experience, Guide

logger = logging.getLogger(__name__)

DATA_PATH = Path(__file__).resolve().parent.parent / "data" / "mumbai_experiences.json"
# Fallback when running as `python -m app.seed` from backend/ root.
if not DATA_PATH.exists():
    DATA_PATH = Path("data/mumbai_experiences.json").resolve()


def load_dataset(path: Path = DATA_PATH) -> tuple[list[dict], list[dict]]:
    """Load and validate the JSON dataset.

    Supports both formats:
      - {"experiences": [...], "guides": [...]}
      - [...]  (experiences list only)
    """
    if not path.exists():
        raise FileNotFoundError(f"Dataset not found: {path}")
    with open(path, encoding="utf-8") as f:
        raw = json.load(f)

    if isinstance(raw, dict):
        experiences = raw.get("experiences", [])
        guides = raw.get("guides", [])
    elif isinstance(raw, list):
        experiences = raw
        guides = []
    else:
        raise ValueError("Dataset must be a list or a dict with 'experiences' key")

    if not experiences:
        raise ValueError("Dataset contains no experiences")
    return experiences, guides


def seed_database() -> dict[str, int]:
    """Clear seed tables and insert dataset. Repeatable, no duplicates."""
    init_db()
    experiences_raw, guides_raw = load_dataset()

    with Session(engine) as session:
        # Clear safely (guides first due to FK).
        session.exec(delete(Guide))  # type: ignore[arg-type]
        session.exec(delete(Experience))  # type: ignore[arg-type]
        session.commit()

        exp_count = 0
        for item in experiences_raw:
            exp = Experience(
                name=item.get("name", "Untitled"),
                category=str(item.get("category", "culture")).lower().strip(),
                lat=float(item.get("lat", 19.0760)),
                lng=float(item.get("lng", 72.8777)),
                avg_cost=int(item.get("avg_cost", 0)),
                duration_min=int(item.get("duration_min", 60)),
                open_time=str(item.get("open_time", "09:00")),
                close_time=str(item.get("close_time", "21:00")),
                rating=float(item.get("rating", 4.0)),
                description=str(item.get("description", "")),
                image_url=item.get("image_url") or None,
                tags=list(item.get("tags", []) or []),
                accessibility_flags=list(item.get("accessibility_flags", []) or []),
                indoor_outdoor=str(item.get("indoor_outdoor", "indoor")).lower(),
                local_gem_score=float(item.get("local_gem_score", 0.5)),
            )
            session.add(exp)
            exp_count += 1
        session.commit()

        # Map 1-based dataset order to DB ids for guide linking.
        # Since we cleared the table, autoincrement may not restart at 1 on SQLite.
        # So fetch ordered experiences to resolve guide experience_id references.
        ordered = session.exec(select(Experience).order_by(Experience.id)).all()  # type: ignore[union-attr]

        def resolve_exp_id(ref) -> int | None:
            if ref is None:
                return None
            try:
                idx = int(ref) - 1  # dataset uses 1-based positions
            except (TypeError, ValueError):
                return None
            if 0 <= idx < len(ordered):
                return ordered[idx].id
            return None

        guide_count = 0
        for g in guides_raw:
            guide = Guide(
                experience_id=resolve_exp_id(g.get("experience_id")),
                name=g.get("name", "Local Guide"),
                photo=g.get("photo") or None,
                languages=list(g.get("languages", []) or []),
                specialty=g.get("specialty", "local culture"),
                rate_per_hour=int(g.get("rate_per_hour", 800)),
                rating=float(g.get("rating", 4.5)),
            )
            session.add(guide)
            guide_count += 1
        session.commit()

    logger.info("Seeded %d experiences, %d guides", exp_count, guide_count)
    return {"experiences": exp_count, "guides": guide_count}


def count_experiences() -> int:
    """Return the number of experience rows currently stored."""
    init_db()
    with Session(engine) as session:
        return int(session.exec(select(func.count()).select_from(Experience)).one())


def seed_if_empty() -> dict[str, int] | None:
    """Seed only when the experiences table is empty.

    Safe to call on every startup: it never duplicates or overwrites data.
    Returns the seed counts, or None when seeding was skipped.
    """
    if count_experiences() > 0:
        logger.info("Seed skipped: experiences table already populated")
        return None
    logger.info("Experiences table empty: seeding dataset")
    return seed_database()


if __name__ == "__main__":
    import sys

    logging.basicConfig(level=logging.INFO)

    if "--force" in sys.argv:
        result = seed_database()
    else:
        result = seed_if_empty()

    if result is None:
        print("Seed skipped: table not empty (use --force to reseed)")
    else:
        print(f"Seeded: {result['experiences']} experiences, {result['guides']} guides")
