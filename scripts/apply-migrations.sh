#!/usr/bin/env bash
# ==============================================================================
# scripts/apply-migrations.sh — push supabase/migrations/*.sql to a project.
# ==============================================================================
# Wraps `supabase link` + `supabase db push`. The whole reason this is a
# script and not "just run supabase db push" is the guard below: `db push`
# against the wrong --project-ref is a one-line typo away from mutating a
# real user's production database, and the Supabase CLI itself does not ask
# "are you sure" before doing that. This script does.
# ==============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# shellcheck source=./lib.sh
source "$SCRIPT_DIR/lib.sh"

usage() {
  cat <<'EOF'
Usage: apply-migrations.sh --project-ref <ref> [--dry-run] [--yes] [--help]

Links this repo to a hosted Supabase project and pushes every migration in
supabase/migrations/ that isn't already recorded as applied there
(`supabase db push`; see supabase/README.md for how that's tracked).

Required:
  --project-ref <ref>   Target Supabase project ref (20-char id from the
                         dashboard URL).

Optional:
  --dry-run              Run `supabase db diff --linked` (shows what WOULD
                          change) instead of `supabase db push`. Always safe;
                          never mutates the remote database. Skips the
                          production confirmation prompt below, since
                          nothing destructive happens.
  --yes                  Skip the interactive "type the project ref again to
                          confirm" prompt. Intended for CI, where a human
                          already reviewed this exact command in a PR/deploy
                          pipeline — NOT a substitute for that review. Using
                          --yes locally to avoid typing a prompt defeats the
                          entire point of this script; don't.
  --help                 Show this message and exit 0.

PRODUCTION GUARD
-----------------
Unless --dry-run or --yes is given, this script requires you to re-type the
project ref at an interactive prompt before it pushes anything. There is no
way for this script to know which ref is "production" and which is a scratch
project — the guard is therefore unconditional: every real push requires a
human to deliberately type the ref a second time and look at what they typed.
A copy-pasted `--project-ref` from the wrong terminal tab does not survive
that; a genuine intent to push does.

Requires:
  - The Supabase CLI (`supabase`) installed and on PATH.
  - `supabase login` already run (or SUPABASE_ACCESS_TOKEN exported) — this
    script never prompts for or reads a token itself, and never echoes one.

Examples:
  scripts/apply-migrations.sh --project-ref abcdefghijklmnopqrst --dry-run
  scripts/apply-migrations.sh --project-ref abcdefghijklmnopqrst
EOF
}

project_ref=""
dry_run=0
skip_confirm=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --project-ref)
      [[ $# -ge 2 ]] || astra_die "--project-ref requires a value."
      project_ref="$2"
      shift 2
      ;;
    --dry-run)
      dry_run=1
      shift
      ;;
    --yes)
      skip_confirm=1
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

[[ -n "$project_ref" ]] || { usage >&2; astra_die "--project-ref is required."; }
astra_require_project_ref "$project_ref" "--project-ref"
astra_require_cmd supabase "Install: https://supabase.com/docs/guides/cli"

migrations_dir="$REPO_ROOT/supabase/migrations"
[[ -d "$migrations_dir" ]] || astra_die "Migrations directory not found: $migrations_dir"
migration_count=$(find "$migrations_dir" -maxdepth 1 -name '*.sql' | wc -l | tr -d ' ')
[[ "$migration_count" -gt 0 ]] || astra_die "No .sql files found in $migrations_dir — nothing to push."

astra_log "Project ref: $(astra_mask "$project_ref")"
astra_log "Found $migration_count migration file(s) in supabase/migrations/."

cd "$REPO_ROOT"

# The confirmation gate runs BEFORE any network call (including `supabase
# link`, which is non-destructive but does contact the remote API) — so a
# mistyped/wrong-tab --project-ref is caught before this script talks to
# that project at all, not just before the push.
if [[ $dry_run -eq 0 && $skip_confirm -eq 0 ]]; then
  if [[ ! -t 0 ]]; then
    astra_die "Not running in an interactive terminal and --yes was not passed. Refusing to push migrations without confirmation. Pass --yes only from a pipeline where this exact command was already reviewed by a human."
  fi
  echo
  echo "About to link to and run 'supabase db push' against project ref: $project_ref"
  echo "This applies every not-yet-applied migration in supabase/migrations/ to that project's REAL database."
  read -r -p "Type the project ref again to confirm, or anything else to abort: " confirm_ref
  if [[ "$confirm_ref" != "$project_ref" ]]; then
    astra_die "Confirmation did not match project ref. Aborted — nothing was pushed."
  fi
fi

astra_log "Linking to project..."
supabase link --project-ref "$project_ref" \
  || astra_die "supabase link failed. Check the project ref and that 'supabase login' (or SUPABASE_ACCESS_TOKEN) is set up."

if [[ $dry_run -eq 1 ]]; then
  astra_log "Dry run: showing pending schema diff only (supabase db diff --linked). Nothing will be pushed."
  supabase db diff --linked
  exit 0
fi

astra_log "Pushing migrations..."
supabase db push \
  || astra_die "supabase db push failed. See CLI output above. Do not re-run blindly — read the error first; a partially-applied migration set needs a forward-fixing migration, not a retry."

astra_log "Migrations pushed. Run scripts/verify-deployment.sh to confirm they actually applied and RLS is enabled."
