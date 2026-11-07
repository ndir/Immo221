#!/usr/bin/env bash
# Teste les migrations sur un Postgres local (base jetable « dekk_test »).
# Usage : PGUSER=postgres ./supabase/tests/run_local.sh
set -euo pipefail
cd "$(dirname "$0")/.."
DB=dekk_test
dropdb --if-exists "$DB"
createdb "$DB"
psql -v ON_ERROR_STOP=1 -q -d "$DB" -f tests/supabase_stub.sql
for f in migrations/*.sql; do
  echo "→ $f"
  psql -v ON_ERROR_STOP=1 -q -d "$DB" -f "$f"
done
psql -v ON_ERROR_STOP=1 -d "$DB" -f tests/scenario.sql
