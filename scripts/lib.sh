#!/usr/bin/env bash
# ==============================================================================
# scripts/lib.sh — tiny shared helpers for the astra scripts/*.sh family.
# ==============================================================================
# Sourced (not executed) by the other scripts in this directory:
#   source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"
#
# Deliberately dependency-free (no jq/yq requirement) so these scripts work
# on a bare CI runner or a fresh laptop with only bash + coreutils + curl +
# the tool being wrapped (supabase CLI / psql).
# ==============================================================================

# astra_log <message...>            — informational line to stderr, timestamped.
astra_log() {
  printf '[%s] %s\n' "$(date -u +'%H:%M:%S')" "$*" >&2
}

# astra_die <message...>            — error + exit 1.
astra_die() {
  printf '\nERROR: %s\n' "$*" >&2
  exit 1
}

# astra_require_cmd <cmd> <install-hint>
# Fails with a helpful, actionable message instead of a bare "command not
# found" a few lines into a script.
astra_require_cmd() {
  local cmd="$1" hint="${2:-}"
  if ! command -v "$cmd" >/dev/null 2>&1; then
    astra_die "required command '$cmd' not found on PATH.${hint:+ $hint}"
  fi
}

# astra_mask <value>
# Prints a value with everything but the last 4 characters replaced by '*',
# for logging identifiers (project refs, keys) without fully exposing them.
# NEVER used on genuinely secret values (service-role keys, DB passwords,
# access tokens) — those are never logged at all, masked or not. See each
# script's own comments for what it does/doesn't consider safe to mask-print.
astra_mask() {
  local value="$1"
  local len=${#value}
  if (( len <= 4 )); then
    printf '****'
    return
  fi
  printf '%s%s' "$(printf '%*s' $((len - 4)) '' | tr ' ' '*')" "${value: -4}"
}

# astra_require_uuid <value> <flag-name>
astra_require_uuid() {
  local value="$1" flag="$2"
  if [[ ! "$value" =~ ^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$ ]]; then
    astra_die "$flag must be a UUID (got: '$value')."
  fi
}

# astra_require_project_ref <value> <flag-name>
# Supabase project refs are 20 lowercase alphanumeric characters.
astra_require_project_ref() {
  local value="$1" flag="$2"
  if [[ ! "$value" =~ ^[a-z0-9]{20}$ ]]; then
    astra_die "$flag doesn't look like a Supabase project ref (expected 20 lowercase alphanumeric characters, got: '$value'). Find it in the dashboard URL: https://supabase.com/dashboard/project/<ref>."
  fi
}
