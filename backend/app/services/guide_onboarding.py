"""Fast guide onboarding.

Speed is the whole point: a guide should go from signup to *pending review* in
three short steps, then start earning as soon as an admin approves.

    1. start     -> draft Guide + GuideProfile
    2. documents -> upload the driver's licence + guide licence to object storage
    3. apply     -> areas, niches, rate; state -> pending

Document bytes live in object storage; the database only keeps the key and a
little metadata (type, size, upload time). Nothing sensitive is ever rendered
back to a client.
"""

from __future__ import annotations

import logging
import mimetypes
from datetime import datetime, timezone
from typing import Any
from uuid import uuid4

from sqlmodel import Session, select

from app.models import Guide, User
from app.models_prd import GuideProfile
from app.services import storage
from app.services.recommender import KNOWN_AREAS

logger = logging.getLogger(__name__)

DOCUMENT_KINDS = ("driver_license", "guide_license")
MAX_DOCUMENT_BYTES = 8 * 1024 * 1024
ALLOWED_CONTENT_TYPES = ("image/jpeg", "image/png", "image/webp", "application/pdf")

#: Specialities a guide can claim. Mirrors the discovery category vocabulary.
NICHE_OPTIONS: list[str] = [
    "street_food",
    "food",
    "heritage",
    "culture",
    "art",
    "history",
    "nightlife",
    "shopping",
    "nature",
    "adventure",
    "photography",
    "wellness",
]


def _now() -> datetime:
    return datetime.now(timezone.utc)


def area_options() -> list[str]:
    return sorted(name.replace("_", " ").title() for name in KNOWN_AREAS)


def get_profile(session: Session, user: User) -> GuideProfile | None:
    if user.id is None:
        return None
    return session.exec(
        select(GuideProfile).where(GuideProfile.user_id == user.id)
    ).first()


def start(
    session: Session,
    user: User,
    *,
    name: str | None = None,
    languages: list[str] | None = None,
    city: str = "Mumbai",
    bio: str = "",
) -> GuideProfile:
    """Create (or return) the draft guide + profile for this user."""
    existing = get_profile(session, user)
    if existing is not None:
        return existing

    guide = Guide(
        name=(name or user.name)[:120],
        specialty="",
        languages=list(languages or []),
        rate_per_hour=800,
    )
    session.add(guide)
    session.commit()
    session.refresh(guide)

    profile = GuideProfile(
        guide_id=guide.id or 0,
        user_id=user.id,
        onboarding_state="signup",
        verification_status="unverified",
        verification_tier="basic",
        bio=bio,
        city=city,
    )
    session.add(profile)
    session.commit()
    session.refresh(profile)
    logger.info("Guide onboarding started: guide=%s user=%s", guide.id, user.id)
    return profile


def upload_document(
    session: Session,
    user: User,
    *,
    kind: str,
    filename: str,
    content_type: str | None,
    data: bytes,
) -> dict[str, Any]:
    """Store one licence document and record its metadata."""
    if kind not in DOCUMENT_KINDS:
        raise ValueError(f"kind must be one of {', '.join(DOCUMENT_KINDS)}")
    if not data:
        raise ValueError("the uploaded document is empty")
    if len(data) > MAX_DOCUMENT_BYTES:
        raise ValueError("document too large (max 8 MB)")

    resolved_type = (content_type or "").split(";")[0].strip().lower()
    if resolved_type not in ALLOWED_CONTENT_TYPES:
        raise ValueError("unsupported document type (use JPEG, PNG, WebP or PDF)")

    profile = get_profile(session, user)
    if profile is None:
        raise LookupError("start guide onboarding first")

    extension = mimetypes.guess_extension(resolved_type) or ".bin"
    key = f"guides/{profile.guide_id}/{kind}-{uuid4().hex}{extension}"
    storage.upload_bytes(key, data, resolved_type)

    documents = dict(profile.documents_json or {})
    documents[kind] = {
        "key": key,
        "content_type": resolved_type,
        "size": len(data),
        "filename": (filename or kind)[:200],
        "uploaded_at": _now().isoformat(),
    }
    profile.documents_json = documents
    if kind == "driver_license":
        profile.driver_license_key = key
    else:
        profile.guide_license_key = key
    session.add(profile)
    session.commit()
    session.refresh(profile)
    return {"kind": kind, "key": key, "content_type": resolved_type, "size": len(data)}


def apply(
    session: Session,
    user: User,
    *,
    areas: list[str],
    niches: list[str],
    rate_per_hour: int | None = None,
    bio: str | None = None,
    languages: list[str] | None = None,
) -> GuideProfile:
    """Submit the application: areas + niches, with both documents present."""
    profile = get_profile(session, user)
    if profile is None:
        raise LookupError("start guide onboarding first")
    if not profile.driver_license_key or not profile.guide_license_key:
        raise ValueError("both the driver's licence and the guide licence are required")
    cleaned_areas = [a.strip() for a in areas if a and a.strip()]
    if not cleaned_areas:
        raise ValueError("select at least one area you cover")
    cleaned_niches = [n.strip() for n in niches if n and n.strip()]

    profile.specialization_areas = cleaned_areas
    profile.niches = cleaned_niches
    profile.onboarding_state = "id_uploaded"
    profile.verification_status = "pending"
    profile.submitted_at = _now()
    session.add(profile)

    guide = session.get(Guide, profile.guide_id)
    if guide is not None:
        guide.areas_covered = cleaned_areas
        if cleaned_niches:
            guide.specialty = cleaned_niches[0]
        if bio is not None:
            guide.bio = bio[:2000]
        if languages:
            guide.languages = list(languages)
        if rate_per_hour is not None:
            guide.rate_per_hour = max(0, int(rate_per_hour))
        session.add(guide)

    session.commit()
    session.refresh(profile)
    logger.info("Guide %s applied (areas=%s niches=%s)", profile.guide_id, cleaned_areas, cleaned_niches)
    return profile


def verify(
    session: Session,
    guide_id: int,
    *,
    approve: bool,
    notes: str | None = None,
    tier: str = "standard",
) -> GuideProfile:
    """Admin decision on a submitted application."""
    profile = session.exec(
        select(GuideProfile).where(GuideProfile.guide_id == guide_id)
    ).first()
    if profile is None:
        raise LookupError("guide profile not found")

    profile.admin_notes = (notes or "")[:1000] or None
    profile.reviewed_at = _now()
    if approve:
        profile.onboarding_state = "verified"
        profile.verification_status = "verified"
        profile.verification_tier = tier
        profile.is_published = True
        profile.verified_at = _now()
        user = session.get(User, profile.user_id) if profile.user_id else None
        if user is not None:
            user.trust_tier = "standard"
            session.add(user)
        guide = session.get(Guide, guide_id)
        if guide is not None:
            guide.verification_status = "verified"
            session.add(guide)
    else:
        profile.onboarding_state = "rejected"
        profile.verification_status = "rejected"
        profile.verification_tier = "basic"
        profile.is_published = False
    session.add(profile)
    session.commit()
    session.refresh(profile)
    return profile


def status(session: Session, user: User) -> dict[str, Any]:
    """Current application state for the signed-in guide."""
    profile = get_profile(session, user)
    if profile is None:
        return {
            "state": "not_started",
            "verification_status": "unverified",
            "required_documents": list(DOCUMENT_KINDS),
            "documents": {},
            "has_driver_license": False,
            "has_guide_license": False,
            "areas": [],
            "niches": [],
            "can_submit": False,
            "is_published": False,
        }
    documents = dict(profile.documents_json or {})
    return {
        "guide_id": profile.guide_id,
        "state": profile.onboarding_state,
        "verification_status": profile.verification_status,
        "verification_tier": profile.verification_tier,
        "required_documents": list(DOCUMENT_KINDS),
        "documents": documents,
        "has_driver_license": bool(profile.driver_license_key),
        "has_guide_license": bool(profile.guide_license_key),
        "areas": list(profile.specialization_areas or []),
        "niches": list(profile.niches or []),
        "can_submit": bool(
            profile.driver_license_key and profile.guide_license_key
        ),
        "is_published": profile.is_published,
        "submitted_at": profile.submitted_at.isoformat() if profile.submitted_at else None,
        "admin_notes": profile.admin_notes,
    }
