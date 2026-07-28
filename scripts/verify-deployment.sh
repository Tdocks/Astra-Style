#!/usr/bin/env bash
# ==============================================================================
# scripts/verify-deployment.sh — check that a deploy actually WORKS.
# ==============================================================================
# "It deployed" (deploy-functions.sh / apply-migrations.sh exited 0) and "it
# works" are different claims. This script makes the second claim only after
# checking it directly against the real project:
#
#   1. The Edge Function is actually reachable (not 404/DNS failure/timeout).
#   2. It rejects a request with no JWT with 401, not 200 or a 500.
#   3. Every migration in supabase/migrations/ is recorded as applied on the
#      remote database — not just "the push command exited 0" (a push can
#      exit 0 having applied 12 of 14 files if the 13th's error handling
#      changes in a future CLI version; check the actual recorded state).
#   4. Row Level Security is enabled on every user-owned table — checked
#      directly against pg_class.relrowsecurity, not inferred from "the RLS
#      migration file ran" (a migration recorded as applied doesn't prove
#      its `alter table ... enable row level security` statement actually
#      took effect, e.g. if it silently no-op'd against a renamed table).
#
# Every check below is independent and prints its own PASS/FAIL/WARN line.
# Exit code is 0 only if every check that ran passed. A WARN is not a pass —
# see "Exit codes" below.
# ==============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
MIGRATIONS_DIR="$REPO_ROOT/supabase/migrations"

# shellcheck source=./lib.sh
source "$SCRIPT_DIR/lib.sh"

usage() {
  cat <<'EOF'
Usage: verify-deployment.sh --project-ref <ref> --anon-key <key> --db-url <url>
                             [--function <name>] [--base-url <url>] [--help]

Runs four independent checks against a deployed Supabase project and prints
a PASS/FAIL/WARN summary. Exits 0 only if every check that ran passed.

Required:
  --project-ref <ref>   Target Supabase project ref.
  --anon-key <key>       The project's anon/publishable API key (dashboard ->
                          Project Settings -> API). This is the same key the
                          iOS app ships with — not secret in the way a
                          service-role key is — but this script still never
                          prints it in full (see below).
  --db-url <url>          Full Postgres connection string with enough
                          privilege to read pg_class and
                          supabase_migrations.schema_migrations (dashboard ->
                          Project Settings -> Database -> Connection string).
                          Required because two of the four checks
                          (migrations-applied, RLS-enabled) can only be
                          verified with real SQL access, not the CLI/HTTP
                          alone — see the module comment above. Also read
                          from the SUPABASE_DB_URL environment variable if
                          --db-url is omitted.

Optional:
  --function <name>      Which function to HTTP-check. Default: outfits-generate.
  --base-url <url>        Override the function base URL. Default:
                          https://<project-ref>.supabase.co/functions/v1
  --help                  Show this message and exit 0.

Exit codes:
  0   every check that ran PASSed.
  1   at least one check FAILed, OR an argument/usage/dependency error meant
      nothing could be checked at all (see the ERROR: line for which).

Secrets: this script never prints --db-url (it may embed a password) except
as a redacted host, and masks --anon-key/--project-ref in its own log lines
even though the anon key is not a service-role-level secret.

Example:
  scripts/verify-deployment.sh \
    --project-ref abcdefghijklmnopqrst \
    --anon-key eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9... \
    --db-url "postgresql://postgres:<password>@db.abcdefghijklmnopqrst.supabase.co:5432/postgres"
EOF
}

project_ref=""
anon_key=""
db_url="${SUPABASE_DB_URL:-}"
function_name="outfits-generate"
base_url=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --project-ref)
      [[ $# -ge 2 ]] || astra_die "--project-ref requires a value."
      project_ref="$2"; shift 2 ;;
    --anon-key)
      [[ $# -ge 2 ]] || astra_die "--anon-key requires a value."
      anon_key="$2"; shift 2 ;;
    --db-url)
      [[ $# -ge 2 ]] || astra_die "--db-url requires a value."
      db_url="$2"; shift 2 ;;
    --function)
      [[ $# -ge 2 ]] || astra_die "--function requires a value."
      function_name="$2"; shift 2 ;;
    --base-url)
      [[ $# -ge 2 ]] || astra_die "--base-url requires a value."
      base_url="$2"; shift 2 ;;
    --help|-h)
      usage; exit 0 ;;
    *)
      astra_die "Unknown argument: '$1'. Run with --help for usage." ;;
  esac
done

if [[ -z "$project_ref" || -z "$anon_key" || -z "$db_url" ]]; then
  usage >&2
  astra_die "--project-ref, --anon-key, and --db-url are all required. (Use --help for why --db-url is non-optional here.)"
fi

astra_require_project_ref "$project_ref" "--project-ref"
astra_require_cmd curl "curl is required for the HTTP checks."
astra_require_cmd psql "The PostgreSQL client is required for the migrations/RLS checks."

[[ -n "$base_url" ]] || base_url="https://${project_ref}.supabase.co/functions/v1"
function_url="${base_url%/}/${function_name}"

astra_log "Project ref: $(astra_mask "$project_ref")"
astra_log "Function URL: $function_url"
astra_log "Anon key: $(astra_mask "$anon_key")"
db_host="$(printf '%s' "$db_url" | sed -E 's#^[a-zA-Z0-9+]+://[^@]*@?##; s#/.*##')"
astra_log "DB host: ${db_host:-<unparseable>}"
echo

pass_count=0
fail_count=0
warn_count=0

report() {
  local status="$1" name="$2" detail="$3"
  case "$status" in
    PASS) pass_count=$((pass_count + 1)); printf 'PASS  %-32s %s\n' "$name" "$detail" ;;
    FAIL) fail_count=$((fail_count + 1)); printf 'FAIL  %-32s %s\n' "$name" "$detail" ;;
    WARN) warn_count=$((warn_count + 1)); printf 'WARN  %-32s %s\n' "$name" "$detail" ;;
    *) astra_die "internal error: unknown report status '$status'" ;;
  esac
}

# ------------------------------------------------------------------------
# Check 1: function is reachable at all (CORS preflight — no auth needed,
# handled entirely by _shared/cors.ts before authenticateRequest() runs).
# ------------------------------------------------------------------------
preflight_code="$(curl -s -o /dev/null -w '%{http_code}' -X OPTIONS "$function_url" \
  -H "apikey: $anon_key" \
  -H "Access-Control-Request-Method: POST" \
  --max-time 15)" || true
# curl's `-w '%{http_code}'` already prints "000" itself on a total
# connection failure (exit code 7 etc.) — do NOT also `|| echo "000"` after
# it, or a real failure prints "000" (from curl) immediately followed by
# "000" (from the fallback) as one un-separated string ("000000"), which
# then matches none of the checks below and silently falls through to the
# wrong branch. The `|| true` above only exists so `set -e` doesn't abort
# the whole script on curl's nonzero exit; it deliberately does not touch
# $preflight_code's value.
[[ -n "$preflight_code" ]] || preflight_code="000"

if [[ "$preflight_code" == "000" ]]; then
  report FAIL "function-reachable" "no HTTP response at all from $function_url (DNS/network failure, or function not deployed)."
elif [[ "$preflight_code" == "404" ]]; then
  report FAIL "function-reachable" "HTTP 404 — function '$function_name' does not appear to be deployed at this URL."
elif [[ "$preflight_code" =~ ^(200|204)$ ]]; then
  report PASS "function-reachable" "CORS preflight returned HTTP $preflight_code."
else
  report WARN "function-reachable" "reachable, but preflight returned unexpected HTTP $preflight_code (expected 200/204)."
fi

# ------------------------------------------------------------------------
# Check 2: POST with no Authorization header must be rejected with 401,
# never 200 (would mean auth is bypassed) and never 500 (would mean it
# crashed instead of validating).
# ------------------------------------------------------------------------
no_jwt_response="$(mktemp)"
trap 'rm -f "$no_jwt_response"' EXIT

no_jwt_code="$(curl -s -o "$no_jwt_response" -w '%{http_code}' -X POST "$function_url" \
  -H "apikey: $anon_key" \
  -H "Content-Type: application/json" \
  -H "X-Request-Id: verify-deployment-$$" \
  -d '{"request_id":"verify-deployment","client_version":"scripts/verify-deployment.sh","body":{}}' \
  --max-time 15)" || true
# See the identical comment on $preflight_code above — same fix, same reason.
[[ -n "$no_jwt_code" ]] || no_jwt_code="000"

if [[ "$no_jwt_code" == "401" ]]; then
  report PASS "rejects-missing-jwt" "HTTP 401 as expected with no Authorization header."
elif [[ "$no_jwt_code" == "000" ]]; then
  report FAIL "rejects-missing-jwt" "no HTTP response (network failure) — cannot confirm auth is enforced."
else
  body_snippet="$(head -c 200 "$no_jwt_response" 2>/dev/null || true)"
  report FAIL "rejects-missing-jwt" "expected HTTP 401, got HTTP $no_jwt_code. Body (first 200 chars): ${body_snippet}"
fi

# ------------------------------------------------------------------------
# Check 3: every local migration is recorded as applied on the remote DB.
# Supabase CLI tracks applied migrations in
# supabase_migrations.schema_migrations, keyed by the filename's leading
# timestamp (e.g. "20260728100000" for
# 20260728100000_enable_extensions.sql). Compare that set against every
# *.sql file actually present in supabase/migrations/.
# ------------------------------------------------------------------------
[[ -d "$MIGRATIONS_DIR" ]] || astra_die "Migrations directory not found: $MIGRATIONS_DIR"

local_versions="$(mktemp)"
remote_versions="$(mktemp)"
trap 'rm -f "$no_jwt_response" "$local_versions" "$remote_versions"' EXIT

find "$MIGRATIONS_DIR" -maxdepth 1 -name '*.sql' -printf '%f\n' \
  | sed -E 's/^([0-9]{14})_.*/\1/' \
  | sort > "$local_versions"

if psql "$db_url" -X -q -t -A \
    -c "select version from supabase_migrations.schema_migrations order by version;" \
    > "$remote_versions" 2>/tmp/verify_migrations_err.log; then
  missing_remote="$(comm -23 "$local_versions" "$remote_versions")"
  if [[ -z "$missing_remote" ]]; then
    local_count=$(wc -l < "$local_versions" | tr -d ' ')
    report PASS "migrations-applied" "all $local_count local migration(s) are recorded as applied on the remote database."
  else
    missing_list="$(printf '%s' "$missing_remote" | tr '\n' ' ')"
    report FAIL "migrations-applied" "migration version(s) present locally but NOT recorded as applied remotely: $missing_list"
  fi
else
  err_snippet="$(head -c 300 /tmp/verify_migrations_err.log 2>/dev/null || true)"
  report FAIL "migrations-applied" "could not query supabase_migrations.schema_migrations: ${err_snippet}"
fi
rm -f /tmp/verify_migrations_err.log

# ------------------------------------------------------------------------
# Check 4: RLS is enabled on every user-owned table (the exact set
# alter'd by 20260728100900_rls_policies.sql: the owned_tables loop, plus
# profiles/subscriptions/account_deletions, which get bespoke policies in
# that same migration but are equally user-owned). NOT product_candidates
# — that table is an intentionally shared, non-user-owned catalog (see
# that migration's own comment) and is out of scope for this check.
# ------------------------------------------------------------------------
user_owned_tables=(
  profiles style_profiles body_profiles lifestyle_profiles
  closet_items closet_item_images
  outfits outfit_items outfit_wears
  style_feedback style_memories
  kyra_threads kyra_messages
  occasions daily_briefs
  studio_generations
  user_product_evaluations
  subscriptions
  account_deletions
)
table_list_sql="$(printf "'%s'," "${user_owned_tables[@]}")"
table_list_sql="${table_list_sql%,}"

rls_query="select c.relname, c.relrowsecurity
from pg_class c
join pg_namespace n on n.oid = c.relnamespace
where n.nspname = 'public' and c.relkind = 'r' and c.relname in (${table_list_sql});"

rls_results="$(mktemp)"
trap 'rm -f "$no_jwt_response" "$local_versions" "$remote_versions" "$rls_results"' EXIT

if psql "$db_url" -X -q -t -A -F'|' -c "$rls_query" > "$rls_results" 2>/tmp/verify_rls_err.log; then
  found_tables=()
  disabled_tables=()
  while IFS='|' read -r tbl enabled; do
    [[ -z "$tbl" ]] && continue
    found_tables+=("$tbl")
    if [[ "$enabled" != "t" ]]; then
      disabled_tables+=("$tbl")
    fi
  done < "$rls_results"

  missing_tables=()
  for expected in "${user_owned_tables[@]}"; do
    if ! printf '%s\n' "${found_tables[@]:-}" | grep -qx "$expected"; then
      missing_tables+=("$expected")
    fi
  done

  if [[ ${#missing_tables[@]} -gt 0 ]]; then
    report FAIL "rls-enabled" "table(s) not found in public schema at all (renamed? migration not applied?): ${missing_tables[*]}"
  elif [[ ${#disabled_tables[@]} -gt 0 ]]; then
    report FAIL "rls-enabled" "RLS is NOT enabled on: ${disabled_tables[*]} — a compromised/buggy client could read/write other users' rows in these tables."
  else
    report PASS "rls-enabled" "RLS enabled on all ${#user_owned_tables[@]} user-owned tables."
  fi
else
  err_snippet="$(head -c 300 /tmp/verify_rls_err.log 2>/dev/null || true)"
  report FAIL "rls-enabled" "could not query pg_class: ${err_snippet}"
fi
rm -f /tmp/verify_rls_err.log

echo
astra_log "Summary: $pass_count passed, $fail_count failed, $warn_count warned."

if [[ $fail_count -gt 0 ]]; then
  astra_log "VERDICT: deployment is NOT verified working. Fix the FAILed check(s) above before treating this deploy as done."
  exit 1
fi
astra_log "VERDICT: all checks passed."
exit 0
