#!/usr/bin/env bash
# scripts/upgrade.sh — idempotent upgrade for the exch.gr Strapi blog.
#
# Phases (in order):
#   preflight → yarn → node → deps → types → workflows → dockerfile → summary
#
# --dry-run prints every mutation without applying it.
# Sourcing this file (e.g. from upgrade.spec.bash) never executes a phase:
# main runs only when the file is executed directly.
set -uo pipefail
IFS=$'\n\t'

# --- globals -------------------------------------------------------------------

DRY_RUN=0
REQUIRED_TOOLS=(yarn git gh jq curl asdf)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

# --- logging -------------------------------------------------------------------

log() {
  printf '%s\n' "$*"
}

warn() {
  printf '%s\n' "$*" >&2
}

die() {
  warn "upgrade.sh: $*"
  exit 1
}

# --- execution wrappers (dry-run aware) -----------------------------------------

run() {
  if (( DRY_RUN )); then
    log "[dry-run] $*"
  else
    log "+ $*"
    "$@"
  fi
}

apply_edit() {
  local description="$1"
  shift
  if (( DRY_RUN )); then
    log "[dry-run] edit: $description"
  else
    "$@"
  fi
}

# --- pure helpers ----------------------------------------------------------------

semver_major() {
  local version="${1#v}"
  printf '%s\n' "${version%%.*}"
}

semver_gte() {
  [[ "$(printf '%s\n' "$1" "$2" | sort -V | head -n1)" == "$2" ]]
}

is_lts_entry() {
  printf '%s' "$1" | jq -e '.lts != false' >/dev/null 2>&1
}

highest_vtag() {
  { grep -E '^v[0-9]+' || true; } | sort -V | tail -n1
}

dependabot_pkgs() {
  jq -r '[.[] | select(.state == "open") | .dependency.package.name] | unique | .[]'
}

is_vtag() {
  [[ "$1" =~ ^v[0-9]+([.][0-9]+)*$ ]]
}

pick_action_tag() {
  local current="$1" candidate="$2"
  if ! is_vtag "$current" || ! is_vtag "$candidate"; then
    printf '%s\n' "$current"
  elif (( $(semver_major "$candidate") > $(semver_major "$current") )); then
    printf '%s\n' "$candidate"
  else
    printf '%s\n' "$current"
  fi
}

derive_gh_repo() {
  local url
  url="$(git -C "$REPO_DIR" remote get-url origin 2>/dev/null)" || return 1
  url="${url##*github.com[:/]}"
  url="${url%.git}"
  [[ "$url" == */* ]] || return 1
  printf '%s\n' "$url"
}

GH_REPO="$(derive_gh_repo || true)"

# --- phases ----------------------------------------------------------------------

# Hard-error preflight: any failure aborts the run. No skip-and-continue.
phase_preflight() {
  local -a missing=()
  local tool
  for tool in "${REQUIRED_TOOLS[@]}"; do
    command -v "$tool" >/dev/null 2>&1 || missing+=("$tool")
  done
  if (( ${#missing[@]} > 0 )); then
    die "missing required tools: ${missing[*]}"
  fi
  gh auth status >/dev/null 2>&1 || die "gh is not authenticated — run 'gh auth login' first"
  if [[ -n "$(git -C "$REPO_DIR" status --porcelain)" ]]; then
    die "worktree is dirty — commit or stash before running the upgrade"
  fi
  log "preflight: all checks passed (repo: ${GH_REPO:-unknown})"
}

# Later phases are added by subsequent subtasks.

phase_order() {
  phase_preflight
}

# --- entry point ------------------------------------------------------------------

main() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --dry-run) DRY_RUN=1 ;;
      *) die "unknown argument: $1" ;;
    esac
    shift
  done
  phase_order
}

# Bottom execution guard: never run phases when sourced (also honors the
# spec harness's UPGRADE_SH_SOURCE_ONLY escape hatch).
if [[ "${BASH_SOURCE[0]}" == "$0" && "${UPGRADE_SH_SOURCE_ONLY:-0}" != "1" ]]; then
  main "$@"
fi
