#!/usr/bin/env bash
set -euo pipefail

# End-to-end smoke test: bring up the Docker stack on an isolated project/port
# and verify the edge -> Kong -> backend chain, then tear it down.

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
COMPOSE_DIR="${ROOT}/infra"
PORT="${SMOKE_HTTP_PORT:-18080}"
PROJECT="${SMOKE_PROJECT:-localiq-smoke}"

cd "${COMPOSE_DIR}"
[ -f .env ] || cp .env.example .env

cleanup() {
  HTTP_PORT="${PORT}" docker compose -p "${PROJECT}" --env-file .env down -v >/dev/null 2>&1 || true
}
trap cleanup EXIT

echo "Starting stack (project=${PROJECT}, port=${PORT})..."
HTTP_PORT="${PORT}" docker compose -p "${PROJECT}" --env-file .env up -d --build

echo "Waiting for edge..."
for _ in $(seq 1 45); do
  if curl -fsS "http://localhost:${PORT}/healthz" >/dev/null 2>&1; then
    break
  fi
  sleep 2
done
curl -fsS "http://localhost:${PORT}/healthz" | grep -q "ok"

echo "Waiting for the API through the gateway..."
api_ready=""
for _ in $(seq 1 45); do
  if curl -fsS "http://localhost:${PORT}/api/v1/experiences" >/dev/null 2>&1; then
    api_ready="yes"
    break
  fi
  sleep 2
done
if [ -z "${api_ready}" ]; then
  echo "API did not become reachable through the gateway" >&2
  docker compose -p "${PROJECT}" --env-file .env logs --tail=50 >&2 || true
  exit 1
fi

echo "Checking /api/v1/parse through Caddy -> Kong -> backend..."
curl -fsS "http://localhost:${PORT}/api/v1/parse" \
  -H 'Content-Type: application/json' \
  -d '{"text":"find local food for 2 hours under 500"}' | grep -q "constraints"

echo "SMOKE OK"
