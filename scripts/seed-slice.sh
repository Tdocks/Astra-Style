#!/usr/bin/env bash
# ==============================================================================
# scripts/seed-slice.sh — apply supabase/seed/slice_seed.sql for one user.
# ==============================================================================
# Runs the vertical-slice 25-item wardrobe seed (supabase/seed/slice_seed.sql)
# against a database, with the target user id passed safely as a psql
# variable (never string-concatenated into SQL text).
# ==============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
SEED_FILE="$REPO_ROOT/supabase/seed/slice_seed.sql"

# shellcheck source=./lib.sh
source "$SCRIPT_DIR/lib.sh"

usage() {
  cat <<'EOF'
Usage: seed-slice.sh --user-id <uuid> [--db-url <url> | --local] [--help]

Seeds the believable 25-item men's wardrobe fixture
(supabase/seed/slice_seed.sql) for one user. Safe to re-run — the seed file
upserts on a deterministic id per (user, item name), so this never
duplicates the wardrobe.

Required:
  --user-id <uuid>      The auth.users id to seed a wardrobe for. Find yours:
                           - Supabase Studio -> Authentication -> Users, or
                           - `select id, email from auth.users;` run against
                             the project (Studio SQL Editor, or psql), or
                           - if you signed in once through the vertical
                             slice's Sign in with Apple flow, that created
                             the auth.users row this script needs to exist.

Exactly one of:
  --db-url <url>         A full Postgres connection string, e.g.
                          "postgresql://postgres:<password>@db.<ref>.supabase.co:5432/postgres"
                          (hosted: dashboard -> Project Settings -> Database
                          -> Connection string). Also read from the
                          SUPABASE_DB_URL environment variable if --db-url is
                          omitted — prefer the env var over a shell history
                          entry containing a password.
  --local                 Use the Supabase CLI's local stack default
                          (postgresql://postgres:postgres@localhost:54322/postgres),
                          i.e. whatever `supabase start` is currently running.

Optional:
  --help                  Show this message and exit 0.

This script never prints the connection string (it may contain a password) —
only whether one was found and (redacted) which host it points at.

Examples:
  scripts/seed-slice.sh --user-id 3fa85f64-5717-4562-b3fc-2c963f66afa6 --local
  SUPABASE_DB_URL=postgresql://... scripts/seed-slice.sh --user-id 3fa85f64-5717-4562-b3fc-2c963f66afa6
EOF
}

user_id=""
db_url="${SUPABASE_DB_URL:-}"
use_local=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --user-id)
      [[ $# -ge 2 ]] || astra_die "--user-id requires a value."
      user_id="$2"
      shift 2
      ;;
    --db-url)
      [[ $# -ge 2 ]] || astra_die "--db-url requires a value."
      db_url="$2"
      shift 2
      ;;
    --local)
      use_local=1
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

[[ -n "$user_id" ]] || { usage >&2; astra_die "--user-id is required."; }
astra_require_uuid "$user_id" "--user-id"
astra_require_cmd psql "Install the PostgreSQL client (e.g. 'apt-get install postgresql-client' or 'brew install libpq')."
[[ -f "$SEED_FILE" ]] || astra_die "Seed file not found: $SEED_FILE"

if [[ $use_local -eq 1 && -n "$db_url" ]]; then
  astra_die "--local and --db-url are mutually exclusive. Pick one."
fi
if [[ $use_local -eq 1 ]]; then
  db_url="postgresql://postgres:postgres@localhost:54322/postgres"
fi
if [[ -z "$db_url" ]]; then
  astra_die "No database target given. Pass --db-url, set SUPABASE_DB_URL, or pass --local for the Supabase CLI's local stack. Run with --help for details."
fi

# Redact: log only the host, never the full URL (which may embed a password).
db_host="$(printf '%s' "$db_url" | sed -E 's#^[a-zA-Z0-9+]+://[^@]*@?##; s#/.*##')"
astra_log "Seeding user $(astra_mask "$user_id") against database host: ${db_host:-<unparseable>}"

psql "$db_url" \
  -v ON_ERROR_STOP=1 \
  -v seed_user_id="$user_id" \
  -f "$SEED_FILE" \
  || astra_die "Seeding failed. Common causes: the user id doesn't exist in auth.users yet (sign in once first), or migrations haven't been applied to this database yet (run scripts/apply-migrations.sh)."

astra_log "Seed complete. 25 closet_items rows upserted."
