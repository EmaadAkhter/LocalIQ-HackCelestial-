#!/usr/bin/env bash
set -euo pipefail

# Expose the LocalIQ stack through a Cloudflare quick tunnel.
#
# Usage:
#   scripts/tunnel.sh                       # tunnels the Caddy edge on :8080
#   scripts/tunnel.sh http://localhost:8000 # tunnel a specific target
#
# A single tunnel serves all three surfaces:
#   /            -> Flutter web (via Caddy -> nginx)
#   /api/v1/*    -> FastAPI (via Caddy -> Kong)
#   /llm/*       -> shared local Ollama (via Caddy -> Kong, key-auth)
#
# Share the printed URL with teammates so they can use your model.

TARGET="${1:-http://localhost:8080}"

if ! command -v cloudflared >/dev/null 2>&1; then
  echo "cloudflared not found. Install it first:" >&2
  echo "  brew install cloudflared" >&2
  exit 1
fi

echo "Starting Cloudflare quick tunnel -> ${TARGET}"
echo
echo "Once it prints an https://<something>.trycloudflare.com URL, share these:"
echo "  App:  https://<host>/"
echo "  API:  https://<host>/api/v1/..."
echo "  Shared model for teammates:"
echo "        export OLLAMA_URL=https://<host>/llm"
echo "        export OLLAMA_API_KEY=localiq-shared-key"
echo

exec cloudflared tunnel --no-autoupdate --url "${TARGET}"
