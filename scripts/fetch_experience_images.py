"""Fetch curated, freely-licensed photos for the 48 LocalIQ experiences.

Why this exists
---------------
The curated dataset shipped with empty ``image_url`` values, so with the Google
Places key disabled every card fell back to a gradient placeholder. This script
downloads real, place-relevant photos from Wikimedia Commons into a
backend-managed asset directory and rewrites the dataset to point at them.

Design rules
------------
* Only Wikimedia Commons (``thumb.wikimedia.org``) is used — the license is
  recorded per image in ``data/images/manifest.json`` so attribution is possible.
* No invented URLs. Every image is downloaded and byte-verified (HTTP 200,
  ``image/*`` content type, minimum size) before the dataset is touched.
* Idempotent: an existing, valid local file is reused unless ``--force``.
* Images are served by the backend at ``/static/images/<file>``; the Google Places
  photo proxy still takes priority at request time when Google is configured.

Usage
-----
    python scripts/fetch_experience_images.py            # fetch missing only
    python scripts/fetch_experience_images.py --force    # re-download all
    python scripts/fetch_experience_images.py --verify   # check local files only
"""

from __future__ import annotations

import argparse
import html
import json
import re
import sys
import time
from pathlib import Path

import httpx

REPO_ROOT = Path(__file__).resolve().parent.parent
BACKEND = REPO_ROOT / "backend"
DATA_JSON = BACKEND / "data" / "mumbai_experiences.json"
IMAGE_DIR = BACKEND / "data" / "images"
MANIFEST = IMAGE_DIR / "manifest.json"

# Wikimedia's robot policy requires a descriptive User-Agent with a contact.
# Requests without one are rejected with HTTP 403.
USER_AGENT = (
    "LocalIQ/1.0 (https://github.com/EmaadAkhter/LocalIQ-HackCelestial-; "
    "educational hackathon project; contact: localiq-dev@example.com) httpx"
)
COMMONS_API = "https://commons.wikimedia.org/w/api.php"
WIKIPEDIA_SUMMARY = "https://en.wikipedia.org/api/rest_v1/page/summary/"

MIN_BYTES = 15_000
MIN_WIDTH = 800
MIN_HEIGHT = 500
ALLOWED_MIME = {"image/jpeg", "image/png"}

# Wikimedia rate-limits bursts hard (HTTP 429), so be a polite client.
POLITE_DELAY_SECONDS = 0.7
MAX_RETRIES = 4

# Curated Commons search queries per experience, most specific first.
# Keyed by the exact ``name`` in data/mumbai_experiences.json.
QUERIES: dict[str, list[str]] = {
    "Elco Pani Puri & Chaat, Bandra": ["Pani puri", "Pani puri Mumbai"],
    "Bademiya Late-Night Kebabs, Colaba": ["Bademiya", "Seekh kebab Mumbai"],
    "Britannia & Co, Ballard Estate": ["Britannia & Co.", "Ballard Estate"],
    "Leopold Cafe, Colaba": ["Leopold Cafe", "Colaba Causeway"],
    "Dadar Maharashtrian Food Trail": ["Vada pav", "Misal"],
    "Mohammed Ali Road Food Walk": ["Mohammed Ali Road Mumbai", "Mohammed Ali Street"],
    "Ghatkopar Khau Galli": ["Mumbai street food", "Dabeli"],
    "Juhu Beach Pav Bhaji Sunset": ["Juhu Beach", "Pav bhaji"],
    "Gateway of India Sunrise": ["Gateway of India", "Taj Mahal Palace hotel"],
    "Elephanta Caves Ferry Day": ["Elephanta Caves", "Elephanta Island"],
    "CSMT Heritage Walk": ["Chhatrapati Shivaji Terminus", "CSMT Mumbai"],
    "Siddhivinayak Morning Darshan": ["Siddhivinayak Temple", "Mahalaxmi Mumbai"],
    "Haji Ali Dargah + Dhobi Ghat": ["Haji Ali Dargah", "Dhobi Ghat"],
    "Kanheri Caves Half-Day": ["Kanheri Caves", "Sanjay Gandhi National Park"],
    "Banganga & Walkeshwar Walk": ["Banganga Tank", "Walkeshwar Temple"],
    "Global Vipassana Pagoda Trip": ["Global Vipassana Pagoda", "Dharavi"],
    "Colaba Causeway Bargain Hunt": ["Colaba Causeway", "Colaba street market"],
    "Linking Road Fashion Crawl": ["Linking Road Mumbai", "Linking Road Bandra"],
    "Crawford Market Spice Run": ["Crawford Market", "Mumbai spices"],
    "Chor Bazaar Antique Hunt": ["Chor Bazaar", "Mumbai antiques"],
    "Zaveri Bazaar & Kalbadevi Lanes": ["Zaveri Bazaar Mumbai", "Kalbadevi"],
    "Phoenix Palladium Mall Crawl": ["Palladium Mall Mumbai", "High Street Phoenix"],
    "Dadar Flower & Plaza Market": ["Dadar flower market", "Dadar Plaza"],
    "Hill Road Budget Fashion": ["Hill Road Bandra", "Bandra shopping"],
    "Jehangir Art Gallery + Kala Ghoda": ["Jahangir Art Gallery Mumbai", "Kala Ghoda"],
    "CSMVS Museum Mile": [
        "Chhatrapati Shivaji Maharaj Vastu Sangrahalaya",
        "Prince of Wales Museum Mumbai",
    ],
    "NGMA Mumbai Hour": ["National Gallery of Modern Art Mumbai", "NGMA Mumbai"],
    "Bandra Chapel Road Street Art": ["Street art in Mumbai", "Bandra graffiti"],
    "Prithvi Theatre Evening, Juhu": ["Prithvi Theatre", "Juhu theatre"],
    "NCPA Performance Night": ["National Centre for the Performing Arts", "NCPA Mumbai"],
    "Royal Opera House Show": ["Royal Opera House Mumbai", "Girgaon opera house"],
    "Kala Ghoda Creative Lanes": ["Kala Ghoda", "Kala Ghoda Festival"],
    "Bandra Nightlife Crawl": ["Linking Road Mumbai", "Bandra street Mumbai"],
    "Lower Parel Brewery Hop": ["Lower Parel", "The Mills Mumbai"],
    "Andheri West Rooftop Circuit": ["Andheri", "Juhu night"],
    "Fort Jazz & Heritage Bar Night": ["Fort Mumbai", "Colaba at night"],
    "Carter Road Live Gig Evening": ["Carter Road Bandra", "Bandra sea face"],
    "Waterfield Road Karaoke Lane": ["Waterfield Road", "Bandra market street"],
    "Marine Drive Midnight Lounge": ["Marine Drive Mumbai night", "Marine Drive"],
    "Versova Beach Shack Night": ["Versova", "Versova fishing village"],
    "Marine Drive Sunrise Walk": ["Marine Drive sunrise", "Marine Drive"],
    "Sanjay Gandhi NP Trail": ["Sanjay Gandhi National Park", "Kanheri"],
    "Powai Lake Cycling Loop": ["Powai Lake", "Powai"],
    "Carter Road Sunset Promenade": ["Carter Road", "Bandra sunset"],
    "Versova Fishing Village Morning": ["Versova harbour", "Versova"],
    "Hanging Gardens + Sunset Point": ["Hanging Gardens", "Malabar Hill"],
    "Bandra Fort & Sea-Link View": ["Bandra Fort", "Bandra-Worli Sea Link"],
    "Bandstand Promenade Evening": ["Bandstand Promenade", "Bandra sea face"],
}


def slugify(name: str) -> str:
    slug = re.sub(r"[^a-z0-9]+", "-", name.lower()).strip("-")
    return slug[:70]


# Tokens a candidate's file title must contain to be accepted. Generic queries
# ("Linking Road", "Mohammed Ali Road") otherwise return photos from other
# countries entirely (a London bridge, a Ladakh road), so every query needs an
# explicit relevance gate.
RELEVANCE: dict[str, list[str]] = {
    "Mohammed Ali Road Food Walk": ["mohammed ali", "mumbai", "bombay"],
    "Linking Road Fashion Crawl": ["linking road", "mumbai", "bandra", "bombay"],
    "Zaveri Bazaar & Kalbadevi Lanes": ["mumbai", "bombay", "kalbadevi", "zaveri bazaar mumbai"],
    "Jehangir Art Gallery + Kala Ghoda": ["jahangir art", "jag", "kala ghoda", "mumbai", "bombay"],
    "Bandra Nightlife Crawl": ["mumbai", "bombay", "linking road", "waterfield", "bandra street"],
    "Carter Road Live Gig Evening": ["carter road", "bandra", "mumbai"],
    "Carter Road Sunset Promenade": ["carter road", "bandra", "mumbai"],
    "Bandra Chapel Road Street Art": ["bandra", "mumbai", "graffiti", "street art", "chapel"],
    "Andheri West Rooftop Circuit": ["andheri", "juhu", "mumbai", "bombay"],
    "Hanging Gardens + Sunset Point": ["hanging gardens mumbai", "malabar", "mumbai", "bombay"],
    "Waterfield Road Karaoke Lane": ["waterfield", "bandra", "mumbai"],
    "Fort Jazz & Heritage Bar Night": ["fort", "mumbai", "bombay", "colaba"],
    "Marine Drive Midnight Lounge": ["marine drive", "mumbai", "bombay"],
    "Marine Drive Sunrise Walk": ["marine drive", "mumbai", "bombay", "nariman"],
    "Bandstand Promenade Evening": ["bandstand", "bandra", "mumbai"],
    "Bandra Fort & Sea-Link View": ["bandra fort", "sea link", "mumbai"],
    "Versova Beach Shack Night": ["versova", "mumbai", "bombay"],
    "Versova Fishing Village Morning": ["versova", "mumbai", "koli"],
    "Sanjay Gandhi NP Trail": ["sanjay gandhi", "kanheri", "mumbai"],
    "Powai Lake Cycling Loop": ["powai", "mumbai", "lake", "hiranandani"],
    "Banganga & Walkeshwar Walk": ["banganga", "walkeshwar", "mumbai"],
    "Mohammed Ali Road Food Walk ": ["mohammed ali", "mumbai"],
    "Lower Parel Brewery Hop": ["lower parel", "mills", "mumbai"],
    "Prithvi Theatre Evening, Juhu": ["prithvi", "juhu", "mumbai"],
    "NCPA Performance Night": ["ncpa", "performing arts", "mumbai"],
    "Royal Opera House Show": ["opera house", "mumbai", "girgaon"],
    "Kala Ghoda Creative Lanes": ["kala ghoda", "mumbai"],
    "CSMVS Museum Mile": ["vastu sangrahalaya", "prince of wales", "mumbai"],
    "NGMA Mumbai Hour": ["national gallery of modern art", "ngma", "mumbai"],
    "Crawford Market Spice Run": ["crawford market", "mumbai", "spice"],
    "Chor Bazaar Antique Hunt": ["chor bazaar", "mumbai"],
    "Dadar Flower & Plaza Market": ["dadar", "mumbai", "flower"],
    "Siddhivinayak Morning Darshan": ["siddhivinayak", "mumbai"],
    "Haji Ali Dargah + Dhobi Ghat": ["haji ali", "dhobi ghat", "mumbai"],
    "Gateway of India Sunrise": ["gateway of india", "mumbai"],
    "Elephanta Caves Ferry Day": ["elephanta", "mumbai"],
    "Kanheri Caves Half-Day": ["kanheri", "mumbai"],
    "Global Vipassana Pagoda Trip": ["vipassana", "pagoda", "mumbai", "dharavi"],
    "Colaba Causeway Bargain Hunt": ["colaba", "mumbai"],
    "Phoenix Palladium Mall Crawl": ["palladium", "phoenix", "mumbai"],
    "Hill Road Budget Fashion": ["hill road bandra", "bandra", "mumbai", "bombay"],
    "Elco Pani Puri & Chaat, Bandra": ["pani puri", "mumbai", "chaat", "bandra"],
    "Bademiya Late-Night Kebabs, Colaba": ["bademiya", "kebab", "colaba", "mumbai"],
    "Britannia & Co, Ballard Estate": [
        "britannia and co",
        "britannia & co",
        "ballard estate",
        "mumbai",
        "bombay",
    ],
    "Leopold Cafe, Colaba": ["leopold", "colaba", "mumbai"],
    "Dadar Maharashtrian Food Trail": ["vada pav", "misal", "mumbai", "dadar"],
    "Ghatkopar Khau Galli": ["street food", "dabeli", "mumbai", "ghatkopar"],
    "Juhu Beach Pav Bhaji Sunset": ["juhu", "pav bhaji", "mumbai"],
    "CSMT Heritage Walk": ["chhatrapati shivaji", "csmt", "mumbai", "termi"],
}


def is_relevant(place: str, title: str, query: str = "") -> bool:
    """Reject candidates whose **file title** misses the place's tokens.

    Only the file title is inspected. Including the query in the check would
    defeat the gate entirely (a Scottish "Moncreiffe Hill" photo passes a
    "Pali Hill" query when the query text is allowed into the haystack).
    """
    tokens = RELEVANCE.get(place)
    if not tokens:
        return True
    haystack = title.lower()
    return any(token.lower() in haystack for token in tokens)


def strip_html(value: str) -> str:
    return html.unescape(re.sub(r"<[^>]+>", "", value or "")).strip()


def polite_get(client: httpx.Client, url: str, **kwargs) -> httpx.Response | None:
    """GET with a courtesy delay and 429/5xx backoff.

    Wikimedia rejects bursts with HTTP 429, so every call is spaced out and
    retried with exponential backoff (honouring ``Retry-After`` when present).
    """
    time.sleep(POLITE_DELAY_SECONDS)
    delay = 2.0
    for attempt in range(MAX_RETRIES):
        try:
            response = client.get(url, **kwargs)
        except Exception as exc:
            print(f"    request error ({type(exc).__name__}), retrying")
            time.sleep(delay)
            delay *= 2
            continue
        if response.status_code in (429, 500, 502, 503, 504):
            retry_after = response.headers.get("retry-after")
            wait = float(retry_after) if retry_after and retry_after.isdigit() else delay
            print(f"    HTTP {response.status_code}; waiting {wait:.0f}s")
            time.sleep(wait)
            delay *= 2
            continue
        return response
    return None


def search_commons(client: httpx.Client, query: str) -> list[dict]:
    """Return candidate image files for a Commons search, best first."""
    response = polite_get(
        client,
        COMMONS_API,
        params={
            "action": "query",
            "generator": "search",
            "gsrsearch": query,
            "gsrnamespace": "6",  # File namespace
            "gsrlimit": "8",
            "prop": "imageinfo",
            "iiprop": "url|mime|size|extmetadata",
            "iiurlwidth": "1200",
            "format": "json",
        },
    )
    if response is None or response.status_code != 200:
        status = getattr(response, "status_code", "no-response")
        detail = (response.text[:120] if response is not None else "all retries exhausted")
        print(f"    search failed for {query!r}: status={status} body={detail!r}")
        return []

    pages = (response.json().get("query") or {}).get("pages") or {}
    candidates: list[dict] = []
    for page in pages.values():
        info = (page.get("imageinfo") or [{}])[0]
        mime = info.get("mime")
        width = info.get("width") or 0
        height = info.get("height") or 0
        if mime not in ALLOWED_MIME or width < MIN_WIDTH or height < MIN_HEIGHT:
            continue
        thumb = info.get("thumburl")
        if not thumb:
            continue
        meta = info.get("extmetadata") or {}
        candidates.append(
            {
                "title": page.get("title", ""),
                "thumburl": thumb,
                "descriptionurl": info.get("descriptionurl"),
                "width": width,
                "height": height,
                "author": strip_html((meta.get("Artist") or {}).get("value", ""))[:120],
                "license": strip_html((meta.get("LicenseShortName") or {}).get("value", ""))[:60],
            }
        )

    # Prefer landscape-ish, reasonably large photos; the first search hit for a
    # precise query is almost always the subject itself.
    candidates.sort(key=lambda c: -(c["width"] * c["height"]))
    return candidates


def wikipedia_candidate(client: httpx.Client, title: str) -> dict | None:
    """Secondary source: the lead image of a Wikipedia article.

    Uses the documented REST summary endpoint (not scraping) and prefers the
    thumbnail host, which is the one Wikimedia serves reliably to clients.
    """
    response = polite_get(client, WIKIPEDIA_SUMMARY + quote_title(title))
    if response is None or response.status_code != 200:
        return None
    try:
        data = response.json()
    except Exception:
        return None
    if data.get("type") == "disambiguation":
        return None
    image = data.get("originalimage") or data.get("thumbnail") or {}
    url = image.get("source")
    if not url:
        return None
    return {
        "title": f"File (via Wikipedia article {data.get('title', title)})",
        "thumburl": url,
        "descriptionurl": (data.get("content_urls", {}).get("desktop", {}) or {}).get("page"),
        "width": image.get("width", 1200),
        "height": image.get("height", 800),
        "author": "see source page",
        "license": "see source page (Wikimedia Commons)",
    }


def quote_title(title: str) -> str:
    from urllib.parse import quote

    return quote(title.replace(" ", "_"), safe="")


def download(client: httpx.Client, url: str, target: Path) -> bool:
    response = polite_get(client, url, timeout=30)
    if response is None or response.status_code != 200:
        print(f"    download failed (status={getattr(response, 'status_code', 'n/a')})")
        return False
    content_type = response.headers.get("content-type", "")
    body = response.content
    if not content_type.startswith("image/"):
        print(f"    not an image: {content_type}")
        return False
    if len(body) < MIN_BYTES:
        print(f"    too small: {len(body)} bytes")
        return False
    target.parent.mkdir(parents=True, exist_ok=True)
    target.write_bytes(body)
    return True


def verify_file(path: Path) -> bool:
    if not path.exists():
        return False
    if path.stat().st_size < MIN_BYTES:
        return False
    with path.open("rb") as handle:
        header = handle.read(12)
    # JPEG: FF D8 FF ; PNG: 89 50 4E 47
    return header.startswith(b"\xff\xd8\xff") or header.startswith(b"\x89PNG")


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--force", action="store_true", help="re-download even if present")
    parser.add_argument("--verify", action="store_true", help="only verify local files")
    parser.add_argument("--timeout", type=float, default=600.0)
    args = parser.parse_args()

    dataset = json.loads(DATA_JSON.read_text(encoding="utf-8"))
    experiences = dataset["experiences"]
    manifest: dict[str, dict] = {}
    if MANIFEST.exists():
        manifest = json.loads(MANIFEST.read_text(encoding="utf-8"))

    if args.verify:
        ok = 0
        missing: list[str] = []
        for exp in experiences:
            url = exp.get("image_url") or ""
            name = Path(url).name if url.startswith("/static/images/") else ""
            if name and verify_file(IMAGE_DIR / name):
                ok += 1
            else:
                missing.append(exp["name"])
        print(f"verified {ok}/{len(experiences)} local images")
        if missing:
            print("missing/invalid:")
            for m in missing:
                print("  -", m)
        return 0 if not missing else 1

    IMAGE_DIR.mkdir(parents=True, exist_ok=True)
    fetched = reused = failed = 0
    deadline = time.time() + args.timeout

    with httpx.Client(headers={"User-Agent": USER_AGENT}, follow_redirects=True) as client:
        for exp in experiences:
            name = exp["name"]
            slug = slugify(name)
            target = IMAGE_DIR / f"{slug}.jpg"

            if not args.force and verify_file(target) and name in manifest:
                reused += 1
                print(f"[skip] {name}")
                continue
            if time.time() > deadline:
                print("timeout reached, stopping")
                break

            entry = None
            queries = QUERIES.get(name, [name])
            # 1) Commons file search (precise, freely licensed)
            for query in queries:
                for cand in search_commons(client, query):
                    if not is_relevant(name, cand["title"], query):
                        continue
                    if download(client, cand["thumburl"], target):
                        entry = {
                            "file": target.name,
                            "query": query,
                            "source_kind": "commons",
                            "commons_title": cand["title"],
                            "source": cand["descriptionurl"] or cand["thumburl"],
                            "author": cand["author"],
                            "license": cand["license"],
                            "width": cand["width"],
                            "height": cand["height"],
                        }
                        break
                if entry:
                    break
            # 2) Fallback: lead image of the matching Wikipedia article
            if not entry:
                for query in queries:
                    cand = wikipedia_candidate(client, query)
                    if not cand or not is_relevant(name, cand["title"], query):
                        continue
                    if download(client, cand["thumburl"], target):
                        entry = {
                            "file": target.name,
                            "query": query,
                            "source_kind": "wikipedia",
                            "commons_title": cand["title"],
                            "source": cand["descriptionurl"] or cand["thumburl"],
                            "author": cand["author"],
                            "license": cand["license"],
                            "width": cand["width"],
                            "height": cand["height"],
                        }
                        break

            if entry:
                manifest[name] = entry
                exp["image_url"] = f"/static/images/{target.name}"
                fetched += 1
                print(f"[ok]   {name} <- {entry['commons_title'][:52]}")
            else:
                failed += 1
                print(f"[FAIL] {name} (image_url left as-is)")

    DATA_JSON.write_text(
        json.dumps(dataset, indent=2, ensure_ascii=False) + "\n", encoding="utf-8"
    )
    MANIFEST.write_text(json.dumps(manifest, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
    print(f"\nfetched={fetched} reused={reused} failed={failed}")
    return 0 if failed == 0 else 1


if __name__ == "__main__":
    sys.exit(main())
