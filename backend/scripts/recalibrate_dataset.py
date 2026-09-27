"""Re-calibrate the curated dataset so the Home rails can actually differ.

Three fields were flat or missing, which made every rail look identical:

* ``local_gem_score`` was clustered 0.60-0.95, so ``localFavourite`` was true for
  47 of 48 places and "Hidden gems" was the same as "Recommended".
* ``crowd_density_level`` was never seeded, so every venue scored ``MEDIUM`` and
  the Right Now engine emitted the same "Weekend — busier than usual" line.
* ``best_visit_time`` was missing, so cards had no practical tip.

This rewrites ``data/mumbai_experiences.json`` (the source of truth for a fresh
install) with hand-curated values.

Usage::

    python scripts/recalibrate_dataset.py              # write the JSON
    python scripts/recalibrate_dataset.py --dry-run    # print the plan only
    python scripts/recalibrate_dataset.py --apply-db   # also update the database
"""

from __future__ import annotations

import argparse
import json
from pathlib import Path

DATA_PATH = Path(__file__).resolve().parent.parent / "data" / "mumbai_experiences.json"

#: name -> new local_gem_score. Anything not listed is left untouched.
GEM_SCORES: dict[str, float] = {
    # --- Genuine hidden gems (>= 0.85): local, offbeat, few tourists ---------
    "Banganga & Walkeshwar Walk": 0.95,
    "Chor Bazaar Antique Hunt": 0.93,
    "Mohammed Ali Road Food Walk": 0.92,
    "Versova Fishing Village Morning": 0.91,
    "Dadar Maharashtrian Food Trail": 0.90,
    "Ghatkopar Khau Galli": 0.90,
    "Dadar Flower & Plaza Market": 0.89,
    "Bandra Chapel Road Street Art": 0.88,
    "Kala Ghoda Creative Lanes": 0.88,
    "Waterfield Road Karaoke Lane": 0.86,
    "Carter Road Live Gig Evening": 0.86,
    # --- Semi-local (0.70 - 0.84) -------------------------------------------
    "Elco Pani Puri & Chaat, Bandra": 0.84,
    "Bademiya Late-Night Kebabs, Colaba": 0.82,
    "Britannia & Co, Ballard Estate": 0.82,
    "Crawford Market Spice Run": 0.80,
    "Jehangir Art Gallery + Kala Ghoda": 0.78,
    "Zaveri Bazaar & Kalbadevi Lanes": 0.78,
    "Fort Jazz & Heritage Bar Night": 0.76,
    "Royal Opera House Show": 0.76,
    "Bandra Nightlife Crawl": 0.74,
    "Hanging Gardens + Sunset Point": 0.72,
    "Sanjay Gandhi NP Trail": 0.70,
    # --- Mainstream / touristy (< 0.70) -------------------------------------
    "Leopold Cafe, Colaba": 0.66,
    "Global Vipassana Pagoda Trip": 0.64,
    "Prithvi Theatre Evening, Juhu": 0.64,
    "Carter Road Sunset Promenade": 0.66,
    "Bandstand Promenade Evening": 0.64,
    "Versova Beach Shack Night": 0.62,
    "Juhu Beach Pav Bhaji Sunset": 0.60,
    "Kanheri Caves Half-Day": 0.60,
    "Haji Ali Dargah + Dhobi Ghat": 0.58,
    "NGMA Mumbai Hour": 0.58,
    "Hill Road Budget Fashion": 0.58,
    "Powai Lake Cycling Loop": 0.58,
    "Siddhivinayak Morning Darshan": 0.56,
    "CSMT Heritage Walk": 0.56,
    "CSMVS Museum Mile": 0.54,
    "Bandra Fort & Sea-Link View": 0.54,
    "Linking Road Fashion Crawl": 0.52,
    "Elephanta Caves Ferry Day": 0.50,
    "Colaba Causeway Bargain Hunt": 0.50,
    "Marine Drive Sunrise Walk": 0.48,
    "Marine Drive Midnight Lounge": 0.48,
    "NCPA Performance Night": 0.46,
    "Andheri West Rooftop Circuit": 0.44,
    "Gateway of India Sunrise": 0.40,
    "Lower Parel Brewery Hop": 0.42,
    "Phoenix Palladium Mall Crawl": 0.28,
}

#: name -> crowd level. LOW = quiet, HIGH = busy. Everything else stays MEDIUM.
CROWD_LEVELS: dict[str, str] = {
    **{
        name: "LOW"
        for name in (
            "Jehangir Art Gallery + Kala Ghoda",
            "NGMA Mumbai Hour",
            "Global Vipassana Pagoda Trip",
            "Kanheri Caves Half-Day",
            "Sanjay Gandhi NP Trail",
            "Banganga & Walkeshwar Walk",
            "Chor Bazaar Antique Hunt",
            "CSMVS Museum Mile",
            "Prithvi Theatre Evening, Juhu",
            "NCPA Performance Night",
            "Royal Opera House Show",
        )
    },
    **{
        name: "HIGH"
        for name in (
            "CSMT Heritage Walk",
            "Gateway of India Sunrise",
            "Marine Drive Sunrise Walk",
            "Juhu Beach Pav Bhaji Sunset",
            "Colaba Causeway Bargain Hunt",
            "Crawford Market Spice Run",
            "Mohammed Ali Road Food Walk",
            "Linking Road Fashion Crawl",
            "Zaveri Bazaar & Kalbadevi Lanes",
            "Phoenix Palladium Mall Crawl",
            "Siddhivinayak Morning Darshan",
            "Haji Ali Dargah + Dhobi Ghat",
            "Bandra Fort & Sea-Link View",
            "Bandstand Promenade Evening",
            "Elephanta Caves Ferry Day",
            "Dadar Flower & Plaza Market",
        )
    },
}

#: name -> best time to visit, shown as the card's practical tip.
BEST_VISIT_TIMES: dict[str, str] = {
    "Marine Drive Sunrise Walk": "Just before sunrise, around 06:00",
    "Gateway of India Sunrise": "Early morning before the crowds",
    "Siddhivinayak Morning Darshan": "Tuesdays are busiest — go before 07:00",
    "Crawford Market Spice Run": "Mornings on weekdays",
    "Mohammed Ali Road Food Walk": "After 20:00; spectacular during Ramadan",
    "Juhu Beach Pav Bhaji Sunset": "An hour before sunset",
    "Banganga & Walkeshwar Walk": "Late afternoon, around 16:30",
    "Chor Bazaar Antique Hunt": "Friday mornings for the flea market",
    "Dadar Flower & Plaza Market": "Before 07:00 when the market is loudest",
    "Jehangir Art Gallery + Kala Ghoda": "Weekday afternoons; closed Mondays",
    "Bandra Chapel Road Street Art": "Golden hour for the murals",
    "Carter Road Sunset Promenade": "Sunset, obviously",
    "Kanheri Caves Half-Day": "Start by 08:00 to beat the heat",
    "CSMVS Museum Mile": "Weekday mornings; closed Mondays",
    "Prithvi Theatre Evening, Juhu": "Book the 18:00 or 21:00 show",
    "Phoenix Palladium Mall Crawl": "Weekday afternoons",
}


def _load() -> tuple[dict | list, list[dict]]:
    raw = json.loads(DATA_PATH.read_text(encoding="utf-8"))
    experiences = raw["experiences"] if isinstance(raw, dict) else raw
    return raw, experiences


def apply_to_database() -> int:
    """Update the three fields in place on the configured database.

    A targeted UPDATE by name (rather than ``seed_database``) so user accounts,
    favourites and journey rows survive the re-calibration.
    """
    from sqlmodel import Session, select

    from app.database import engine, init_db
    from app.models import Experience

    init_db()
    updated = 0
    with Session(engine) as session:
        for exp in session.exec(select(Experience)).all():
            new_gem = GEM_SCORES.get(exp.name)
            new_crowd = CROWD_LEVELS.get(exp.name)
            changed = False
            if new_gem is not None and exp.local_gem_score != new_gem:
                exp.local_gem_score = new_gem
                changed = True
            if new_crowd is not None and exp.crowd_density_level != new_crowd:
                exp.crowd_density_level = new_crowd
                changed = True
            if changed:
                session.add(exp)
                updated += 1
        session.commit()
    return updated


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--dry-run", action="store_true", help="print without writing")
    parser.add_argument("--apply-db", action="store_true", help="also update the database")
    args = parser.parse_args()

    raw, experiences = _load()
    missing: list[str] = []
    changed = 0
    for exp in experiences:
        name = exp.get("name", "")
        if name not in GEM_SCORES:
            missing.append(name)
            continue
        updates = {
            "local_gem_score": GEM_SCORES[name],
            "crowd_density_level": CROWD_LEVELS.get(name, exp.get("crowd_density_level", "MEDIUM")),
        }
        if name in BEST_VISIT_TIMES:
            updates["best_visit_time"] = BEST_VISIT_TIMES[name]
        if any(exp.get(k) != v for k, v in updates.items()):
            if args.dry_run:
                print(f"{name}: {updates}")
            exp.update(updates)
            changed += 1

    if missing:
        print(f"WARNING: {len(missing)} places had no mapping: {missing}")

    gems = sum(1 for e in experiences if float(e.get("local_gem_score", 0)) >= 0.85)
    crowd = {e.get("crowd_density_level", "MEDIUM") for e in experiences}
    print(f"{changed} rows updated; {gems}/{len(experiences)} true gems; crowd levels: {sorted(crowd)}")

    if not args.dry_run:
        DATA_PATH.write_text(json.dumps(raw, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
        print(f"Wrote {DATA_PATH}")

    if args.apply_db:
        print(f"Database rows updated: {apply_to_database()}")


if __name__ == "__main__":
    main()
