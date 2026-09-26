.PHONY: install dev backend frontend tunnel lint typecheck \
	infra-up infra-down infra-tunnel infra-logs k8s-apply k8s-delete

# Install all dependencies
install:
	cd backend && pip install -r requirements.txt
	cd frontend && npm install

# Run both frontend and backend
dev:
	./scripts/dev.sh

# Run backend only
backend:
	cd backend && uvicorn main:app --reload --host 0.0.0.0 --port 8000

# Run frontend only
frontend:
	cd frontend && npm run dev

# Create tunnel for external access
tunnel:
	./scripts/tunnel.sh

# Lint Python backend
lint-backend:
	cd backend && ruff check .

# Lint TypeScript frontend
lint-frontend:
	cd frontend && npm run lint

# Lint all
lint: lint-backend lint-frontend

# Typecheck Python backend
typecheck-backend:
	cd backend && mypy .

# Typecheck TypeScript frontend
typecheck-frontend:
	cd frontend && npm run typecheck

# Typecheck all
typecheck: typecheck-backend typecheck-frontend

# ---- Infrastructure ----

# Start the full local stack (Postgres, backend, Kong, Caddy, static web) + host Ollama
infra-up:
	cd infra && docker compose --env-file .env up -d --build

infra-down:
	cd infra && docker compose --env-file .env down

# Start the stack and open a public Cloudflare quick tunnel
infra-tunnel:
	cd infra && docker compose --env-file .env --profile tunnel up -d

infra-logs:
	cd infra && docker compose --env-file .env logs -f

# Deploy the Kubernetes manifests (needs a cluster; HPA needs metrics-server)
k8s-apply:
	kubectl apply -k infra/k8s

k8s-delete:
	kubectl delete -k infra/k8s