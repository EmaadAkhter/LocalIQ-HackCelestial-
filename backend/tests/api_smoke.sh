#!/usr/bin/env bash
set -euo pipefail

# Container-internal API smoke test.
# Runs inside the backend image (no bind mounts), starts the server on
# localhost, and verifies health + parsing. Used by CI.

uvicorn main:app --host 127.0.0.1 --port 8000 >/tmp/api.log 2>&1 &
API_PID=$!
trap 'kill "${API_PID}" 2>/dev/null || true' EXIT

for _ in $(seq 1 25); do
  if curl -fsS http://127.0.0.1:8000/health >/dev/null 2>&1; then
    break
  fi
  sleep 1
done

curl -fsS http://127.0.0.1:8000/health | grep -q "ok"

curl -fsS -X POST http://127.0.0.1:8000/api/v1/parse \
  -H 'Content-Type: application/json' \
  -d '{"text":"food for 2 hours under 500"}' | grep -q "constraints"

echo "API SMOKE OK"
