# LocalIQ

> Not “what’s nearby” — **what you can actually experience right now.**

LocalIQ takes a traveller’s real constraints (time, budget, group, accessibility, location,
existing plans) and turns them into a ranked, explainable, re-rankable shortlist of *doable*
local experiences — not another generic list of places.

**Team Nexify · HackCelestial 3.0 · PS-6: Intelligent Local Discovery & Experience Platform**

---

## Architecture

```text
Judge / teammate
      │
      ▼
Cloudflare Tunnel (cloudflared)
      │
      ▼
Caddy (edge: routing, gzip)              gateway/caddy
      ├── /            → nginx (Flutter web)   gateway/nginx
      ├── /api/v1/*    → Kong → FastAPI        gateway/kong
      └── /llm/*       → Kong (key-auth) → Ollama (shared model)
                              │
                              ├── PostgreSQL
                              └── Ollama (local or shared)
```

- **Frontend:** Flutter (web + iOS + Android) — served as static web via nginx
- **Backend:** FastAPI + SQLModel
- **Database:** PostgreSQL (SQLite for native dev)
- **LLM:** local Ollama, shareable to teammates through Kong key-auth + the tunnel
- **Gateway:** Kong (API gateway, key-auth) behind Caddy (edge proxy)
- **Orchestration:** Docker Compose (local) and Kubernetes (HPA-autoscaled, roadmap)

## Repository structure

```text
localIQ/
├── backend/                 # FastAPI app (Dockerfile included)
│   ├── app/
│   ├── data/
│   └── requirements.txt
├── frontend/                # legacy Next.js web app (being replaced by Flutter)
├── frontend_flutter/        # Flutter app (web + iOS + Android)  [to be added]
├── gateway/
│   ├── caddy/Caddyfile      # edge reverse proxy
│   ├── kong/kong.yml        # API routes + LLM key-auth
│   └── nginx/nginx.conf     # static Flutter web host
├── infra/
│   ├── docker-compose.yml             # local-LLM mode (your machine)
│   ├── docker-compose.remote-llm.yml  # remote-LLM mode (teammates)
│   ├── k8s/                           # Kubernetes manifests + HPA + kustomization
│   └── .env.example
└── scripts/
    ├── dev.sh
    └── tunnel.sh            # Cloudflare quick tunnel
```

## Prerequisites

- Docker + Docker Compose
- [Ollama](https://ollama.com/) (local model)
- [cloudflared](https://developers.cloudflare.com/cloudflare-one/connections/connect-networks/)
- Flutter SDK (frontend)
- Python 3.11+ and Node.js 20+ (native dev)

## Docker: two ways to compose

Copy the env file first:

```bash
cd infra && cp .env.example .env
```

### 1. Local-LLM mode (your machine)

Runs Postgres, backend, Kong, Caddy, nginx, and talks to Ollama on your host.

```bash
cd infra
docker compose --env-file .env up -d --build
# optional: add a public Cloudflare tunnel
docker compose --env-file .env --profile tunnel up -d
```

Edge is on http://localhost:8080.

### 2. Remote-LLM mode (teammates without Ollama)

Point the backend at a shared, tunnelled model:

```bash
export OLLAMA_URL=https://<shared-host>/llm
export OLLAMA_API_KEY=localiq-shared-key
cd infra
docker compose -f docker-compose.remote-llm.yml --env-file .env up -d --build
```

## Sharing your local model

A single Cloudflare tunnel serves the app, the API, **and** the model:

```bash
scripts/tunnel.sh            # tunnels http://localhost:8080
```

Give teammates the printed URL plus the shared key. The `/llm/*` route is protected by
Kong `key-auth`; requests must send `apikey: localiq-shared-key`.

## Kubernetes (roadmap / production story)

```bash
kubectl apply -k infra/k8s        # namespace, postgres, backend, kong, caddy, flutter-web, cloudflared, HPA
```

Notes:
- `infra/k8s/ollama.yaml` is optional (CPU-only in-cluster model server).
- Autoscaling needs `metrics-server` and enough cluster capacity; HPA will not visibly
  scale on a single-node laptop without load.
- Put your tunnel token in `infra/k8s/cloudflared.yaml` (or create the secret with `kubectl`).

## Native development

```bash
make install    # backend (pip) + frontend (npm) deps
make dev        # run frontend + backend together
make backend    # uvicorn on :8000
make frontend   # next dev on :3000 (legacy)
make infra-up   # docker compose stack
make k8s-apply  # kubernetes manifests
```

## Demo reliability

- The dataset is **seeded locally** — never depend on a live external API during the pitch.
- Constraint parsing and guide chat fall back to heuristics / canned responses
  (`DEMO_MODE=true` forces canned responses).
- Weather and maps are progressive enhancements, not hard dependencies.
- Keep a `localhost` fallback ready in case the tunnel drops mid-demo.

## Status

> AI backend complete (constraint parsing, AI guide chat, explainability). Infrastructure
> complete (Docker, Kong, Caddy, nginx, Kubernetes manifests, Cloudflare tunnel). Next:
> PostgreSQL data layer + feasibility/ranking engine, and the Flutter frontend.
> See [`PLAN.md`](./PLAN.md) for the phased roadmap.
