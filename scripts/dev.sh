#!/usr/bin/env bash
# First run, in order, stopping at the first failure.
#   ./scripts/dev.sh
# Used by nobody in CI: it exists so a stranger can start the whole stack with one command.
set -euo pipefail
cd "$(dirname "$0")/.."

export DATABASE_URL="${DATABASE_URL:-postgresql://brandguard:brandguard@localhost:5432/brandguard}"

echo "==> starting postgres"
docker compose up -d
printf "    waiting"
for _ in $(seq 1 60); do
  if docker compose exec -T db pg_isready -U brandguard -d brandguard >/dev/null 2>&1; then
    echo " ready"; break
  fi
  printf "."; sleep 1
done

echo "==> applying schema, functions, seed"
for f in database/001_schema.sql database/002_functions.sql database/003_seed.sql; do
  psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -q -f "$f"
  echo "    $f"
done

echo "==> assertions"
psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -q -f database/tests/001_assertions.sql

echo
echo "Database is ready. Now, in two terminals:"
echo "    make api"
echo "    make app-web        # or: make app"
echo "Then: python scripts/smoke.py"
