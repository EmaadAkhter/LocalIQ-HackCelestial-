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
├── seed.py                   # dataset seeding            (data layer)
├── services/
│   ├── llm.py                # Ollama client (generate, chat, auth)
│   ├── parser.py             # NL → constraints (LLM + heuristic + canned)
│   ├── guide.py              # context-scoped AI guide chat
│   ├── explain.py            # template "why this fits" reasons
│   ├── recommender.py        # feasibility + ranking       (to build)
│   └── weather.py            # Open-Meteo adapter          (to build)
└── api/v1/
    ├── experiences.py
    ├── recommendations.py
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
- **One tunnel, three surfaces.** App, API, and shared model share one tunnel;
  the model route is protected by Kong key-auth.
- **Kong over nginx for APIs.** Kong gives declarative routing and plugins
  (key-auth) without bespoke config; nginx only serves static files.

## Known limitations

- Ranking is rule-based (weighted sum), not learned — deliberately, for
  explainability.
- Autoscaling (HPA) requires a real cluster with `metrics-server`; it is a
  production story, not a laptop demo.
- The AI guide can be wrong; the prompt forbids inventing specifics, but outputs
  should still be treated as guidance, not fact.
