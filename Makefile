.PHONY: install dev backend frontend tunnel lint typecheck

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
	@echo "Tunnel command placeholder - configure ngrok/cloudflare as needed"

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