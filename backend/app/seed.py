"""Database seeding utilities for LocalIQ."""

import json
import logging
from pathlib import Path

from sqlmodel import Session, delete, func, select

from app.database import engine, init_db
from app.models import Experience, Guide
from app.models_prd import Badge, Quest, QuestStop

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
        # Clear safely (children before parents due to FK).
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

    logger.info("Seeded %d experiences, %d guides", exp_count, guide_count)
    quest_counts = seed_quests_and_badges()
    logger.info(
        "Seeded %d quests, %d badges", quest_counts["quests"], quest_counts["badges"]
    )
    return {
        "experiences": exp_count,
        "guides": guide_count,
        "quests": quest_counts["quests"],
        "badges": quest_counts["badges"],
    }


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
