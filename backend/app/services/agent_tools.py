"""Tool registry for the Travel Buddy agent.

Each tool is a plain function that receives a Session and keyword arguments and
returns a JSON-serializable result. The agent layer converts these into OpenAI
function-call schemas for the LLM.
"""

from __future__ import annotations

from typing import Any

from sqlmodel import Session, select

from app.models import Experience, Guide
from app.services import places


def _experience_to_dict(e: Experience) -> dict[str, Any]:
    return {
        "id": e.id,
        "name": e.name,
        "category": e.category,
        "lat": e.lat,
        "lng": e.lng,
        "avg_cost": e.avg_cost,
        "rating": e.rating,
        "duration_min": e.duration_min,
        "open_time": e.open_time,
        "close_time": e.close_time,
        "description": e.description,
        "image_url": e.image_url,
        "tags": e.tags,
    }


def _guide_to_dict(g: Guide) -> dict[str, Any]:
    return {
        "id": g.id,
        "name": g.name,
        "specialty": g.specialty,
        "languages": g.languages,
        "rate_per_hour": g.rate_per_hour,
        "rating": g.rating,
        "areas_covered": g.areas_covered,
        "bio": g.bio,
    }


def search_places(session: Session, *, query: str = "", category: str = "", limit: int = 5) -> list[dict[str, Any]]:
    """Search places/experiences by text and optional category."""
    categories = [category] if category else None
    rows = places.search(session, text=query, categories=categories, limit=limit)
    return [_experience_to_dict(e) for e in rows]


def get_place(session: Session, *, place_id: int) -> dict[str, Any] | None:
    """Fetch a single place by id."""
    e = session.get(Experience, place_id)
    return _experience_to_dict(e) if e else None


def search_guides(session: Session, *, area: str = "", language: str = "", limit: int = 5) -> list[dict[str, Any]]:
    """Search verified local guides by area and language."""
    stmt = select(Guide)
    if area:
        stmt = stmt.where(Guide.areas_covered.contains([area]))
    if language:
        stmt = stmt.where(Guide.languages.contains([language]))
    rows = list(session.exec(stmt.limit(limit)).all())
    return [_guide_to_dict(g) for g in rows]


def list_meetups(session: Session, *, area: str = "", limit: int = 5) -> list[dict[str, Any]]:
    """List upcoming meetups in an area.

    ponytail: meetups are not modelled yet; return an empty list and a hint so
    the agent can tell the user honestly instead of hallucinating.
    """
    return []


# Registry exposed to the agent. The schema is a subset of OpenAI's tool format.
#: Tools that spend money or change state. Everything else is read-only and
#: runs without asking. Keep this list short and explicit.
MUTATING_TOOLS: frozenset[str] = frozenset()


REGISTRY: dict[str, dict[str, Any]] = {
    "search_places": {
        "function": search_places,
        "schema": {
            "type": "function",
            "function": {
                "name": "search_places",
                "description": "Search places and experiences in Mumbai by text and category.",
                "parameters": {
                    "type": "object",
                    "properties": {
                        "query": {"type": "string", "description": "Free-text search term."},
                        "category": {
                            "type": "string",
                            "description": "Optional category such as food, culture, nature, nightlife.",
                        },
                        "limit": {"type": "integer", "default": 5, "description": "Max results."},
                    },
                },
            },
        },
    },
    "get_place": {
        "function": get_place,
        "schema": {
            "type": "function",
            "function": {
                "name": "get_place",
                "description": "Fetch details for a specific place by its id.",
                "parameters": {
                    "type": "object",
                    "properties": {
                        "place_id": {"type": "integer", "description": "The place id."},
                    },
                    "required": ["place_id"],
                },
            },
        },
    },
    "search_guides": {
        "function": search_guides,
        "schema": {
            "type": "function",
            "function": {
                "name": "search_guides",
                "description": "Search local guides by area and language.",
                "parameters": {
                    "type": "object",
                    "properties": {
                        "area": {"type": "string", "description": "Mumbai area such as Bandra or Colaba."},
                        "language": {"type": "string", "description": "Preferred guide language."},
                        "limit": {"type": "integer", "default": 5, "description": "Max results."},
                    },
                },
            },
        },
    },
    "list_meetups": {
        "function": list_meetups,
        "schema": {
            "type": "function",
            "function": {
                "name": "list_meetups",
                "description": "List upcoming public meetups in an area.",
                "parameters": {
                    "type": "object",
                    "properties": {
                        "area": {"type": "string", "description": "Mumbai area."},
                        "limit": {"type": "integer", "default": 5, "description": "Max results."},
                    },
                },
            },
        },
    },
}


def execute(name: str, session: Session, arguments: dict[str, Any]) -> Any:
    """Run a tool by name with JSON arguments."""
    entry = REGISTRY.get(name)
    if not entry:
        raise ValueError(f"Unknown tool: {name}")
    return entry["function"](session, **arguments)


def schemas() -> list[dict[str, Any]]:
    """Return the LLM-ready tool schema list."""
    return [entry["schema"] for entry in REGISTRY.values()]
