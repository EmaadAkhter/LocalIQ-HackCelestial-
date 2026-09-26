"""Database seeding utilities for LocalIQ."""

import asyncio
import json
import logging
from pathlib import Path

from sqlmodel import Session, delete, func, select

from app.database import engine, init_db
from app.models import (
    CompositeTag,
    Experience,
    ExperienceTag,
    Guide,
    GuidePackage,
    GuidePackageStop,
    Tag,
)

logger = logging.getLogger(__name__)

DATA_PATH = Path(__file__).resolve().parent.parent / "data" / "mumbai_experiences.json"
TAG_TAXONOMY_PATH = Path(__file__).resolve().parent.parent / "data" / "tag_taxonomy.json"
# Fallback when running as `python -m app.seed` from backend/ root.
if not DATA_PATH.exists():
    DATA_PATH = Path("data/mumbai_experiences.json").resolve()
if not TAG_TAXONOMY_PATH.exists():
    TAG_TAXONOMY_PATH = Path("data/tag_taxonomy.json").resolve()


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
        # Clear safely in FK order: guide package children first, then the
        # guide/experience rows they reference.
        session.exec(delete(GuidePackageStop))  # type: ignore[arg-type]
        session.exec(delete(GuidePackage))  # type: ignore[arg-type]
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

        # Tags must exist before linking them to experiences; run inside the
        # same open session so the seeding writes and reads stay consistent.
        tag_count = seed_tags(session)
        link_count = backfill_experience_tags(session)

    logger.info("Seeded %d experiences, %d guides, %d tags, %d links", exp_count, guide_count, tag_count, link_count)

    return {"experiences": exp_count, "guides": guide_count, "tags": tag_count, "experience_tags": link_count}


def load_tag_taxonomy(path: Path = TAG_TAXONOMY_PATH) -> dict:
    """Load the master tag taxonomy JSON."""
    if not path.exists():
        raise FileNotFoundError(f"Tag taxonomy not found: {path}")
    with open(path, encoding="utf-8") as f:
        return json.load(f)


def seed_tags(session: Session | None = None) -> int:
    """Seed the master tag taxonomy and composite tags.

    Idempotent: skips tags that already exist.
    """
    close_session = session is None
    if session is None:
        init_db()
        session = Session(engine)

    try:
        taxonomy = load_tag_taxonomy()
        existing = {t.name for t in session.exec(select(Tag)).all()}
        count = 0
        for item in taxonomy.get("tags", []):
            name = item["name"]
            if name in existing:
                continue
            session.add(
                Tag(
                    name=name,
                    category=item.get("category", "vibe"),
                    facet_type=item.get("facet_type", "user_facing"),
                    description=item.get("description"),
                    weight=float(item.get("weight", 1.0)),
                )
            )
            count += 1
        session.commit()

        existing_composite = {c.name for c in session.exec(select(CompositeTag)).all()}
        for item in taxonomy.get("composite_tags", []):
            name = item["name"]
            if name in existing_composite:
                continue
            session.add(
                CompositeTag(
                    name=name,
                    description=item.get("description"),
                    required_tags=list(item.get("required_tags", [])),
                    optional_tags=list(item.get("optional_tags", [])),
                )
            )
            count += 1
        session.commit()
        return count
    finally:
        if close_session:
            session.close()


def backfill_experience_tags(session: Session | None = None) -> int:
    """Create ExperienceTag rows from the JSON ``tags`` field on experiences."""
    close_session = session is None
    if session is None:
        init_db()
        session = Session(engine)

    try:
        tag_map = {t.name: t.id for t in session.exec(select(Tag)).all()}
        experiences = session.exec(select(Experience)).all()
        existing_links = {
            (et.experience_id, et.tag_id)
            for et in session.exec(select(ExperienceTag)).all()
        }
        count = 0
        for exp in experiences:
            for tag_name in exp.tags or []:
                tag_id = tag_map.get(tag_name)
                if tag_id is None:
                    continue
                key = (exp.id, tag_id)
                if key in existing_links:
                    continue
                session.add(
                    ExperienceTag(
                        experience_id=exp.id,
                        tag_id=tag_id,
                        confidence=1.0,
                        source="seed",
                    )
                )
                existing_links.add(key)
                count += 1
        session.commit()
        return count
    finally:
        if close_session:
            session.close()


async def generate_missing_embeddings(batch_size: int = 16) -> int:
    """Generate embeddings for experiences that don't have one yet.

    Uses the local Ollama model with a deterministic fallback when unavailable.
    """
    from app.services.embeddings import embed_text

    init_db()
    count = 0
    with Session(engine) as session:
        stmt = select(Experience).where(Experience.embedding.is_(None))  # type: ignore[attr-defined]
        missing = list(session.exec(stmt).all())
        if not missing:
            logger.info("No missing embeddings")
            return 0

        for i in range(0, len(missing), batch_size):
            batch = missing[i : i + batch_size]
            texts = [
                f"{exp.name}. {exp.category}. {exp.description}. Tags: {', '.join(exp.tags or [])}"
                for exp in batch
            ]
            vectors = await asyncio.gather(*[embed_text(t) for t in texts])
            for exp, vector in zip(batch, vectors):
                exp.embedding = vector
                count += 1
            session.commit()
            logger.info("Embedded batch %d/%d", i + len(batch), len(missing))
    return count


def seed_guide_packages(session: Session | None = None) -> int:
    """Generate one end-to-end package per guide when none exist.

    Each package picks the guide's own experience (when linked) plus up to two
    nearby experiences as stops, giving the marketplace realistic demo data
    without hand-authoring routes.
    """
    close_session = session is None
    if session is None:
        init_db()
        session = Session(engine)

    try:
        existing = session.exec(select(func.count()).select_from(GuidePackage)).one()
        if int(existing) > 0:
            return 0

        guides = list(session.exec(select(Guide)).all())
        experiences = list(session.exec(select(Experience)).all())
        if not guides or not experiences:
            return 0

        from app.services.recommender import haversine_km

        by_id = {e.id: e for e in experiences}
        count = 0
        for guide in guides:
            anchor = by_id.get(guide.experience_id) or experiences[0]
            # Pick the two nearest other experiences as additional stops.
            others = sorted(
                (e for e in experiences if e.id != anchor.id),
                key=lambda e: haversine_km(anchor.lat, anchor.lng, e.lat, e.lng),
            )[:2]
            stops = [anchor, *others]
            package = GuidePackage(
                guide_id=guide.id,
                title=f"{anchor.name.split(',')[0]} & Neighbourhood Walk",
                description=(
                    f"A {guide.specialty} route with {guide.name}, starting near "
                    f"{anchor.name} and covering {len(stops)} stops."
                ),
                default_pickup_area=anchor.name.split(",")[-1].strip() or "Mumbai",
                pickup_lat=anchor.lat,
                pickup_lng=anchor.lng,
                total_duration_hours=round(sum(e.duration_min for e in stops) / 60.0, 1) or 3.0,
                price_per_person=max(500, int(guide.rate_per_hour * 2)),
                max_group_size=8,
                languages=guide.languages or ["English"],
                inclusions=["Guide", "Route planning", "Local tips"],
                is_active=True,
            )
            session.add(package)
            session.commit()
            session.refresh(package)
            for seq, exp in enumerate(stops, start=1):
                session.add(
                    GuidePackageStop(
                        package_id=package.id,
                        experience_id=exp.id,
                        sequence=seq,
                        segment_type="experience",
                        location_name=exp.name,
                        lat=exp.lat,
                        lng=exp.lng,
                        duration_min=exp.duration_min,
                    )
                )
            session.commit()
            count += 1
        return count
    finally:
        if close_session:
            session.close()


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
        # Still ensure tags/composite tags, experience links and guide
        # packages exist so upgrades pick up the newer tables.
        tag_count = seed_tags()
        link_count = backfill_experience_tags()
        package_count = seed_guide_packages()
        logger.info(
            "Seeded %d tags, %d experience-tag links, %d guide packages",
            tag_count,
            link_count,
            package_count,
        )
        return None
    logger.info("Experiences table empty: seeding dataset")
    result = seed_database()
    result["guide_packages"] = seed_guide_packages()
    return result


if __name__ == "__main__":
    import sys

    logging.basicConfig(level=logging.INFO)

    if "--embeddings" in sys.argv:
        count = asyncio.run(generate_missing_embeddings())
        print(f"Generated embeddings for {count} experiences")
    elif "--force" in sys.argv:
        result = seed_database()
        print(f"Seeded: {result['experiences']} experiences, {result['guides']} guides, {result['tags']} tags")
    else:
        result = seed_if_empty()

        if result is None:
            print("Seed skipped: table not empty (use --force to reseed)")
        else:
            print(
                f"Seeded: {result['experiences']} experiences, "
                f"{result['guides']} guides, {result['tags']} tags"
            )
