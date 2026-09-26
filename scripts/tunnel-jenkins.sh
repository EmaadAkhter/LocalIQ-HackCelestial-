#!/usr/bin/env bash
set -euo pipefail

# Expose Jenkins through a Cloudflare quick tunnel.
#
# WARNING: Jenkins has a large attack surface. Exposing it to the public
# internet is risky. Prefer an SSH tunnel:
#     ssh -L 8081:localhost:8081 user@host
#
# If you proceed, use a strong admin password (infra/jenkins/.env) and consider
# a named tunnel with Cloudflare Access policies.

TARGET="${1:-http://localhost:8081}"

cat >&2 <<'EOF'
WARNING
  You are about to expose Jenkins publicly.
  - Use a strong JENKINS_ADMIN_PASSWORD.
  - Do not leave it running longer than you need.
  - Prefer SSH port-forwarding for day-to-day access.
EOF

if ! command -v cloudflared >/dev/null 2>&1; then
  echo "cloudflared not found. Install it first: brew install cloudflared" >&2
  exit 1
fi

exec cloudflared tunnel --no-autoupdate --url "${TARGET}"
