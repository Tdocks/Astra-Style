#!/usr/bin/env bash
# ==============================================================================
# scripts/deploy-functions.sh — deploy Edge Functions to a Supabase project.
# ==============================================================================
# Thin, validated wrapper around `supabase functions deploy`. Exists so
# "deploy the slice's Edge Function" is one documented command instead of a
# tribal-knowledge `supabase` invocation someone has to reconstruct from
# supabase/functions/README.md each time.
#
# What this does NOT do: set secrets (`supabase secrets set ...`), run
# migrations, or verify the deploy worked. See apply-migrations.sh and
# verify-deployment.sh for those — deliberately separate scripts/steps so a
# failure in one is unambiguous about what did and didn't happen.
# ==============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
FUNCTIONS_DIR="$REPO_ROOT/supabase/functions"

# shellcheck source=./lib.sh
source "$SCRIPT_DIR/lib.sh"

usage() {
  cat <<'EOF'
Usage: deploy-functions.sh --project-ref <ref> [--function <name>] [--no-verify-jwt] [--dry-run] [--help]

Deploys one or all Supabase Edge Functions under supabase/functions/ to a
hosted project.

Required:
  --project-ref <ref>   Target Supabase project ref (20-char id from the
                         dashboard URL, e.g. https://supabase.com/dashboard/project/<ref>).

Optional:
  --function <name>     Deploy only this one function (directory name under
                         supabase/functions/, e.g. "outfits").
                         Default: deploy every function directory found
                         (every subdirectory of supabase/functions/ except
                         "_shared", which is a library, not a function).
  --no-verify-jwt        Pass --no-verify-jwt through to the Supabase CLI.
                         Do NOT use this for outfits or any other
                         function that authenticates via _shared/jwt.ts --
                         this flag disables the *platform-level* JWT check,
                         which these functions rely on defense-in-depth
                         alongside their own authenticateRequest() call. Only
                         exists for a genuinely public/no-auth function,
                         which nothing in this repo currently is.
  --dry-run              Print the exact `supabase` command(s) that would run
                         and exit 0 without deploying anything.
  --help                 Show this message and exit 0.

Requires:
  - The Supabase CLI (`supabase`) installed and on PATH.
  - `supabase login` already run (or SUPABASE_ACCESS_TOKEN exported) —
    this script never prompts for or reads a token itself, and never
    echoes one.

Examples:
  scripts/deploy-functions.sh --project-ref abcdefghijklmnopqrst
  scripts/deploy-functions.sh --project-ref abcdefghijklmnopqrst --function outfits
EOF
}

project_ref=""
only_function=""
extra_flags=()
dry_run=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --project-ref)
      [[ $# -ge 2 ]] || astra_die "--project-ref requires a value."
      project_ref="$2"
      shift 2
      ;;
    --function)
      [[ $# -ge 2 ]] || astra_die "--function requires a value."
      only_function="$2"
      shift 2
      ;;
    --no-verify-jwt)
      extra_flags+=("--no-verify-jwt")
      shift
      ;;
    --dry-run)
      dry_run=1
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

[[ -d "$FUNCTIONS_DIR" ]] || astra_die "Functions directory not found: $FUNCTIONS_DIR"

# Discover deployable functions: every directory under supabase/functions/
# that has an index.ts, excluding _shared (a library, not a function).
functions_to_deploy=()
if [[ -n "$only_function" ]]; then
  [[ -f "$FUNCTIONS_DIR/$only_function/index.ts" ]] \
    || astra_die "No index.ts found at supabase/functions/$only_function/index.ts."
  functions_to_deploy=("$only_function")
else
  while IFS= read -r -d '' dir; do
    name="$(basename "$dir")"
    [[ "$name" == "_shared" ]] && continue
    [[ -f "$dir/index.ts" ]] || continue
    functions_to_deploy+=("$name")
  done < <(find "$FUNCTIONS_DIR" -mindepth 1 -maxdepth 1 -type d -print0 | sort -z)
fi

[[ ${#functions_to_deploy[@]} -gt 0 ]] || astra_die "No deployable functions found under $FUNCTIONS_DIR."

astra_log "Project ref: $(astra_mask "$project_ref")"
astra_log "Deploying ${#functions_to_deploy[@]} function(s): ${functions_to_deploy[*]}"

for fn in "${functions_to_deploy[@]}"; do
  # `${extra_flags[@]+...}` rather than a bare "${extra_flags[@]}": under
  # `set -u`, bash 3.2 (macOS's /bin/bash, still what `env bash` resolves to
  # on a stock Mac) treats expanding an EMPTY array as an unbound-variable
  # error, so the common no-flags case would abort the deploy before it
  # started. The +-form expands to nothing at all when the array is empty
  # and to the properly-quoted elements when it isn't, on every bash.
  cmd=(supabase functions deploy "$fn" --project-ref "$project_ref" ${extra_flags[@]+"${extra_flags[@]}"})
  if [[ $dry_run -eq 1 ]]; then
    printf 'DRY RUN: %s\n' "${cmd[*]}"
    continue
  fi
  astra_log "Deploying '$fn'..."
  # Run from repo root so the CLI resolves supabase/config.toml and
  # supabase/functions/ relative paths correctly regardless of caller cwd.
  (cd "$REPO_ROOT" && "${cmd[@]}") \
    || astra_die "Deploy failed for function '$fn'. See the supabase CLI output above for the real error — this script does not suppress or reinterpret it."
  astra_log "Deployed '$fn'."
done

if [[ $dry_run -eq 1 ]]; then
  astra_log "Dry run complete — nothing was deployed."
else
  astra_log "All ${#functions_to_deploy[@]} function(s) deployed. Run scripts/verify-deployment.sh next — a successful 'supabase functions deploy' means the code was uploaded, not that it works."
fi
