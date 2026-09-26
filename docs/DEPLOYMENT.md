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

> Rate-limit state and login lockout are in-memory: correct for the single
> backend container this deployment runs. A multi-replica setup needs Redis.

### LLM reliability

The Ollama client uses one shared connection-pooled HTTP client (created lazily,
closed on shutdown), retries transient failures (`429`/`5xx`, connect/read
timeouts) with exponential backoff, memoises identical prompts in a TTL cache,
and applies per-endpoint timeouts. Every call degrades to the heuristic parser
or canned chat reply instead of failing the request. The cache is in-memory and
per-process.

## Rollback

- Docker: `docker compose -p localiq down` then redeploy the previous image tag.
- K8s: `kubectl rollout undo deployment/backend -n localiq`.
