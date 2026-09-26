"""Self-hosted cover photos for experiences.

Looks a venue up in Google Places, downloads its first photo with the
server-side key, and stores the bytes in object storage. The experience then
carries an ``image_key`` and the API derives a media URL from it, so the Flutter
app never talks to Google or S3 directly.

Degrades quietly: no Places key, no photo, a far-away match, or an object-store
failure all just leave the experience on its placeholder image.
"""

from __future__ import annotations

import logging
import mimetypes
from uuid import uuid4

from sqlmodel import Session, select

from app.config import get_settings
from app.models import Experience
from app.services import google_places, storage
from app.services.recommender import haversine_km

logger = logging.getLogger(__name__)

#: Reject a Places match farther than this from the experience's own coords.
MAX_MATCH_DISTANCE_KM = 1.5


def _extension_for(content_type: str) -> str:
    base = (content_type or "image/jpeg").split(";")[0].strip() or "image/jpeg"
    ext = mimetypes.guess_extension(base) or ".jpg"
    return ".jpg" if ext in (".jpe", ".jpeg") else ext


async def enrich_experience_photo(
    session: Session, experience: Experience, *, force: bool = False
) -> bool:
    """Fetch and store a cover photo for one experience. Returns True if stored."""
    settings = get_settings()
    if not settings.photo_enrich_enabled:
        return False
    if experience.image_key and not force:
        return False
    if not google_places.is_configured():
        return False

    results = await google_places.search_places(
        experience.name,
        lat=experience.lat,
        lng=experience.lng,
        radius_m=2000,
        page_size=3,
    )
    best: tuple[float, object] | None = None
    for result in results:
        if not result.photo_name:
            continue
        distance = haversine_km(
            experience.lat, experience.lng, result.lat, result.lng
        )
        if distance <= MAX_MATCH_DISTANCE_KM and (best is None or distance < best[0]):
            best = (distance, result)
    if best is None:
        logger.debug("No nearby Places photo for %s", experience.name)
        return False

    fetched = await google_places.fetch_photo(
        best[1].photo_name,  # type: ignore[attr-defined]
        max_width_px=settings.photo_max_width_px,
    )
    if not fetched:
        return False
    data, content_type = fetched
    key = f"experiences/{experience.id or 'new'}/{uuid4().hex}{_extension_for(content_type)}"
    storage.upload_bytes(key, data, content_type)
    experience.image_key = key
    session.add(experience)
    session.commit()
    session.refresh(experience)
    logger.info("Stored photo for %s at %s", experience.name, key)
    return True


async def enrich_missing_photos(
    session: Session,
    *,
    limit: int = 50,
    only_ids: list[int] | None = None,
) -> dict[str, int]:
    """Backfill photos for experiences that have no image at all yet.

    Curated experiences already ship a local ``image_url``, so they are skipped
    unless ``force`` is used at the call site — this keeps Google Places quota
    for the scraped rows that actually need a cover.
    """
    stmt = select(Experience).where(
        Experience.image_key.is_(None), Experience.image_url.is_(None)
    )
    if only_ids:
        stmt = stmt.where(Experience.id.in_(only_ids))
    rows = list(session.exec(stmt.limit(max(1, limit))).all())

    enriched = 0
    for experience in rows:
        try:
            if await enrich_experience_photo(session, experience):
                enriched += 1
        except Exception as exc:  # pragma: no cover - defensive
            logger.warning("Photo enrichment failed for %s: %s", experience.name, exc)
    return {"attempted": len(rows), "enriched": enriched}
