.PHONY: help install install-backend install-frontend dev backend frontend-legacy \
	tunnel lint lint-backend lint-frontend typecheck typecheck-backend typecheck-frontend \
	test infra-up infra-down infra-tunnel infra-logs \
	jenkins-up jenkins-down jenkins-logs k8s-apply k8s-delete

help: ## Show available targets
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-20s\033[0m %s\n", $$1, $$2}'

# ---- Install ----

install: install-backend install-frontend ## Install backend + legacy frontend deps

install-backend: ## Install backend Python deps
	cd backend && pip install -r requirements.txt

install-frontend: ## Install legacy frontend deps
	cd frontend_legacy && npm install

# ---- Native development ----

dev: ## Run backend + legacy frontend together
	./scripts/dev.sh

backend: ## Run the API (uvicorn on :8000)
	cd backend && uvicorn main:app --reload --host 0.0.0.0 --port 8000

frontend-legacy: ## Run the legacy Next.js app
	cd frontend_legacy && npm run dev

# ---- Quality ----

lint: lint-backend lint-frontend ## Lint backend + frontend

lint-backend: ## Lint the Python backend
	cd backend && ruff check . || true

lint-frontend: ## Lint the legacy frontend
	cd frontend_legacy && npm run lint

typecheck: typecheck-backend typecheck-frontend ## Typecheck backend + frontend

typecheck-backend: ## Typecheck the Python backend
	cd backend && mypy . || true

typecheck-frontend: ## Typecheck the legacy frontend
	cd frontend_legacy && npm run typecheck

test: ## Run the end-to-end smoke test
	bash tests/smoke/smoke.sh

# ---- Docker infrastructure ----

infra-up: ## Start the Docker stack (local LLM)
	cd infra && docker compose --env-file .env up -d --build

infra-down: ## Stop the Docker stack
	cd infra && docker compose --env-file .env down

infra-tunnel: ## Start the stack with a public Cloudflare tunnel
	cd infra && docker compose --env-file .env --profile tunnel up -d

infra-logs: ## Tail Docker stack logs
	cd infra && docker compose --env-file .env logs -f

tunnel: ## Expose the app via a Cloudflare quick tunnel
	./scripts/tunnel.sh

# ---- Jenkins ----

jenkins-up: ## Start self-hosted Jenkins
	cd infra/jenkins && docker compose -f docker-compose.jenkins.yml --env-file .env up -d --build

jenkins-down: ## Stop Jenkins
	cd infra/jenkins && docker compose -f docker-compose.jenkins.yml --env-file .env down

jenkins-logs: ## Tail Jenkins logs
	cd infra/jenkins && docker compose -f docker-compose.jenkins.yml --env-file .env logs -f

# ---- Kubernetes ----

k8s-apply: ## Deploy the Kubernetes manifests
	kubectl apply -k infra/k8s

k8s-delete: ## Delete the Kubernetes manifests
	kubectl delete -k infra/k8s
