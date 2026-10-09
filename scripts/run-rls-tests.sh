#!/usr/bin/env bash
# ==============================================================================
# scripts/run-rls-tests.sh — run supabase/tests/*.sql against a real Postgres.
# ==============================================================================
# Applies, in order, against a fresh scratch database:
#   1. supabase/tests/00_test_only_auth_storage_shim.sql (auth/storage stand-in)
#   2. every supabase/migrations/*.sql file, in filename order
#   3. supabase/tests/10_test_only_grants.sql (anon/authenticated table grants)
#   4. supabase/tests/20_rls_isolation_tests.sql (the actual assertions)
#
# This is real SQL run against a real Postgres instance — not a mock, not a
# dry-run parse. See supabase/tests/20_rls_isolation_tests.sql's header for
# why the suite is plain SQL (`raise exception` on failure) rather than
# pgTAP, and what each table's assertions prove.
#
# Exit code is the exit code of step 4 (0 = every RLS assertion passed).
# Steps 1-3 use `ON_ERROR_STOP=1`, so a failure there aborts the whole run
# with a non-zero exit before step 4 is even attempted.
# ==============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
TESTS_DIR="$REPO_ROOT/supabase/tests"
MIGRATIONS_DIR="$REPO_ROOT/supabase/migrations"

# shellcheck source=./lib.sh
source "$SCRIPT_DIR/lib.sh"

usage() {
  cat <<'EOF'
Usage: run-rls-tests.sh [--db-name <name>] [--keep-db] [--help]

Applies supabase/migrations/*.sql plus the test-only shim/grants in
supabase/tests/ to a fresh scratch database, then runs
supabase/tests/20_rls_isolation_tests.sql — a plain-SQL suite that asserts,
per user-owned table, that Row Level Security actually isolates users (see
that file's header comment for the full list of what each table asserts).

Connects to an ALREADY-RUNNING Postgres server using standard libpq
environment variables (PGHOST, PGPORT, PGUSER, PGPASSWORD, PGDATABASE) or a
matching ~/.pgpass / service file — this script does not start or manage a
Postgres server itself. In CI (.github/workflows/rls-tests.yml) that server
is a `pgvector/pgvector:pg16` service container; locally it can be any
Postgres 16 instance with the vector/pgcrypto/pg_trgm/unaccent extensions
installable (`apt-get install postgresql-16 postgresql-16-pgvector`
provides all of them on Debian/Ubuntu).

Optional:
  --db-name <name>   Scratch database name to create/drop. Default:
                      astra_rls_test. Must not be a database you care about —
                      it is unconditionally DROPPED (if present) before
                      creation and, unless --keep-db is given, after the run.
  --keep-db           Do not drop the scratch database after the run (either
                      outcome). Useful for `psql <db-name>` post-mortem
                      debugging of a failure.
  --help               Show this message and exit 0.

Requires:
  - psql on PATH, able to connect with CREATEDB privilege (e.g. the
    `postgres` superuser role).

Examples:
  # Against a local Postgres started with default trust/peer auth:
  PGHOST=localhost PGUSER=postgres scripts/run-rls-tests.sh

  # Keep the scratch database around after a failing run to inspect it:
  PGHOST=localhost PGUSER=postgres scripts/run-rls-tests.sh --keep-db
  psql -h localhost -U postgres astra_rls_test -c "select * from pg_tables where schemaname='public';"
EOF
}

db_name="astra_rls_test"
keep_db=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --db-name)
      [[ $# -ge 2 ]] || astra_die "--db-name requires a value."
      db_name="$2"
      shift 2
      ;;
    --keep-db)
      keep_db=1
      shift
      ;;
    --help|-h)
      usage
      exit 0
      ;;
    *)
      astra_die "Unknown argument: '$1'. Run with --help for usage."
      ;;
  esac
done

astra_require_cmd psql "Install the PostgreSQL client (e.g. apt-get install postgresql-client)."
[[ -d "$TESTS_DIR" ]] || astra_die "Test directory not found: $TESTS_DIR"
[[ -d "$MIGRATIONS_DIR" ]] || astra_die "Migrations directory not found: $MIGRATIONS_DIR"

shim_file="$TESTS_DIR/00_test_only_auth_storage_shim.sql"
grants_file="$TESTS_DIR/10_test_only_grants.sql"
assertions_file="$TESTS_DIR/20_rls_isolation_tests.sql"
[[ -f "$shim_file" ]] || astra_die "Missing $shim_file"
[[ -f "$grants_file" ]] || astra_die "Missing $grants_file"
[[ -f "$assertions_file" ]] || astra_die "Missing $assertions_file"

# psql against the `postgres` maintenance database, to create/drop the
# scratch database itself (you cannot DROP/CREATE the database you are
# currently connected to).
admin_psql() {
  psql -X -q -v ON_ERROR_STOP=1 -d postgres "$@"
}

# psql against the scratch database, for everything else.
test_psql() {
  psql -X -v ON_ERROR_STOP=1 -d "$db_name" "$@"
}

cleanup() {
  if [[ $keep_db -eq 1 ]]; then
    astra_log "--keep-db given: leaving '$db_name' in place for inspection."
    return
  fi
  astra_log "Dropping scratch database '$db_name'..."
  admin_psql -c "drop database if exists \"$db_name\";" >/dev/null 2>&1 || \
    astra_log "WARNING: failed to drop '$db_name' during cleanup. Drop it manually: dropdb $db_name"
}
trap cleanup EXIT

astra_log "Target: $(astra_mask "${PGUSER:-$(whoami)}")@${PGHOST:-localhost}:${PGPORT:-5432}, scratch db '$db_name'"

astra_log "Creating scratch database '$db_name' (dropping first if it already exists)..."
admin_psql -c "drop database if exists \"$db_name\";"
admin_psql -c "create database \"$db_name\";"

astra_log "Applying test-only auth/storage shim..."
test_psql -f "$shim_file"

migration_count=0
while IFS= read -r -d '' migration_file; do
  astra_log "Applying migration: $(basename "$migration_file")"
  test_psql -f "$migration_file"
  migration_count=$((migration_count + 1))
done < <(find "$MIGRATIONS_DIR" -maxdepth 1 -name '*.sql' -print0 | sort -z)
[[ "$migration_count" -gt 0 ]] || astra_die "No .sql files found in $MIGRATIONS_DIR — nothing was applied."
astra_log "Applied $migration_count migration(s)."

astra_log "Applying test-only grants..."
test_psql -f "$grants_file"

astra_log "Running RLS isolation assertions..."
echo
set +e
test_psql -f "$assertions_file"
test_exit=$?
if [[ $test_exit -eq 0 ]]; then
  test_psql -f "$TESTS_DIR/30_studio_job_safety.sql"
  test_exit=$?
fi
if [[ $test_exit -eq 0 ]]; then
  test_psql -f "$TESTS_DIR/31_studio_lookbooks.sql"
  test_exit=$?
fi
if [[ $test_exit -eq 0 ]]; then
  test_psql -f "$TESTS_DIR/32_studio_retention.sql"
  test_exit=$?
fi
if [[ $test_exit -eq 0 ]]; then
  test_psql -f "$TESTS_DIR/33_studio_deletion.sql"
  test_exit=$?
fi
if [[ $test_exit -eq 0 ]]; then
  test_psql -f "$TESTS_DIR/34_reference_photo_cleanup.sql"
  test_exit=$?
fi
if [[ $test_exit -eq 0 ]]; then
  test_psql -f "$TESTS_DIR/35_guest_photo_storage.sql"
  test_exit=$?
fi
if [[ $test_exit -eq 0 ]]; then
  test_psql -f "$TESTS_DIR/36_studio_image_descriptions.sql"
  test_exit=$?
fi
if [[ $test_exit -eq 0 ]]; then
  test_psql -f "$TESTS_DIR/37_studio_submission_idempotency.sql"
  test_exit=$?
fi
if [[ $test_exit -eq 0 ]]; then
  test_psql -f "$TESTS_DIR/38_kyra_studio_confirmations.sql"
  test_exit=$?
fi
if [[ $test_exit -eq 0 ]]; then
  test_psql -f "$TESTS_DIR/39_studio_premium_quota.sql"
  test_exit=$?
fi
if [[ $test_exit -eq 0 ]]; then
  test_psql -f "$TESTS_DIR/40_kyra_preview_approval_ordering.sql"
  test_exit=$?
fi
if [[ $test_exit -eq 0 ]]; then
  test_psql -f "$TESTS_DIR/41_reference_photo_association.sql"
  test_exit=$?
fi
if [[ $test_exit -eq 0 ]]; then
  test_psql -f "$TESTS_DIR/42_closet_cutout_reservations.sql"
  test_exit=$?
fi
if [[ $test_exit -eq 0 ]]; then
  test_psql -f "$TESTS_DIR/43_kyra_studio_inspiration_history.sql"
  test_exit=$?
fi
if [[ $test_exit -eq 0 ]]; then
  test_psql -f "$TESTS_DIR/44_studio_hi_res_exports.sql"
  test_exit=$?
fi
if [[ $test_exit -eq 0 ]]; then
  test_psql -f "$TESTS_DIR/45_compatibility_weights.sql"
  test_exit=$?
fi
if [[ $test_exit -eq 0 ]]; then
  test_psql -f "$TESTS_DIR/46_outfit_unlock_count_cache.sql"
  test_exit=$?
fi
if [[ $test_exit -eq 0 ]]; then
  test_psql -f "$TESTS_DIR/47_studio_orphan_result_cleanup.sql"
  test_exit=$?
fi
if [[ $test_exit -eq 0 ]]; then
  test_psql -f "$TESTS_DIR/48_studio_semantic_generation_cache.sql"
  test_exit=$?
fi
if [[ $test_exit -eq 0 ]]; then
  test_psql -f "$TESTS_DIR/49_studio_reference_short_retention.sql"
  test_exit=$?
fi
if [[ $test_exit -eq 0 ]]; then
  test_psql -f "$TESTS_DIR/50_studio_semantic_generation_concurrency.sql"
  test_exit=$?
fi
if [[ $test_exit -eq 0 ]]; then
  test_psql -f "$TESTS_DIR/51_closet_image_thumbnail_variants.sql"
  test_exit=$?
fi
if [[ $test_exit -eq 0 ]]; then
  test_psql -f "$TESTS_DIR/52_style_preference_quiz_answers.sql"
  test_exit=$?
fi
if [[ $test_exit -eq 0 ]]; then
  test_psql -f "$TESTS_DIR/53_closet_care_instructions.sql"
  test_exit=$?
fi
if [[ $test_exit -eq 0 ]]; then
  test_psql -f "$TESTS_DIR/54_outfit_edit_rpc.sql"
  test_exit=$?
fi
if [[ $test_exit -eq 0 ]]; then
  test_psql -f "$TESTS_DIR/55_outfit_generation_quota.sql"
  test_exit=$?
fi
if [[ $test_exit -eq 0 ]]; then
  test_psql -f "$TESTS_DIR/56_kyra_atomic_outfit_generation.sql"
  test_exit=$?
fi
if [[ $test_exit -eq 0 ]]; then
  test_psql -f "$TESTS_DIR/57_morning_loop_trial_admission.sql"
  test_exit=$?
fi
if [[ $test_exit -eq 0 ]]; then
  test_psql -f "$TESTS_DIR/58_closet_batch_job_idempotency.sql"
  test_exit=$?
fi
set -e
echo

if [[ $test_exit -eq 0 ]]; then
  astra_log "VERDICT: all RLS assertions passed."
else
  astra_log "VERDICT: at least one RLS assertion FAILED (see 'FAIL' rows / RLS FAIL warnings above). Exit code: $test_exit"
fi

exit "$test_exit"
