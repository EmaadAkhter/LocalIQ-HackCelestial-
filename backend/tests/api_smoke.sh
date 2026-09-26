#!/usr/bin/env bash
set -euo pipefail

# Container-internal API smoke test.
# Runs inside the backend image (no bind mounts, no curl), starts the server on
# localhost, and verifies health + parsing. Used by CI.

uvicorn main:app --host 127.0.0.1 --port 8000 >/tmp/api.log 2>&1 &
API_PID=$!
trap 'kill "${API_PID}" 2>/dev/null || true' EXIT

python - <<'PY'
import json
import sys
import time
import urllib.request


def call(url: str, method: str = "GET", body: dict | None = None):
    data = json.dumps(body).encode() if body is not None else None
    request = urllib.request.Request(
        url, data=data, method=method, headers={"Content-Type": "application/json"}
    )
    with urllib.request.urlopen(request, timeout=10) as response:
        return response.status, response.read().decode()


deadline = time.time() + 30
while time.time() < deadline:
    try:
        status, body = call("http://127.0.0.1:8000/health")
        if status == 200 and "ok" in body:
            break
    except Exception:
        time.sleep(1)
else:
    sys.exit("health endpoint never became ready")

status, body = call(
    "http://127.0.0.1:8000/api/v1/parse", "POST", {"text": "food for 2 hours under 500"}
)
if "constraints" not in body:
    sys.exit(f"parse did not return constraints: {body[:200]}")

print("API SMOKE OK")
PY
