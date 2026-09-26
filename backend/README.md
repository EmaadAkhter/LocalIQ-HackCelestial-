# LocalIQ Backend

Local-first Mumbai experience recommender. FastAPI + SQLModel + SQLite. Works fully offline; Ollama (local LLM) and Open-Meteo weather are optional enhancements with graceful fallbacks.

Everything lives in the local SQLite file: curated experiences, guides, users, sessions and guide requests.

## Setup

```bash
cd backend
python -m venv .venv
# Windows:
.venv\Scripts\activate
# macOS/Linux:
# source .venv/bin/activate

pip install -r requirements.txt
cp .env.example .env   # then edit if needed
```

## Environment

| Var | Default | Purpose |
|---|---|---|
| `DATABASE_URL` | `sqlite:///./data/localiq.db` | SQLite file (all local data) |
| `AUTH_SECRET_KEY` | `localiq-dev-secret-change-me` | Signs session tokens — change before sharing |
| `AUTH_TOKEN_TTL_MINUTES` | `10080` | Session lifetime (7 days) |
| `OLLAMA_URL` | `http://localhost:11434` | Local Ollama server |
| `OLLAMA_MODEL` | _(empty)_ | e.g. `llama3.2:3b`. Empty = heuristic/fallback mode |
| `OPEN_METEO_URL` | `https://api.open-meteo.com/v1/forecast` | Weather |
| `CORS_ORIGINS` | `http://localhost:3000` | Comma-separated frontend origins |
| `GOOGLE_MAPS_API_KEY_WEB` | _(empty)_ | Maps JavaScript key, served to browsers by `GET /api/v1/config` |
| `GOOGLE_MAPS_API_KEY_ANDROID` | _(empty)_ | Android key, injected into the manifest by the release script |
| `GOOGLE_MAPS_API_KEY_IOS` | _(empty)_ | iOS key, injected into `Info.plist` by the release script |
| `GOOGLE_PLACES_API_KEY` | _(empty)_ | Server-side Places API (search/nearby/photo proxy). Never sent to clients |
| `GOOGLE_ROUTES_API_KEY` | _(empty)_ | Server-side Routes API (travel time/distance/polyline). Never sent to clients |

One key per platform: Google restricts keys per application (HTTP referrer for
web, package + SHA-1 for Android, bundle id for iOS). The backend is the single
source of truth — the Flutter app holds no key and fetches the web one from
`GET /api/v1/config` at startup, falling back to the offline map canvas when the
backend is unreachable. `scripts/set-maps-keys.sh` (or `.ps1`) copies the native
keys from `backend/.env` into the Android/iOS projects.

> **Security note:** the browser key is public by definition, so do **not** reuse
> it as `GOOGLE_PLACES_API_KEY` / `GOOGLE_ROUTES_API_KEY` in production — a
> referrer restriction is the only thing shielding it. Create one extra key
> restricted by IP with just the Places/Routes APIs enabled. The local dev env
> reuses the web key because it is the only credential available, and
> `tests/smoke_live.py` prints a warning when it detects that.

Never commit `.env`.

## Database + Seed

```bash
cd backend
python -m app.seed
```

Repeatable: clears `experiences`/`guides` and re-inserts from `data/mumbai_experiences.json` (48 experiences, 12 guides). No duplicates. Tables `users`, `user_sessions` and `guide_requests` are created on startup and are never wiped by seeding.

Inspect the local DB any time:

```bash
sqlite3 data/localiq.db ".tables"
sqlite3 data/localiq.db "select id,name,email from users;"
```

## Authentication

Local, self-hosted, no external IdP and no new dependency:

- Passwords stored as `pbkdf2_sha256$iterations$salt$hash` (per-user random salt, constant-time compare).
- Sessions are opaque random tokens; only `HMAC-SHA256(secret, token)` is stored, so a leaked DB cannot be replayed.
- Expiry enforced on every request; expired rows are deleted on use.
- `GET /api/v1/auth/status` reports auth + Ollama state for the frontend.

```bash
# Register (returns a token immediately)
curl -X POST http://localhost:8000/api/v1/auth/register -H "Content-Type: application/json" \
  -d '{"name":"Aarav Sharma","email":"aarav@example.com","password":"secret123"}'

# Login
curl -X POST http://localhost:8000/api/v1/auth/login -H "Content-Type: application/json" \
  -d '{"email":"aarav@example.com","password":"secret123"}'

# Authenticated call
curl http://localhost:8000/api/v1/auth/me -H "Authorization: Bearer <token>"
```

| Method | Path | Auth | Description |
|---|---|---|---|
| POST | `/api/v1/auth/register` | – | Create account, returns token (201) |
| POST | `/api/v1/auth/login` | – | Returns token |
| POST | `/api/v1/auth/logout` | required | Revoke the current token |
| GET | `/api/v1/auth/me` | required | Current user |
| GET | `/api/v1/auth/status` | – | Auth + Ollama status |

Errors: `409` email already registered, `401` bad credentials, `422` validation, `400` malformed email.

Guide requests accept a token (linked to the user, listed in `GET /api/v1/guides/me/requests`) and also work anonymously so the demo flow never breaks.

## Ollama (optional)

```bash
ollama serve
ollama pull llama3.2:3b
# set OLLAMA_MODEL=llama3.2:3b in .env
```

Without Ollama the backend still works: `/parse` uses a deterministic heuristic, `/chat` returns data-grounded replies, `/recommend` uses template `why_this_fits`. Startup warm-up failure is logged and ignored.

## Run

```bash
cd backend
uvicorn main:app --reload --port 8000
```

- Health: `GET http://localhost:8000/health`
- Swagger: `http://localhost:8000/docs`
- ReDoc: `http://localhost:8000/redoc`
- OpenAPI: `http://localhost:8000/openapi.json`

## API Endpoints

| Method | Path | Description |
|---|---|---|
| GET | `/health` | Health check |
| POST | `/api/v1/auth/register` · `/login` · `/logout` | Local auth (see above) |
| GET | `/api/v1/auth/me` · `/status` | Current user · service status |
| GET | `/api/v1/config` | Public client config (Maps JS key, feature flags) |
| GET | `/api/v1/experiences?category=&q=&min_rating=&limit=&offset=` | List/filter experiences |
| GET | `/api/v1/experiences/{id}` | Experience row |
| GET | `/api/v1/experiences/{id}/detail?lat=&lng=` | Enriched detail: distance, travel time, opening hours, weather, route |
| GET | `/api/v1/experiences/{id}/guides` | Guides for experience (falls back to top guides) |
| POST | `/api/v1/recommend` | Feasibility + weather-aware ranking |
| GET | `/api/v1/weather?lat=&lon=` | Normalized Open-Meteo (neutral fallback) |
| POST | `/api/v1/parse` | NL constraints → JSON (Ollama, else heuristic) |
| POST | `/api/v1/chat` | Experience-grounded guide chat (fallback if no LLM) |
| GET | `/api/v1/guides` | List guides |
| POST | `/api/v1/guides/{id}/request` | Guide request, persisted locally |
| GET | `/api/v1/guides/me/requests` | Authed user's guide requests |

### Example recommendation request

```bash
curl -X POST http://localhost:8000/api/v1/recommend -H "Content-Type: application/json" -d '{
  "location": "Bandra",
  "time_hours": 4,
  "budget_inr": 1500,
  "group_type": "friends",
  "interests": ["food", "art"],
  "accessibility": null,
  "start_time": null
}'
```

Response includes `total_candidates`, `feasible_count`, ranked `recommendations` with `why_this_fits`, `distance_km`, `travel_time_min`, `total_time_min`, `estimated_cost`, `score` + `score_parts`.

## Fallback behavior

- **Ollama down/empty model** → heuristic parse, template chat replies, template `why_this_fits`. Recommendations unaffected.
- **Weather down** → neutral context (`available: false`), no indoor/outdoor bias; `/recommend` still 200.
- **No location** → distance-neutral scoring.
- **External routing** → offline Haversine + 20 km/h Mumbai heuristic; Google Maps key not required.
- **DB is the source of truth** → no external service is mandatory for any endpoint.

## Troubleshooting

- `Dataset not found`: run from `backend/` so `data/mumbai_experiences.json` resolves.
- Empty DB: run `python -m app.seed`.
- `401` right after login: token expired or logout was called — login again.
- `409` on register: that email already exists in the local DB.
- CORS blocked: add your frontend URL to `CORS_ORIGINS` (comma-separated), restart.
- Ollama parse weirdness: `/parse` validates with Pydantic and falls back to `source: "heuristic"`.
- Port in use: `uvicorn main:app --port 8001`.

## Tests

```bash
make test-backend           # pytest suite, from the repo root
make test-live              # every endpoint against the live Google APIs
cd backend && pytest tests/ -v
```

Covers health, DB init, seed repeatability, retrieval, budget/time/opening-hours feasibility, ranking, weather boost, recommend endpoint, parser fallback, weather fallback, Ollama failure handling, and the full auth suite (hashing, register/login/logout, 401s, persistence, no plaintext secrets).

Run `make test-live` (or `python backend/tests/smoke_live.py`) for an end-to-end
check that boots the real app and calls **every** endpoint against the live
Google Places/Routes APIs and Open-Meteo: 40 checks covering health, config,
experiences (list/filter/search/detail/404/guides), recommend (WALK + DRIVE,
with and without origin, accessibility, validation), places search/nearby/photo
proxy, integrations status, weather, parse, chat, guide requests, the full auth
lifecycle, and a key-leak scan proving no server-side Google key ever reaches a
client.

## Google integration notes

Both server-side modules are optional and fail safe. Two API quirks are already
handled in code — keep them in mind before editing:

- **Routes API** rejects `routingPreference` for anything other than `DRIVE`
  ("Routing preference cannot be set for WALK or BICYCLE routing mode"), so the
  field is only sent for `DRIVE`. Adding it back silently disables all route
  enrichment and everything falls back to Haversine estimates.
- **Places API (New)** has no `places.shortDescription` field. Requesting it in
  `X-Goog-FieldMask` makes Google reject the whole request with HTTP 400, which
  disables every Places call. Descriptions are empty for Google results for that
  reason.

