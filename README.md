<div align="center">
  <table>
    <tr>
      <td align="center" valign="middle">
        <img src="./assets/localiq-logo.png" width="145" alt="LocalIQ Logo">
      </td>
      <td align="left" valign="middle">
        <h1>LocalIQ</h1>
        <p><strong>Discover Local. Smarter.</strong><br>
        Not “what’s nearby” — what you can actually experience right now.</p>
      </td>
    </tr>
  </table>

  <p><strong>Flutter · FastAPI · PostgreSQL · Ollama · Google Maps · Kong · Caddy · Docker · Kubernetes · Jenkins</strong></p>
  <p>Team Nexify · HackCelestial 3.0 · PS-6: Intelligent Local Discovery &amp; Experience Platform</p>
</div>

LocalIQ takes a traveller’s real constraints (time, budget, group, accessibility,
location, existing plans) and turns them into a ranked, explainable, re-rankable
shortlist of *doable* local experiences — not another generic list of places.

---

## Architecture

```text
Client
  │
  ▼
cloudflared  ──►  Caddy :80
                    ├── /              → nginx (Flutter web)
                    ├── /api/v1/*      → Kong → FastAPI
                    └── /llm/*         → Kong (key-auth) → Ollama
                                            │
FastAPI ──► PostgreSQL
        └─► Ollama (local, or shared via tunnel)
```

- **Frontend:** Flutter (web + iOS + Android)
- **Backend:** FastAPI + SQLModel
- **Database:** PostgreSQL (SQLite for native dev)
- **LLM:** local Ollama, shareable to teammates via Kong key-auth + tunnel
- **Gateway:** Kong (API gateway) behind Caddy (edge proxy)
- **CI/CD:** self-hosted Jenkins
- **Orchestration:** Docker Compose + Kubernetes (HPA)

Details: [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md).

## Features

### Recommendation engine
- **Feasibility-first filtering:** budget, time (visit + travel + buffer),
  opening hours (overnight-aware), accessibility (wheelchair/step-free) and max
  day-trip distance — nothing infeasible is ever ranked.
- **Semantic retrieval:** `use_semantic=true` embeds the free-text intent with a
  self-hosted model (`nomic-embed-text` via Ollama) and retrieves by cosine
  similarity; pgvector on Postgres, a JSON-vector brute-force fallback on SQLite.
  Falls back to tag + rating order when no embeddings exist yet.
- **Taxonomy-aware filtering:** `required_tags` / `excluded_tags` filter on the
  master tag taxonomy, composable with semantic or keyword retrieval.
- **Weighted ranking:** interest match, time fit, budget fit, distance, rating,
  local-gem score, semantic rank, weather boost and aggregated user feedback.
- **Deterministic explainability:** every result carries a plain-language
  `why_this_fits` (templates, not an LLM) that names the semantic query and any
  matched tags.
- **Travel-time heuristic:** haversine distance + Mumbai city-speed model.
- **Location resolution:** ~40 Mumbai area anchors with substring matching.
- **“N candidates → M feasible”** reveal, preserved even with SQL pre-filtering.

### AI / LLM
- **Natural-language parsing** (`/parse`) via local Ollama with a heuristic regex
  fallback and a few-shot prompt.
- **Structured-output normalisation** — coerces `"null"` strings, `"₹1,500"`,
  numeric strings, comma interests, list accessibility, group synonyms, `HH:MM`.
- **Guide chat** (`/chat`) grounded in one experience, with intent-aware canned
  fallbacks; `DEMO_MODE=true` forces canned responses.
- **Resilience:** one shared HTTP client, exponential-backoff retries, a
  per-prompt TTL cache and per-endpoint timeouts; LLM failures never 500 a request.

### Data
- 48 curated Mumbai experiences + 12 guides, seeded idempotently.
- **Master tag taxonomy** (180+ tags + composite filters) in
  `data/tag_taxonomy.json`, backfilled onto every experience as `experience_tags`.
- **End-to-end guide packages:** pickup → ordered stops → drop-off, seeded from
  each guide’s own route plus nearby experiences.
- **Discovery pipeline:** SearXNG-backed search, page scraping (with a
  search-snippet fallback when a site blocks bots), then **local-LLM candidate
  extraction** constrained to the tag taxonomy and known Mumbai areas. Results
  land in `hidden_gem_candidates` with `sources` / `mentions` provenance, plus an
  admin approve/reject curation flow. Falls back to a deterministic heuristic
  extractor when the model is unavailable.
- Alembic migrations applied on startup (`alembic check` drift-free).
- `created_at` / `updated_at` on every table, composite indexes for hot queries
  and Postgres pool tuning. SQLite for native dev/tests.

### API
- Auth, experiences, recommendations (semantic + tag aware), tags, discovery,
  guide packages (bookings, availability, reviews), guides, parse, chat, weather,
  itineraries, favorites, nearby, feedback, admin and client config. Swagger at
  `/docs`, ReDoc at `/redoc`, schema at `/openapi.json`.

### Auth & security
- PBKDF2-SHA256 passwords; opaque session tokens stored only as HMAC hashes.
- Password policy, login lockout, per-IP rate limits, explicit CORS allow-list.
- Unified error schema with no stack-trace leakage.

### Observability & performance
- `X-Request-ID` on every response, structured JSON logs and Prometheus `/metrics`.
- `/readyz` readiness (Postgres required, Ollama reported).
- Weather cache (10 min), recommendation cache (60 s), LLM response cache.

### Infrastructure & CI
- Docker Compose in two modes (local-LLM, remote-LLM); Caddy → Kong → FastAPI.
- **Self-hosted SearXNG** alongside pgvector/Postgres for the discovery pipeline.
- Kubernetes manifests with HPA; self-hosted Jenkins with a GitHub push webhook
  and an 80% coverage gate; named Cloudflare tunnel on `tavesglobal.com`.
- Multi-stage backend image on Python 3.12 (non-root), secrets-from-file and
  database backup/restore scripts.

## Repository layout

```text
localIQ/
├── backend/                 # FastAPI app (Dockerfile included)
├── frontend_flutter/        # Flutter client (web + iOS + Android)
├── frontend_legacy/         # previous Next.js web app (reference)
├── gateway/                 # Caddy (edge), Kong (API), nginx (static web)
├── infra/
│   ├── docker-compose.yml             # local-LLM mode (owner)
│   ├── docker-compose.remote-llm.yml  # remote-LLM mode (teammates)
│   ├── jenkins/                       # self-hosted Jenkins + JCasC
│   └── k8s/                           # Kubernetes manifests + HPA
├── docs/                    # architecture, deployment, dev, ethics, jenkins
├── scripts/                 # dev, tunnel, db backup/restore, maps keys
├── tests/smoke/             # end-to-end smoke test
├── Jenkinsfile              # CI pipeline
├── Makefile
├── README.md
├── SECURITY.md
├── CONTRIBUTING.md
├── CODE_OF_CONDUCT.md
├── LICENSE
└── PLAN.md
```

## Quick start

Native development:

```bash
make install
make dev            # backend :8000 + legacy frontend :3000
```

Docker (full stack + local model):

```bash
cd infra && cp .env.example .env
cd .. && make infra-up      # edge on http://localhost:8080
```

Discovery (SearXNG + local-LLM extraction):

```bash
# SearXNG (compose service, published on host port 8888)
cd infra && docker compose up -d searxng

# Local model for parsing/chat and candidate extraction (optional but recommended)
ollama pull llama3.2:3b
ollama pull nomic-embed-text     # semantic search embeddings

# backend/.env (native dev)
#   SEARXNG_URL=http://localhost:8888
#   OLLAMA_MODEL=llama3.2:3b
#   EMBEDDING_MODEL=nomic-embed-text
```

Then `POST /api/v1/discover` with `{"query": "hidden heritage spots", "area": "Bandra"}`.
LLM extraction takes ~15–25s per page, so discovery is a curation tool rather
than a hot path; set `discovery_use_llm=false` to use the instant heuristic
extractor instead.

CI (self-hosted Jenkins):

```bash
cd infra/jenkins && cp .env.example .env   # set admin password + DOCKER_SOCK
cd ../.. && make jenkins-up                # http://localhost:8081
```

Run `make help` for all targets.

## Sharing the local model

A single named Cloudflare tunnel serves the app, the API, Jenkins, and the
shared LLM (one-time setup: `make tunnel-setup`).

```bash
make tunnel          # runs the `localiq` tunnel in the foreground
```

Public URLs:

| Surface | URL |
|---|---|
| App (Flutter web) | https://localiq.tavesglobal.com |
| API | https://localiq.tavesglobal.com/api/v1/... |
| API docs (Swagger) | https://localiq.tavesglobal.com/docs |
| Shared model | https://localiq.tavesglobal.com/llm (Kong key-auth) |
| CI | https://jenkins.tavesglobal.com |

Teammates then set:

```bash
export OLLAMA_URL=https://localiq.tavesglobal.com/llm
export OLLAMA_API_KEY=localiq-shared-key
```

## Documentation

| Doc | Contents |
|---|---|
| [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md) | components, flows, decisions |
| [`docs/DEVELOPMENT.md`](docs/DEVELOPMENT.md) | local setup and checks |
| [`docs/DEPLOYMENT.md`](docs/DEPLOYMENT.md) | Docker, K8s, tunnel, env vars |
| [`docs/JENKINS.md`](docs/JENKINS.md) | CI/CD setup and security |
| [`docs/ETHICS.md`](docs/ETHICS.md) | AI, data, accessibility ethics |
| [`SECURITY.md`](SECURITY.md) | reporting and hardening |
| [`CONTRIBUTING.md`](CONTRIBUTING.md) | branching, commits, style |
| [`PLAN.md`](PLAN.md) | phased roadmap |

## Demo reliability

- The dataset is **seeded locally** — never depend on a live external API on stage.
- Constraint parsing and guide chat fall back to heuristics / canned responses
  (`DEMO_MODE=true` forces canned responses).
- Weather and maps are progressive enhancements, not hard dependencies.
- Keep a `localhost` fallback ready in case the tunnel drops mid-demo.

## Status

> All seven backend phases are complete: PostgreSQL data layer, feasibility +
> ranking engine, local-LLM parsing and chat, auth hardening, caching,
> observability (Prometheus + structured logs) and operations (multi-stage image,
> secrets-from-file, backups). Self-hosted Jenkins builds on every push with an
> 80% coverage gate, and a named Cloudflare tunnel serves the stack on
> `tavesglobal.com`.
>
> The Flutter client lives in `frontend_flutter/`. Remaining: build it for web
> and point `FLUTTER_WEB_DIR` at the output, and supply the Google Maps keys.

## License

[MIT](LICENSE) © 2026 Team Nexify.
