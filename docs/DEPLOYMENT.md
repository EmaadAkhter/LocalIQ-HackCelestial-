# Deployment

## Environments

- **Native dev** — backend on `:8000`, client dev server, host Ollama.
- **Docker (local)** — full stack via Docker Compose on one machine.
- **Kubernetes** — production-shaped manifests with HPA.

## Docker

Copy the env file:

```bash
cd infra && cp .env.example .env
```

### Local-LLM mode (owner's machine)

```bash
cd infra
docker compose --env-file .env up -d --build
```

Edge: `http://localhost:8080`.

### Remote-LLM mode (teammates)

```bash
export OLLAMA_URL=https://<shared-host>/llm
export OLLAMA_API_KEY=localiq-shared-key
cd infra
docker compose -f docker-compose.remote-llm.yml --env-file .env up -d --build
```

### Public tunnel (Cloudflare, named)

One named tunnel (`localiq`) serves the app, the API, Jenkins, and the shared
LLM. TLS terminates at Cloudflare's edge; cloudflared dials out, so no ports are
opened on the host.

One-time setup (already done on the owner's machine):

```bash
cloudflared tunnel login                 # browser; pick tavesglobal.com
make tunnel-setup                        # creates the tunnel + DNS routes
```

Run it (foreground) against the running stack:

```bash
make tunnel
# or: ./scripts/tunnel.sh
```

Public URLs:

| Surface | URL |
|---|---|
| App (Flutter web) | https://localiq.tavesglobal.com |
| API | https://localiq.tavesglobal.com/api/v1/... |
| API docs (Swagger / ReDoc) | https://localiq.tavesglobal.com/docs · `/redoc` · `/openapi.json` |
| Shared model (key-auth) | https://localiq.tavesglobal.com/llm |
| CI | https://jenkins.tavesglobal.com |

Config: `infra/cloudflared/config.yml`. Credentials are git-ignored
(`infra/cloudflared/*.json`).

Teammates using the shared model:

```bash
export OLLAMA_URL=https://localiq.tavesglobal.com/llm
export OLLAMA_API_KEY=localiq-shared-key
```

## Kubernetes

```bash
kubectl apply -k infra/k8s
```

- Images: `localiq-backend:latest` (built from `backend/`) and
  `localiq-frontend:latest` (built from `frontend_flutter/` once it exists).
- `infra/k8s/ollama.yaml` is optional (CPU-only in-cluster model).
- HPA needs `metrics-server` and cluster capacity.
- Put the Cloudflare tunnel token in `infra/k8s/cloudflared.yaml`.

## Jenkins (CI)

See [`JENKINS.md`](JENKINS.md). Jenkins is optional for local dev but drives the
build on `main`.

## Environment variables

| Variable | Used by | Notes |
|---|---|---|
| `DATABASE_URL` | backend | SQLite for native, Postgres in Docker/K8s |
| `OLLAMA_URL` | backend | `http://localhost:11434` or `https://<host>/llm` |
| `OLLAMA_MODEL` | backend | default `llama3.2:3b` |
| `OLLAMA_API_KEY` | backend | set only for the shared, tunnelled model |
| `DEMO_MODE` | backend | `true` forces canned LLM responses |
| `CORS_ORIGINS` | backend | comma-separated allowed origins (no `*`) |
| `LOG_JSON` | backend | `true` emits newline-delimited JSON logs |
| `RATE_LIMIT_ENABLED` | backend | per-IP limits; auto-off when `APP_ENV=test` |
| `LOGIN_MAX_ATTEMPTS` | backend | failed logins before lockout (default `5`) |
| `LOGIN_LOCKOUT_MINUTES` | backend | lockout window (default `15`) |
| `AUTH_SECRET_KEY` | backend | HMAC key for session-token hashing |
| `DB_POOL_SIZE` | backend | Postgres pool size (default `5`) |
| `DB_MAX_OVERFLOW` | backend | Postgres overflow connections (default `10`) |
| `DB_POOL_RECYCLE_SECONDS` | backend | recycle idle connections (default `1800`) |
| `LLM_PARSE_TIMEOUT_SECONDS` | backend | `/parse` LLM timeout (default `20`) |
| `LLM_CHAT_TIMEOUT_SECONDS` | backend | `/chat` LLM timeout (default `30`) |
| `LLM_WARM_TIMEOUT_SECONDS` | backend | startup warm-up timeout (default `5`) |
| `LLM_MAX_RETRIES` | backend | retries on transient LLM failures (default `2`) |
| `LLM_RETRY_BACKOFF_SECONDS` | backend | exponential-backoff base (default `0.5`) |
| `LLM_CACHE_ENABLED` | backend | memoise identical prompts (default `true`) |
| `LLM_CACHE_TTL_SECONDS` | backend | response cache TTL (default `300`) |
| `WEATHER_CACHE_TTL_SECONDS` | backend | weather cache TTL (default `600`) |
| `RECOMMEND_CACHE_ENABLED` | backend | cache identical `/recommend` calls (default `true`) |
| `RECOMMEND_CACHE_TTL_SECONDS` | backend | recommendation cache TTL (default `60`) |
| `IMAGE_PLACEHOLDER_URL_TEMPLATE` | backend | `{seed}` image placeholder; empty disables |
| `ADMIN_API_KEY` | backend | enables `/api/v1/admin/*` (empty disables); sent as `X-Admin-Key` |
| `FEEDBACK_WEIGHT` | backend | ranking nudge from aggregated feedback (default `4.0`) |
| `HTTP_PORT` | infra | host port for the Caddy edge (default `8080`) |
| `FLUTTER_WEB_DIR` | infra | path to the Flutter web build |

## Database migrations

The schema is owned by **Alembic** (`backend/alembic/`). The backend applies
pending migrations automatically on startup (except in tests, which use
`create_all`). Manual commands, from `backend/`:

```bash
alembic upgrade head                       # apply all migrations
alembic revision --autogenerate -m "msg"   # new revision from model changes
alembic downgrade -1                       # roll back one
alembic check                              # fail if models drift from migrations
```

Or via `make db-migrate` / `make db-revision m="msg"` / `make db-downgrade`.

Tables carry `created_at` / `updated_at` (naive UTC) and composite indexes for
the common query shapes (`experiences(category, rating)`, `experiences(lat, lng)`,
`guide_requests(user_id, created_at)`, `user_sessions(user_id, expires_at)`).

## Observability & hardening

| Concern | Where |
|---|---|
| Liveness | `GET /healthz` (edge) / `GET /health` (backend) |
| Readiness | `GET /readyz` — checks Postgres (required) + Ollama (reported) |
| API docs | `GET /docs`, `/redoc`, `/openapi.json` |
| Request tracing | `X-Request-ID` echoed on every response; present in JSON logs |
| Structured logs | one JSON line per request: method, path, status, duration_ms, request_id |
| Error shape | every failure returns `{error, message, request_id, path, status_code}` |
| Rate limits | reads 60/min · recommend 30/min · parse & chat 20/min · auth 10/min |
| Login lockout | 5 failed attempts → 15-minute lock (per email) |
| Metrics | `GET /metrics` — Prometheus; **backend-only** (the edge does not route it) |
| Coverage | `make test-cov`; CI fails under 80% |
| Load check | `make loadtest` → `backend/tests/load/loadtest.py` |

Prometheus metric families: `localiq_http_requests_total`,
`localiq_http_request_duration_seconds` (labelled by method/route/status),
`localiq_llm_cache_*`, `localiq_weather_cache_entries`,
`localiq_recommend_cache_*`, `localiq_db_pool_checked_out`.

> Rate-limit state and login lockout are in-memory: correct for the single
> backend container this deployment runs. A multi-replica setup needs Redis.

### Product APIs

| Area | Endpoints |
|---|---|
| Itineraries | `POST/GET/PUT/DELETE /api/v1/itineraries[/{id}]` — user-owned, totals + travel time computed |
| Favorites | `GET/POST/DELETE /api/v1/me/favorites[/{experience_id}]` — idempotent save/unsave |
| Discovery | `GET /api/v1/experiences/nearby?lat=&lng=&radius_km=` — bbox + haversine, distance-sorted |
| Feedback | `POST /api/v1/recommendations/{experience_id}/feedback` — thumbs up/down nudges ranking |
| Admin | `POST/PATCH/DELETE /api/v1/admin/experiences[/{id}]` — requires `X-Admin-Key` |

Itineraries and favorites require a session token. Feedback is accepted from
anonymous users too. Admin endpoints return `503` unless `ADMIN_API_KEY` is set.

### Caching & query efficiency

- **Weather** is cached per coordinate for `WEATHER_CACHE_TTL_SECONDS` (10 min),
  so `/recommend` does not call Open-Meteo on every request. Failures are not
  cached and fall back to neutral context.
- **Recommendations** are cached per constraint set for
  `RECOMMEND_CACHE_TTL_SECONDS` (60 s) — repeated slider drags are instant.
- **Budget** is a hard feasibility filter, so it is applied in SQL
  (`avg_cost <= budget`) before ranking instead of loading every row. The full
  pool size is still counted separately, so the "N candidates → M feasible"
  reveal is unchanged.
- **Images**: every experience gets an `image_url`; curated URLs win, otherwise a
  deterministic placeholder is generated from the name.

### LLM reliability

The Ollama client uses one shared connection-pooled HTTP client (created lazily,
closed on shutdown), retries transient failures (`429`/`5xx`, connect/read
timeouts) with exponential backoff, memoises identical prompts in a TTL cache,
and applies per-endpoint timeouts. Every call degrades to the heuristic parser
or canned chat reply instead of failing the request. The cache is in-memory and
per-process.

## Operations

### Images

The backend image is a **multi-stage** build on **Python 3.12 (LTS)**:

- `builder` installs runtime deps into `/opt/venv`,
- `test` adds dev deps (`--target test`) and is what CI runs `pytest` in,
- `runtime` (default) ships only the venv + app, runs as non-root `appuser`,
  and excludes `pip`/`curl` (healthcheck uses the stdlib).

```bash
docker build -t localiq-backend:local backend/                    # runtime
docker build -t localiq-backend-test:local --target test backend/ # CI
```

### Secrets from files

Any of `DATABASE_URL`, `AUTH_SECRET_KEY`, `OLLAMA_API_KEY`, `ADMIN_API_KEY`
can be supplied as a file via `<KEY>_FILE` (Docker/K8s secrets). An explicit
environment value always wins.

```yaml
environment:
  DATABASE_URL_FILE: /run/secrets/database_url
```

### Backups

```bash
make db-backup                       # -> backups/localiq-<timestamp>.sql
make db-restore f=backups/<file>.sql # overwrites the target DB
```

Dumps land in `backups/` (git-ignored).

## Rollback

- Docker: `docker compose -p localiq down` then redeploy the previous image tag.
- K8s: `kubectl rollout undo deployment/backend -n localiq`.
