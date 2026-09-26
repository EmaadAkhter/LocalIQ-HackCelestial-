"""Database seeding utilities for LocalIQ."""

import asyncio
import json
import logging
from datetime import date
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
    PackageBooking,
    Tag,
    User,
)
from app.models_prd import Badge, GuideProfile, Quest, QuestStop

logger = logging.getLogger(__name__)

#: Badge catalogue referenced by ``journey_rules.evaluate_badges``.
SEED_BADGES: list[dict] = [
    {
        "code": "first_steps",
        "name": "First Steps",
        "description": "Completed your first quest.",
        "xp_bonus": 25,
        "tier": "bronze",
    },
    {
        "code": "hidden_gem_hunter",
        "name": "Hidden Gem Hunter",
        "description": "Visited a local gem on a quest.",
        "xp_bonus": 40,
        "tier": "bronze",
    },
    {
        "code": "taste_trail",
        "name": "Taste Trail",
        "description": "Finished a food-focused quest.",
        "xp_bonus": 50,
        "tier": "silver",
    },
    {
        "code": "heritage_walker",
        "name": "Heritage Walker",
        "description": "Finished a culture and history quest.",
        "xp_bonus": 50,
        "tier": "silver",
    },
    {
        "code": "quest_streak_3",
        "name": "Quest Streak",
        "description": "Completed three quests.",
        "xp_bonus": 75,
        "tier": "gold",
    },
]

#: Demo quests. Stops are 1-based positions into the curated dataset so a fresh
#: install has something playable without any authoring.
SEED_QUESTS: list[dict] = [
    {
        "code": "bandra_eats_walk",
        "title": "Bandra Eats Walk",
        "story": (
            "Three cheap, legendary stops within a short walk of each other. "
            "Start hungry."
        ),
        "category": "food",
        "difficulty": "easy",
        "xp_reward": 120,
        "estimated_minutes": 300,
        "estimated_cost": 1500,
        # 1 Elco Pani Puri, 8 Juhu Pav Bhaji, 7 Ghatkopar Khau Galli
        "stops": [1, 8, 7],
    },
    {
        "code": "heritage_walk_south",
        "title": "Heritage Walk South",
        "story": (
            "Fort, a chapel, a lake temple and a promenade: the city's memory "
            "in one walkable loop."
        ),
        "category": "culture",
        "difficulty": "medium",
        "xp_reward": 200,
        "estimated_minutes": 420,
        "estimated_cost": 1200,
        # 47 Bandra Fort, 28 Bandra Chapel, 15 Banganga, 9 Gateway of India
        "stops": [47, 28, 15, 9],
    },
]

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
        # Clear safely (children before parents due to FK order): guide package
        # and journey children first, then the guide/experience rows they share.
        session.exec(delete(GuidePackageStop))  # type: ignore[arg-type]
        session.exec(delete(GuidePackage))  # type: ignore[arg-type]
        session.exec(delete(QuestStop))  # type: ignore[arg-type]
        session.exec(delete(Quest))  # type: ignore[arg-type]
        session.exec(delete(Badge))  # type: ignore[arg-type]
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

    logger.info(
        "Seeded %d experiences, %d guides, %d tags, %d links",
        exp_count,
        guide_count,
        tag_count,
        link_count,
    )
    quest_counts = seed_quests_and_badges()
    logger.info(
        "Seeded %d quests, %d badges", quest_counts["quests"], quest_counts["badges"]
    )
    return {
        "experiences": exp_count,
        "guides": guide_count,
        "tags": tag_count,
        "experience_tags": link_count,
        "quests": quest_counts["quests"],
        "badges": quest_counts["badges"],
    }


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
def seed_quests_and_badges() -> dict[str, int]:
    """Insert the badge catalogue and demo quests (idempotent by code)."""
    init_db()
    with Session(engine) as session:
        for item in SEED_BADGES:
            existing = session.exec(
                select(Badge).where(Badge.code == item["code"])  # type: ignore[union-attr]
            ).first()
            if existing is None:
                session.add(Badge(**item))
        session.commit()

        ordered = session.exec(select(Experience).order_by(Experience.id)).all()  # type: ignore[union-attr]
        quest_count = 0
        for spec in SEED_QUESTS:
            if session.exec(
                select(Quest).where(Quest.code == spec["code"])  # type: ignore[union-attr]
            ).first():
                continue
            quest = Quest(
                code=spec["code"],
                title=spec["title"],
                story=spec["story"],
                category=spec["category"],
                difficulty=spec["difficulty"],
                xp_reward=spec["xp_reward"],
                estimated_minutes=spec["estimated_minutes"],
                estimated_cost=spec["estimated_cost"],
            )
            session.add(quest)
            session.commit()
            session.refresh(quest)
            for position, ref in enumerate(spec["stops"], start=1):
                idx = int(ref) - 1
                if not (0 <= idx < len(ordered)):
                    continue
                session.add(
                    QuestStop(
                        quest_id=quest.id or 0,
                        experience_id=ordered[idx].id or 0,
                        position=position,
                    )
                )
            session.commit()
            quest_count += 1

        badge_count = len(session.exec(select(Badge)).all())
        return {"quests": quest_count, "badges": badge_count}


#: Dev-only demo guide login so the driver trip map is demoable out of the box.
DEMO_GUIDE_EMAIL = "guide.demo@localiq.demo"
DEMO_GUIDE_PASSWORD = "GuideDemo123"


def seed_demo_driver_data(session: Session | None = None) -> dict[str, int]:
    """Give every package one confirmed trip plus a demo guide login.

    The driver map is meaningless with no trips, so in development we fabricate
    one confirmed booking per package (pickup = the package's pickup point, drop
    = same place) and link a demo guide account to the first guide. Guarded to
    development: no demo account or fabricated booking is ever created in
    production or under test.
    """
    from app.config import get_settings

    if get_settings().app_env not in ("development", "dev"):
        return {"trips": 0, "demo_user": 0}

    close_session = session is None
    if session is None:
        init_db()
        session = Session(engine)

    try:
        packages = list(session.exec(select(GuidePackage)).all())
        if not packages:
            return {"trips": 0, "demo_user": 0}

        created_trips = 0
        existing = session.exec(select(func.count()).select_from(PackageBooking)).one()
        if int(existing) == 0:
            for package in packages:
                session.add(
                    PackageBooking(
                        booking_ref=f"DEMO{package.id:04d}",
                        guide_id=package.guide_id,
                        package_id=package.id,
                        pickup_address=package.default_pickup_area,
                        pickup_lat=package.pickup_lat,
                        pickup_lng=package.pickup_lng,
                        date=date.today().isoformat(),
                        start_time="10:00",
                        hours=max(1, int(package.total_duration_hours)),
                        group_size=2,
                        total_price=package.total_price
                        or package.price_per_person * 2,
                        status="confirmed",
                        guest_name="Demo Guest",
                        guest_phone="+91 90000 00000",
                    )
                )
                created_trips += 1
            session.commit()

        demo_user = 0
        existing_user = session.exec(
            select(User).where(User.email == DEMO_GUIDE_EMAIL)
        ).first()
        if existing_user is None:
            first_guide = session.exec(select(Guide)).first()
            if first_guide is not None:
                from app.services.auth import hash_password

                user = User(
                    name=first_guide.name,
                    email=DEMO_GUIDE_EMAIL,
                    password_hash=hash_password(DEMO_GUIDE_PASSWORD),
                    trust_tier="standard",
                    provider="email",
                    tier="plus",
                )
                session.add(user)
                session.commit()
                session.refresh(user)
                profile = session.exec(
                    select(GuideProfile).where(GuideProfile.user_id == user.id)
                ).first()
                if profile is None:
                    session.add(
                        GuideProfile(
                            guide_id=first_guide.id,
                            user_id=user.id,
                            onboarding_state="verified",
                            verification_status="verified",
                            verification_tier="standard",
                            is_published=True,
                            city="Mumbai",
                        )
                    )
                    session.commit()
                demo_user = 1
        return {"trips": created_trips, "demo_user": demo_user}
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
        # Still ensure tags/composite tags, experience links, guide packages and
        # journey content exist so upgrades pick up the newer tables.
        tag_count = seed_tags()
        link_count = backfill_experience_tags()
        package_count = seed_guide_packages()
        quest_counts = seed_quests_and_badges()
        seed_demo_driver_data()
        logger.info(
            "Seeded %d tags, %d links, %d packages, %d quests, %d badges",
            tag_count,
            link_count,
            package_count,
            quest_counts["quests"],
            quest_counts["badges"],
        )
        return None
    logger.info("Experiences table empty: seeding dataset")
    result = seed_database()
    result["guide_packages"] = seed_guide_packages()
    seed_demo_driver_data()
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
