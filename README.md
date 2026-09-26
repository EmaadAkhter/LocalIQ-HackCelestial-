# LocalIQ

> Not “what’s nearby” — **what you can actually experience right now.**

LocalIQ takes a traveller’s real constraints (time, budget, group, accessibility,
location, existing plans) and turns them into a ranked, explainable, re-rankable
shortlist of *doable* local experiences — not another generic list of places.

**Team Nexify · HackCelestial 3.0 · PS-6: Intelligent Local Discovery & Experience Platform**

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

## Repository layout

```text
localIQ/
├── backend/                 # FastAPI app (Dockerfile included)
├── frontend_flutter/        # Flutter client (web + iOS + Android)  [to be added]
├── frontend_legacy/         # previous Next.js web app (reference)
├── gateway/                 # Caddy (edge), Kong (API), nginx (static web)
├── infra/
│   ├── docker-compose.yml             # local-LLM mode (owner)
│   ├── docker-compose.remote-llm.yml  # remote-LLM mode (teammates)
│   ├── jenkins/                       # self-hosted Jenkins + JCasC
│   └── k8s/                           # Kubernetes manifests + HPA
├── docs/                    # architecture, deployment, dev, ethics, jenkins
├── scripts/                 # dev.sh, tunnel.sh, tunnel-setup.sh
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

> Backend + data layer complete: PostgreSQL seeded with the Mumbai dataset,
> feasibility/ranking engine live, self-hosted Jenkins CI with GitHub push
> triggers, and a named Cloudflare tunnel on `tavesglobal.com`. Next: the
> Flutter client. See [`PLAN.md`](PLAN.md).

## License

[MIT](LICENSE) © 2026 Team Nexify.
