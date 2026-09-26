"""Server-side Google integration for LocalIQ.

Split by responsibility:

* :mod:`app.services.google_places` — Places API (New) for place discovery and
  search, plus a photo proxy so the server key never reaches a client.
* :mod:`app.services.google_routes` — Routes API for travel time, distance and
  route geometry.

Both modules are strictly optional. Every call is failure-safe and falls back
to the local SQLite dataset / Haversine heuristic, so the product works on a
laptop with no Google keys at all.

Key handling
------------
Only *server-restricted* keys are read from the backend environment
(``GOOGLE_PLACES_API_KEY`` / ``GOOGLE_ROUTES_API_KEY``). Client-facing map keys
(``GOOGLE_MAPS_API_KEY_WEB/ANDROID/IOS``) are never used for server calls and are
never sent to clients by this package.
"""

from .google_places import (
    PHOTO_MEDIA_PATH,
    PlacesResult,
    normalize_place,
    photo_proxy_url,
    search_places,
)
from .google_routes import RouteResult, compute_route, route_between_many

__all__ = [
    "PHOTO_MEDIA_PATH",
    "PlacesResult",
    "RouteResult",
    "compute_route",
    "normalize_place",
    "photo_proxy_url",
    "route_between_many",
    "search_places",
]
