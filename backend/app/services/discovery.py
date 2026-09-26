"""SearXNG-based activities discovery pipeline.

The pipeline is self-hosted end to end and never requires paid APIs:

1. Query SearXNG for area + activity keywords.
2. Fetch each result page and read its text.
3. Extract structured candidates with the local LLM (Ollama), constrained to
   the master tag taxonomy and known Mumbai areas.
4. Fall back to a deterministic heuristic extractor when the model is
   unavailable (no Ollama, timeout, unparseable JSON, tests).
5. Normalize tags against the taxonomy and store ``ScrapedCandidate``,
   ``DiscoverySource`` and ``CandidateCitation`` rows for admin curation.

When SearXNG is unavailable the endpoint degrades gracefully and returns an
empty list.
"""

from __future__ import annotations

import asyncio
import json
import logging
import re
from datetime import datetime, timezone
from functools import lru_cache
from pathlib import Path
from typing import Any
from urllib.parse import urljoin, urlparse

import httpx
from sqlmodel import Session, select

from app.config import get_settings
from app.database import engine
from app.models import ScrapedCandidate, CandidateCitation, DiscoverySource

logger = logging.getLogger(__name__)

_DATA_DIR = Path(__file__).resolve().parent.parent.parent / "data"
_TAXONOMY_PATH = _DATA_DIR / "tag_taxonomy.json"

# Heuristic keyword -> canonical taxonomy tag. Every value must be a valid tag
# in data/tag_taxonomy.json; _normalize_tags drops anything else.
_TAG_HINTS: dict[str, list[str]] = {
    "heritage": ["heritage", "historical", "colonial", "victorian", "fort"],
    "museum": ["museum"],
    "street_food": ["street food", "chaat", "vada pav", "pani puri", "kebab", "food walk", "khau galli"],
    "food": ["food", "restaurant", "eatery", "cuisine", "dining"],
    "cafe": ["cafe", "coffee"],
    "nightlife": ["nightlife", "night out", "party"],
    "bars": ["bar", "pub", "cocktail", "dive bar"],
    "brewery": ["brewery", "brewing", "beer"],
    "live_music": ["live music", "gig", "jazz", "karaoke"],
    "beach": ["beach"],
    "nature": ["park", "garden", "lake", "forest", "wildlife", "trail"],
    "cycling": ["cycling", "bicycle", "bike ride"],
    "sunset": ["sunset"],
    "sunrise": ["sunrise"],
    "street_art": ["street art", "mural", "graffiti"],
    "galleries": ["gallery", "galleries", "art show"],
    "modern_art": ["modern art", "contemporary art"],
    "theatre": ["theatre", "theater", "performance", "opera"],
    "shopping": ["shopping", "boutique", "fashion", "mall", "brands"],
    "market": ["market", "bazaar", "bargain"],
    "temple": ["temple", "dargah", "church", "shrine"],
    "spiritual": ["spiritual", "meditation", "yoga"],
    "landmark": ["landmark", "monument", "gateway", "iconic"],
    "views": ["viewpoint", "view point", "panoramic", "sea view", "skyline"],
    "photography": ["photography", "photogenic", "photo spot"],
    "caves": ["caves", "rock-cut"],
}

# Patterns that help skip generic/non-place results.
_SKIP_URL_RE = re.compile(
    r"(reddit\.com|facebook\.com|twitter\.com|x\.com|youtube\.com|instagram\.com)", re.I
)

_LLM_SYSTEM = (
    "You are a precise travel data extractor for Mumbai. You read a web page "
    "and return only real, visitable places that are explicitly mentioned. "
    "Never invent places. Respond with JSON only."
)


def _http_client() -> httpx.AsyncClient:
    return httpx.AsyncClient(
        timeout=get_settings().searxng_timeout_seconds,
        follow_redirects=True,
        headers={
            "User-Agent": (
                "Mozilla/5.0 (compatible; LocalIQBot/0.1; +https://localiq.example.com)"
            ),
        },
    )


# ---------------------------------------------------------------------------
# Taxonomy + area vocabulary (shared by the LLM prompt and normalizer)
# ---------------------------------------------------------------------------


@lru_cache(maxsize=1)
def _taxonomy_tag_names() -> frozenset[str]:
    """Valid tag names from the master taxonomy (cached)."""
    try:
        with open(_TAXONOMY_PATH, encoding="utf-8") as f:
            taxonomy = json.load(f)
        names = {t["name"] for t in taxonomy.get("tags", []) if t.get("name")}
        if names:
            return frozenset(names)
    except Exception as exc:  # pragma: no cover - defensive
        logger.warning("Could not load tag taxonomy for discovery: %s", exc)
    # Last resort: the heuristic keys, so we never block on a missing file.
    return frozenset(_TAG_HINTS.keys())


def _known_areas() -> dict[str, tuple[float, float]]:
    from app.services.recommender import KNOWN_AREAS

    return KNOWN_AREAS


def _normalize_tag_list(values: Any) -> list[str]:
    """Keep only canonical tag names, normalized to underscore form."""
    valid = _taxonomy_tag_names()
    tags: list[str] = []
    if isinstance(values, str):
        values = [values]
    if not isinstance(values, (list, tuple, set)):
        return tags
    for raw in values:
        if raw is None:
            continue
        key = str(raw).strip().lower().replace(" ", "_").replace("-", "_")
        if key in valid and key not in tags:
            tags.append(key)
    return tags


def _resolve_area(value: Any) -> str | None:
    """Map a free-text area to a known Mumbai anchor name."""
    if value is None:
        return None
    key = str(value).strip().lower()
    if not key:
        return None
    areas = _known_areas()
    if key in areas:
        return key.title()
    for name in sorted(areas.keys(), key=len, reverse=True):
        if name in key or key in name:
            return name.title()
    return None


def _area_from_text(text: str) -> str | None:
    """Try to extract a Mumbai area from the text."""
    text_lower = text.lower()
    for area in sorted(_known_areas().keys(), key=len, reverse=True):
        if area in text_lower:
            return area.title()
    return None


# ---------------------------------------------------------------------------
# Search + scrape
# ---------------------------------------------------------------------------


async def search_searxng(query: str, *, max_results: int | None = None) -> list[dict[str, Any]]:
    """Return SearXNG result items as dicts with at least ``url`` and ``title``.

    Falls back to an empty list if SearXNG is not configured or returns an error.
    """
    settings = get_settings()
    if not settings.searxng_enabled or not settings.searxng_url:
        return []

    max_results = max_results or settings.searxng_max_results
    params = {
        "q": query,
        "format": "json",
        "language": "en",
        "safesearch": "0",
    }
    url = urljoin(settings.searxng_url.rstrip("/") + "/", "search")

    async with _http_client() as client:
        try:
            response = await client.get(url, params=params)
            response.raise_for_status()
            data = response.json()
        except Exception as exc:  # pragma: no cover - network/dependency optional
            logger.warning("SearXNG search failed: %s", exc)
            return []

    results = data.get("results", []) if isinstance(data, dict) else []
    return [
        {
            "url": item.get("url"),
            "title": item.get("title", ""),
            "content": item.get("content", ""),
        }
        for item in results[:max_results]
        if item.get("url") and not _SKIP_URL_RE.search(item.get("url", ""))
    ]


async def scrape_page(url: str) -> dict[str, Any]:
    """Fetch a URL and extract readable text + metadata.

    Uses BeautifulSoup when installed; otherwise returns the page title and a
    plain-text fallback. Returns ``ok=False`` when the page cannot be fetched
    (many travel sites block bots with 403).
    """
    async with _http_client() as client:
        try:
            response = await client.get(url)
            response.raise_for_status()
        except Exception as exc:
            logger.info("Could not fetch %s (%s); will use the search snippet", url, exc)
            return {"url": url, "title": "", "text": "", "ok": False}

    html = response.text
    title_match = re.search(r"<title[^>]*>(.*?)</title>", html, re.S | re.I)
    title = title_match.group(1).strip() if title_match else ""

    try:
        from bs4 import BeautifulSoup

        soup = BeautifulSoup(html, "html.parser")
        # Remove script/style/nav/footer noise.
        for tag in soup(["script", "style", "nav", "footer", "header", "aside"]):
            tag.decompose()
        text = soup.get_text(separator="\n", strip=True)
    except Exception:  # pragma: no cover - fallback when bs4 unavailable
        # Very rough fallback: strip tags and collapse whitespace.
        text = re.sub(r"<[^>]+>", " ", html)

    # Collapse whitespace.
    text = re.sub(r"\s+", " ", text).strip()
    return {"url": url, "title": title, "text": text[:8000], "ok": True}


async def scrape_or_snippet(result: dict[str, Any]) -> dict[str, Any]:
    """Scrape a result, falling back to its SearXNG snippet when blocked.

    Many travel sites return 403 to bots; the search snippet still names real
    places, so it is a usable (if shorter) extraction source.
    """
    page = await scrape_page(result["url"])
    if page.get("ok"):
        return page

    snippet = f"{result.get('title', '')}. {result.get('content', '')}".strip()
    if len(snippet) >= 40:
        return {
            "url": result["url"],
            "title": result.get("title", ""),
            "text": snippet,
            "ok": True,
            "from_snippet": True,
        }
    return page


# ---------------------------------------------------------------------------
# Heuristic extractor (fallback)
# ---------------------------------------------------------------------------


def _normalize_tags(title: str, text: str) -> list[str]:
    """Map free text to canonical taxonomy tags (heuristic path)."""
    combined = f"{title} {text}".lower()
    tags: set[str] = set()
    for canonical, hints in _TAG_HINTS.items():
        if any(hint in combined for hint in hints):
            tags.add(canonical)
    return sorted(tags & _taxonomy_tag_names())


def _extract_candidates_from_page(
    page: dict[str, Any], default_area: str | None = None
) -> list[dict[str, Any]]:
    """Naive extractor: split page text into candidate places.

    Looks for capitalised phrases followed by location/activity words. This is
    the fallback used when the local LLM is unavailable.
    """
    text = page.get("text", "")
    if not text:
        return []

    sentences = re.split(r"[.!?]\s+", text)
    candidates: list[dict[str, Any]] = []
    seen_titles: set[str] = set()

    activity_words = [
        "visit",
        "explore",
        "walk",
        "tour",
        "spot",
        "place",
        "cafe",
        "restaurant",
        "market",
        "temple",
        "beach",
        "park",
    ]

    for sentence in sentences:
        if len(sentence) < 20 or len(sentence) > 300:
            continue
        lower = sentence.lower()
        if not any(word in lower for word in activity_words):
            continue
        # Pull out a capitalised noun phrase as the title.
        match = re.search(r"([A-Z][A-Za-z0-9\s&',-]{2,60})(?:\s+(?:in|at|near|on|from))", sentence)
        if not match:
            continue
        title = match.group(1).strip()
        if title.lower() in seen_titles or len(title) < 4:
            continue
        seen_titles.add(title.lower())
        area = _area_from_text(sentence) or _resolve_area(default_area)
        candidates.append(
            {
                "raw_title": title,
                "url": page.get("url"),
                "area": area,
                "extracted_data": {
                    "sentence": sentence.strip(),
                    "page_title": page.get("title"),
                    "tags": _normalize_tags(title, sentence),
                    "extraction_method": "heuristic",
                },
                "llm_confidence": 0.3,
            }
        )

    return candidates[:5]


# ---------------------------------------------------------------------------
# Local-LLM extractor
# ---------------------------------------------------------------------------


def _build_llm_prompt(page: dict[str, Any], area: str | None, max_candidates: int) -> str:
    text = str(page.get("text", ""))[: get_settings().discovery_page_chars]
    allowed_tags = ", ".join(sorted(_taxonomy_tag_names()))
    allowed_areas = ", ".join(sorted(_known_areas().keys()))
    return f"""Extract up to {max_candidates} real, visitable places from the page below.

Return JSON exactly in this shape:
{{
  "candidates": [
    {{
      "name": "official place name",
      "area": "one of the allowed areas, or null",
      "category": "one allowed tag",
      "tags": ["allowed tag", "allowed tag"],
      "description": "one sentence quote or summary from the page",
      "confidence": 0.0
    }}
  ]
}}

Rules:
- Only include specific venues or landmarks explicitly named in the text. Do not invent.
- NEVER return a city, suburb or neighbourhood as a place (e.g. "Bandra", "Bandra West", "Mumbai"). Return the actual venue/landmark names, such as "National Juice Center" or "Bandra Fort".
- Good "name" examples: "Bandra Fort", "Elco Pani Puri", "Mount Mary Church".
- Bad "name" examples: "Bandra", "Mumbai", "street food".
- "area" must be one of: {allowed_areas}
- "tags" and "category" must be chosen from: {allowed_tags}
- Prefer 1-3 tags per place, most specific first.
- "confidence" is 0..1 for how clearly the page presents the place as a visitable activity.
- If the page has no real places, return {{"candidates": []}}.

Requested area (context): {area or "unknown"}
Page title: {page.get('title', '')}
Page URL: {page.get('url', '')}
Page text:
\"\"\"{text}\"\"\"
"""


def _normalize_llm_candidate(
    raw: Any, page: dict[str, Any], default_area: str | None
) -> dict[str, Any] | None:
    """Validate + normalize one LLM candidate into the internal shape."""
    if not isinstance(raw, dict):
        return None
    name = str(raw.get("name") or "").strip()
    if not (3 <= len(name) <= 200):
        return None
    # Reject neighbourhood names masquerading as places ("Bandra West").
    if name.lower().strip() in set(_known_areas().keys()):
        return None

    tags = _normalize_tag_list(raw.get("tags"))
    for extra in (raw.get("category"),):
        for tag in _normalize_tag_list(extra):
            if tag not in tags:
                tags.append(tag)

    area = (
        _resolve_area(raw.get("area"))
        or _resolve_area(default_area)
        or _area_from_text(str(raw.get("description") or name))
    )

    try:
        confidence = float(raw.get("confidence", 0.5))
    except (TypeError, ValueError):
        confidence = 0.5
    confidence = max(0.0, min(1.0, confidence))

    description = str(raw.get("description") or "").strip()[:500]

    return {
        "raw_title": name,
        "url": page.get("url"),
        "area": area,
        "extracted_data": {
            "sentence": description or name,
            "page_title": page.get("title"),
            "tags": tags,
            "extraction_method": "llm",
        },
        "llm_confidence": confidence,
    }


def _llm_available() -> bool:
    """True when a local LLM is configured for extraction."""
    try:
        from app.services.llm import get_client

        return get_client().configured
    except Exception:  # pragma: no cover - defensive
        return False


async def _extract_candidates_llm(
    page: dict[str, Any], area: str | None
) -> list[dict[str, Any]] | None:
    """Extract candidates with the local LLM.

    Returns ``None`` when the model is disabled/unavailable/failed (the caller
    then uses the heuristic extractor). Returns a (possibly empty) list when the
    model responded successfully.
    """
    settings = get_settings()
    # Tests must be deterministic and offline; only real environments use the LLM.
    if settings.app_env == "test" or not settings.discovery_use_llm or not _llm_available():
        return None

    from app.services.llm import get_client

    limit = settings.discovery_max_candidates_per_page
    prompt = _build_llm_prompt(page, area, limit)

    try:
        data = await get_client().generate_json(
            prompt,
            system=_LLM_SYSTEM,
            timeout=settings.discovery_llm_timeout_seconds,
            num_predict=settings.discovery_llm_num_predict,
            # Batch extraction is latency-sensitive: one attempt, then fall back.
            attempts=1,
        )
    except Exception as exc:  # pragma: no cover - defensive
        logger.warning(
            "LLM extraction failed for %s: %s: %s",
            page.get("url"),
            type(exc).__name__,
            exc or "(no message)",
        )
        return None

    if not data or not isinstance(data.get("candidates"), list):
        return None

    normalized: list[dict[str, Any]] = []
    seen: set[str] = set()
    for raw in data["candidates"]:
        candidate = _normalize_llm_candidate(raw, page, area)
        if candidate is None:
            continue
        key = candidate["raw_title"].lower()
        if key in seen:
            continue
        seen.add(key)
        normalized.append(candidate)
        if len(normalized) >= limit:
            break

    logger.info(
        "LLM extracted %d candidates from %s", len(normalized), page.get("url")
    )
    return normalized


async def extract_candidates(
    page: dict[str, Any], area: str | None = None
) -> list[dict[str, Any]]:
    """Extract candidates from one page: LLM first, heuristic fallback."""
    if page.get("ok"):
        llm_candidates = await _extract_candidates_llm(page, area)
        if llm_candidates is not None:
            return llm_candidates
    return _extract_candidates_from_page(page, area)


# ---------------------------------------------------------------------------
# Storage
# ---------------------------------------------------------------------------


def _get_or_create_source(session: Session, page: dict[str, Any]) -> DiscoverySource:
    """Return an existing source by URL or create a new one."""
    url = page.get("url", "")
    parsed = urlparse(url)
    base = f"{parsed.scheme}://{parsed.netloc}" if parsed.netloc else url
    source = session.exec(select(DiscoverySource).where(DiscoverySource.base_url == base)).first()
    if source is None:
        source = DiscoverySource(
            name=page.get("title", parsed.netloc or "unknown"),
            base_url=base,
            source_type="blog",
            trust_score=0.5,
            last_scraped=datetime.now(timezone.utc),
        )
        session.add(source)
        session.commit()
        session.refresh(source)
    else:
        source.last_scraped = datetime.now(timezone.utc)
        session.add(source)
        session.commit()
    return source


def _store_candidate(
    session: Session,
    candidate: dict[str, Any],
    source: DiscoverySource | None,
) -> ScrapedCandidate:
    """Store a candidate and its mention, avoiding duplicate titles."""
    existing = session.exec(
        select(ScrapedCandidate).where(ScrapedCandidate.raw_title == candidate["raw_title"])
    ).first()
    if existing is not None:
        existing.mention_count = (existing.mention_count or 0) + 1
        session.add(existing)
        session.commit()
        return existing

    data = candidate.get("extracted_data", {}) or {}
    # Prefer tags the extractor already validated; fall back to heuristics.
    tags = data.get("tags") or _normalize_tags(candidate["raw_title"], data.get("sentence", ""))
    method = data.get("extraction_method", "heuristic")

    db_candidate = ScrapedCandidate(
        raw_title=candidate["raw_title"],
        url=candidate.get("url"),
        area=candidate.get("area"),
        extracted_data={**data, "tags": tags},
        llm_confidence=candidate.get("llm_confidence", 0.0),
        mention_count=1,
        authenticity_signals={
            "source_domain": source.base_url if source else None,
            "extraction_method": method,
        },
        status="pending",
    )
    session.add(db_candidate)
    session.commit()
    session.refresh(db_candidate)

    if source is not None:
        mention = CandidateCitation(
            candidate_id=db_candidate.id,
            source_id=source.id,
            url=candidate.get("url"),
            quote=data.get("sentence"),
            sentiment="positive",
            mention_date=datetime.now(timezone.utc),
        )
        session.add(mention)
        session.commit()

    return db_candidate


# ---------------------------------------------------------------------------
# Pipeline
# ---------------------------------------------------------------------------


async def discover_activities(
    query: str,
    *,
    area: str | None = None,
    max_results: int | None = None,
    store: bool = True,
) -> list[dict[str, Any]]:
    """Run the discovery pipeline for a free-text query.

    Extraction uses the local LLM when available and the heuristic extractor
    otherwise. Returns a list of candidates (stored when ``store=True``). Safe
    to call when SearXNG is offline: returns an empty list.
    """
    settings = get_settings()
    full_query = f"{area} {query}".strip() if area else query
    limit = max_results or settings.discovery_max_results
    results = await search_searxng(full_query, max_results=limit)
    if not results:
        return []

    pages = await asyncio.gather(*[scrape_or_snippet(r) for r in results])

    # Bound concurrency so a laptop-hosted Ollama isn't saturated.
    semaphore = asyncio.Semaphore(max(1, settings.discovery_llm_concurrency))

    async def _extract_one(page: dict[str, Any]) -> tuple[dict[str, Any], list[dict[str, Any]]]:
        if not page.get("ok"):
            return page, []
        if settings.discovery_use_llm and _llm_available():
            async with semaphore:
                llm_candidates = await _extract_candidates_llm(page, area)
            if llm_candidates is not None:
                return page, llm_candidates
        return page, _extract_candidates_from_page(page, area)

    extracted = await asyncio.gather(*[_extract_one(p) for p in pages])

    if not store:
        return [c for _, candidates in extracted for c in candidates]

    stored: list[dict[str, Any]] = []
    with Session(engine) as session:
        for page, candidates in extracted:
            source = _get_or_create_source(session, page)
            for candidate in candidates:
                db_candidate = _store_candidate(session, candidate, source)
                stored.append(
                    {
                        "id": db_candidate.id,
                        "raw_title": db_candidate.raw_title,
                        "area": db_candidate.area,
                        "url": db_candidate.url,
                        "tags": db_candidate.extracted_data.get("tags", []),
                        "method": db_candidate.authenticity_signals.get("extraction_method"),
                        "confidence": db_candidate.llm_confidence,
                        "status": db_candidate.status,
                    }
                )
    return stored
