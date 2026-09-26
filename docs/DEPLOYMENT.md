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

### Public tunnel

```bash
cd infra
docker compose --env-file .env --profile tunnel up -d
# or, from the host:
scripts/tunnel.sh
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
| `CORS_ORIGINS` | backend | comma-separated allowed origins |
| `HTTP_PORT` | infra | host port for the Caddy edge (default `8080`) |
| `FLUTTER_WEB_DIR` | infra | path to the Flutter web build |

## Rollback

- Docker: `docker compose -p localiq down` then redeploy the previous image tag.
- K8s: `kubectl rollout undo deployment/backend -n localiq`.
