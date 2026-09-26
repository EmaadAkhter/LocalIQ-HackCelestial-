# Architecture

## Overview

LocalIQ turns traveller constraints into a ranked, explainable shortlist of
*doable* local experiences. It is a self-hosted system with a local LLM, designed
to run entirely on one machine and be exposed through a single Cloudflare Tunnel.

## Components

| Component | Technology | Role |
|---|---|---|
| Web + mobile client | Flutter (web, iOS, Android) | Constraint form, results, map, guide chat |
| Legacy web client | Next.js (`frontend_legacy/`) | Previous web app, kept for reference |
| API | FastAPI + SQLModel | Parsing, recommendations, chat, weather |
| Database | PostgreSQL (SQLite for native dev) | Experiences, guides, itineraries |
| LLM | Ollama (local or shared) | Constraint parsing, AI guide chat |
| API gateway | Kong (DB-less) | Routing, `/llm` key-auth |
| Edge proxy | Caddy | Routing, gzip, single ingress |
| Static host | nginx | Serves the Flutter web bundle |
| Tunnel | cloudflared | Public access to the edge |
| CI | Jenkins (self-hosted) | Lint, build images, smoke test |

## Request flow

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

## Backend modules

```text
backend/app/
├── config.py                 # typed settings (env / .env)
├── schemas.py                # Pydantic request/response models
├── models.py                 # SQLModel tables            (data layer)
├── database.py               # engine + session           (data layer)
├── vector.py                 # pgvector / SQLite JSON vector column
├── seed.py                   # dataset + tags + packages seeding
├── services/
│   ├── llm.py                # Ollama client (generate, chat, auth)
│   ├── embeddings.py         # Ollama embeddings + deterministic fallback
│   ├── semantic_search.py    # pgvector / SQLite cosine + tag hybrid search
│   ├── parser.py             # NL → constraints (LLM + heuristic + canned)
│   ├── guide.py              # context-scoped AI guide chat
│   ├── explain.py            # template "why this fits" reasons
│   ├── recommender.py        # feasibility + ranking
│   ├── discovery.py          # SearXNG search + scrape + candidate extraction
│   └── weather.py            # Open-Meteo adapter
└── api/v1/
    ├── experiences.py
    ├── recommendations.py    # semantic + tag-aware ranking
    ├── tags.py               # taxonomy, composite tags, by-tag lookup
    ├── discovery.py          # /discover candidate pipeline
    ├── guide_packages.py     # packages, bookings, availability, reviews
    ├── guides.py
    ├── parse.py
    ├── chat.py
    └── weather.py
```

## Design decisions

- **Feasibility before ranking.** Hard filters (time, budget, opening hours,
  accessibility) run before scoring, so nothing infeasible is ever ranked.
- **Deterministic explainability.** Reasons are generated from templates, not an
  LLM, so they are instant and never wrong.
- **Graceful LLM degradation.** Every LLM call has a fallback: parser → heuristic,
  chat → canned. `DEMO_MODE=true` forces canned responses for a stable demo.
- **Semantic search is optional and self-hosted.** `use_semantic=true` embeds the
  intent via Ollama; embeddings are stored as `pgvector` on Postgres and JSON on
  SQLite through one `Vector` type. When the model or vectors are missing the
  query degrades to tag + rating retrieval, never an error.
- **One taxonomy everywhere.** Experiences, guides and quests reference the same
  master tag list (`data/tag_taxonomy.json`) so filters, semantic queries and
  composite tags share vocabulary.
- **Discovery is provenance-first.** SearXNG results are scraped into
  `hidden_gem_candidates` with `sources`/`mentions` rows; nothing becomes a real
  experience until an admin approves it, keeping the curated dataset trustworthy.
- **Extraction prefers the LLM but never depends on it.** Candidate extraction
  prompts the local Ollama model for JSON constrained to the taxonomy and known
  Mumbai areas; unparseable output, a missing model or a test environment falls
  back to a deterministic heuristic extractor. SearXNG snippets are used when a
  site blocks scraping, so discovery still works within a modest footprint.
  `discovery_llm_concurrency=1` by default because a single laptop Ollama
  serializes generations.
- **One named tunnel, four surfaces.** App, API, shared model, and Jenkins share
  one Cloudflare tunnel on `tavesglobal.com`; the model route is protected by
  Kong key-auth and Jenkins by its own login.
- **Kong over nginx for APIs.** Kong gives declarative routing and plugins
  (key-auth) without bespoke config; nginx only serves static files.

## Known limitations

- Ranking is rule-based (weighted sum), not learned — deliberately, for
  explainability.
- Autoscaling (HPA) requires a real cluster with `metrics-server`; it is a
  production story, not a laptop demo.
- The AI guide can be wrong; the prompt forbids inventing specifics, but outputs
  should still be treated as guidance, not fact.
