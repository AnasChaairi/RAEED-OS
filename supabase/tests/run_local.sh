#!/usr/bin/env bash
# Runs the migrations and access-rule tests on a throwaway local Postgres database.
# Usage: PGHOST=/tmp PGPORT=5432 PGUSER=postgres supabase/tests/run_local.sh
set -euo pipefail
cd "$(dirname "$0")/.."
db=raeed_test_$$
createdb "$db"
trap 'dropdb "$db"' EXIT
psql -q -v ON_ERROR_STOP=1 -d "$db" -f tests/local_bootstrap.sql
for f in migrations/*.sql; do psql -q -v ON_ERROR_STOP=1 -d "$db" -f "$f"; done
psql -v ON_ERROR_STOP=1 -d "$db" -f tests/access_rules_test.sql
