#!/usr/bin/env bash
set -euo pipefail

# Dump the LocalIQ Postgres database to a timestamped .sql file.
#
# Usage:
#   scripts/db-backup.sh [output.sql]
#
# Requires the Postgres container to be running (docker compose in infra/).

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT/infra"

if [ -f .env ]; then
  set -a
  # shellcheck disable=SC1091
  . ./.env
  set +a
fi

PGUSER="${POSTGRES_USER:-localiq}"
PGDB="${POSTGRES_DB:-localiq}"
OUT="${1:-$ROOT/backups/localiq-$(date +%Y%m%d-%H%M%S).sql}"

mkdir -p "$(dirname "$OUT")"
docker compose exec -T postgres pg_dump -U "$PGUSER" -d "$PGDB" > "$OUT"
echo "Backed up $PGDB to $OUT ($(wc -c < "$OUT" | tr -d ' ') bytes)"
