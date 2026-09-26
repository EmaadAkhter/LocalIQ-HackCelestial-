.PHONY: help install install-backend install-frontend dev backend frontend-legacy \
	tunnel tunnel-setup lint lint-backend lint-frontend typecheck typecheck-backend typecheck-frontend \
	test test-cov test-backend test-live loadtest infra-up infra-down infra-tunnel infra-logs \
	db-migrate db-revision db-downgrade db-backup db-restore \
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

test-cov: ## Run backend tests with coverage (gate: 80%)
	cd backend && APP_ENV=test python -m pytest -q --cov=app --cov=main --cov-fail-under=80

loadtest: ## Concurrency/latency check against the local edge
	cd backend && python tests/load/loadtest.py --base http://localhost:8080

test-backend: ## Run the backend pytest suite
	cd backend && python -m pytest tests -q

test-live: ## Boot the API in-process and call every endpoint against live Google APIs
	cd backend && python tests/smoke_live.py

# ---- Docker infrastructure ----

infra-up: ## Start the Docker stack (local LLM)
	cd infra && docker compose --env-file .env up -d --build

infra-down: ## Stop the Docker stack
	cd infra && docker compose --env-file .env down

infra-tunnel: ## Publish the running stack via the named Cloudflare tunnel
	./scripts/tunnel.sh

infra-logs: ## Tail Docker stack logs
	cd infra && docker compose --env-file .env logs -f

tunnel: ## Alias for infra-tunnel
	./scripts/tunnel.sh

tunnel-setup: ## One-time Cloudflare tunnel create + DNS routes
	./scripts/tunnel-setup.sh

# ---- Database migrations (Alembic) ----

db-migrate: ## Apply pending DB migrations
	cd backend && alembic upgrade head

db-revision: ## Autogenerate a migration (make db-revision m="message")
	cd backend && alembic revision --autogenerate -m "$(m)"

db-downgrade: ## Roll back one migration
	cd backend && alembic downgrade -1

db-backup: ## Dump Postgres to backups/ (scripts/db-backup.sh)
	./scripts/db-backup.sh

db-restore: ## Restore Postgres (make db-restore f=backups/<file>.sql)
	./scripts/db-restore.sh "$(f)"

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
