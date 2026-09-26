# Development

## Prerequisites

- Python 3.11+
- Node.js 20+ (legacy web client only)
- Flutter SDK (client)
- Docker + Docker Compose
- Ollama

## Backend

```bash
cd backend
python3 -m venv venv
source venv/bin/activate
pip install -r requirements.txt
cp .env.example .env
uvicorn main:app --reload --port 8000
```

The API is served at `http://localhost:8000`. Interactive docs:
`http://localhost:8000/docs`.

### Local LLM

```bash
brew services start ollama      # or: ollama serve
ollama pull llama3.2:3b
```

The backend warms the model on startup (non-fatal if Ollama is down).

### Useful endpoints

| Endpoint | Purpose |
|---|---|
| `GET /health` | health check |
| `POST /api/v1/parse/` | free text → structured constraints |
| `POST /api/v1/chat/` | context-scoped AI guide reply |

## Client

The target client is Flutter (`frontend_flutter/`, not yet created):

```bash
cd frontend_flutter
flutter pub get
flutter run -d chrome     # web
flutter run               # device/emulator
```

The legacy Next.js client is in `frontend_legacy/`:

```bash
cd frontend_legacy
npm install
npm run dev
```

## Gateway

```bash
cd infra
docker compose --env-file .env up -d
curl -fsS http://localhost:8080/healthz
```

## Checks

```bash
make lint        # backend + frontend
make typecheck
make test        # smoke test against the Docker stack
```

## Conventions

- Formatting: [`.editorconfig`](../.editorconfig).
- Commits: Conventional Commits (see [`CONTRIBUTING.md`](../CONTRIBUTING.md)).
- Shell scripts: `#!/usr/bin/env bash` + `set -euo pipefail`.
