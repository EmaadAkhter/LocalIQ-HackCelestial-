#!/usr/bin/env bash
set -euo pipefail

# Restore a LocalIQ Postgres dump produced by scripts/db-backup.sh.
#
# Usage:
#   scripts/db-restore.sh backups/localiq-YYYYmmdd-HHMMSS.sql
#
# WARNING: this overwrites data in the target database.

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT/infra"

IN="${1:?usage: scripts/db-restore.sh <backup.sql>}"
[ -f "$IN" ] || { echo "No such file: $IN" >&2; exit 1; }

if [ -f .env ]; then
  set -a
  # shellcheck disable=SC1091
  . ./.env
  set +a
fi

PGUSER="${POSTGRES_USER:-localiq}"
PGDB="${POSTGRES_DB:-localiq}"

docker compose exec -T postgres psql -U "$PGUSER" -d "$PGDB" < "$IN"
echo "Restored $PGDB from $IN"
