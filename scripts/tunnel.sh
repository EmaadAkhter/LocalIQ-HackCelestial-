#!/usr/bin/env bash
set -euo pipefail

# Publish LocalIQ on tavesglobal.com through the named Cloudflare Tunnel.
#
# Usage:
#   scripts/tunnel.sh
#
# Requires a one-time setup first (see scripts/tunnel-setup.sh):
#   cloudflared tunnel create localiq
#   cloudflared tunnel route dns localiq localiq.tavesglobal.com
#   cloudflared tunnel route dns localiq jenkins.tavesglobal.com
#
# A single tunnel serves all surfaces:
#   https://localiq.tavesglobal.com/         -> Flutter web (Caddy -> nginx)
#   https://localiq.tavesglobal.com/api/v1/* -> FastAPI (Caddy -> Kong)
#   https://localiq.tavesglobal.com/llm/*    -> shared Ollama (Kong key-auth)
#   https://jenkins.tavesglobal.com/         -> self-hosted Jenkins CI

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CF="${CLOUDFLARED:-$HOME/.local/bin/cloudflared}"
CFG="$ROOT/infra/cloudflared/config.yml"

if ! command -v "$CF" >/dev/null 2>&1; then
  echo "cloudflared not found at $CF." >&2
  echo "Install it first:  brew install cloudflared" >&2
  exit 1
fi

if ! command -v "$CF" >/dev/null 2>&1; then
  echo "cloudflared not found. Install it first:" >&2
  echo "  brew install cloudflared" >&2
  exit 1
fi

if [ ! -f "$CFG" ]; then
  echo "Missing tunnel config: $CFG" >&2
  echo "Run scripts/tunnel-setup.sh first." >&2
  exit 1
fi

CREDS="$("$CF" tunnel --config "$CFG" ingress validate >/dev/null 2>&1 && grep -E '^credentials-file:' "$CFG" | awk '{print $2}')"
if [ -n "${CREDS:-}" ] && [ ! -f "$CREDS" ]; then
  echo "Credentials file missing: $CREDS" >&2
  echo "Run scripts/tunnel-setup.sh to recreate it." >&2
  exit 1
fi

if ! "$CF" tunnel info localiq >/dev/null 2>&1; then
  echo "Tunnel 'localiq' does not exist. Run scripts/tunnel-setup.sh first." >&2
  exit 1
fi

echo "Starting Cloudflare Tunnel -> https://localiq.tavesglobal.com"
echo "  App/API : https://localiq.tavesglobal.com"
echo "  Jenkins : https://jenkins.tavesglobal.com"
echo "  Shared model for teammates:"
echo "        export OLLAMA_URL=https://localiq.tavesglobal.com/llm"
echo "        export OLLAMA_API_KEY=localiq-shared-key"
echo

exec "$CF" tunnel --no-autoupdate --config "$CFG" run
