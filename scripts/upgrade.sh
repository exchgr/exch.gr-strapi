#!/usr/bin/env bash
# scripts/upgrade.sh — thin orchestrator for the idempotent exch.gr Strapi
# upgrade. cli.bash parses the flags into WANT_* selection booleans; main then
# conditionally runs each phase in canonical order (preflight always first,
# summary always last). --dry-run composes with any selection and prints every
# mutation without applying it.
set -uo pipefail
IFS=$'\n\t'

LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib"
source "$LIB_DIR/common.bash"
source "$LIB_DIR/helpers.bash"
source "$LIB_DIR/lookups.bash"
source "$LIB_DIR/preflight.bash"
source "$LIB_DIR/yarn.bash"
source "$LIB_DIR/node.bash"
source "$LIB_DIR/deps.bash"
source "$LIB_DIR/types.bash"
source "$LIB_DIR/workflows.bash"
source "$LIB_DIR/docker.bash"
source "$LIB_DIR/cli.bash"

# --- orchestrator ------------------------------------------------------------------

# Read-only closing report: what ran, where yarn/node now stand, and the
# reminder to review the diff before committing. No side effects.
phase_summary() {
  local ran="all"
  if (( ! WANT_ALL )); then
    ran=""
    (( WANT_YARN )) && ran+=" yarn"
    (( WANT_NODE )) && ran+=" node"
    (( WANT_DEPS )) && ran+=" deps"
    (( WANT_TRANSITIVE )) && ran+=" transitive"
    (( WANT_TYPES )) && ran+=" types"
    (( WANT_WORKFLOWS )) && ran+=" workflows"
    (( WANT_DOCKERFILE )) && ran+=" dockerfile"
    ran="${ran# }"
  fi
  local yarn_version node_version
  yarn_version="$(jq -r '.packageManager // empty' "$REPO_DIR/package.json" 2>/dev/null)"
  node_version="$(sed -n 's/^nodejs //p' "$REPO_DIR/.tool-versions" 2>/dev/null | head -n1)"
  log "summary: ran [$ran]"
  log "summary: resolved yarn=${yarn_version:-unknown} node=${node_version:-unset}"
  log "summary: inspect 'git diff' before committing"
}

# --- entry point -------------------------------------------------------------------

main() {
  parse_args "$@"
  phase_preflight
  if (( WANT_ALL || WANT_YARN )); then phase_yarn; fi
  if (( WANT_ALL || WANT_NODE )); then phase_node; fi
  if (( WANT_ALL || WANT_DEPS )); then phase_deps; fi
  if (( WANT_ALL || WANT_TRANSITIVE )); then phase_transitive; fi
  if (( WANT_ALL || WANT_TYPES )); then phase_types; fi
  if (( WANT_ALL || WANT_WORKFLOWS )); then phase_workflows; fi
  if (( WANT_ALL || WANT_DOCKERFILE )); then phase_dockerfile; fi
  phase_summary
}

# Bottom execution guard: never run phases when sourced (also honors the
# spec harness's UPGRADE_SH_SOURCE_ONLY escape hatch). Lives only here.
if [[ "${BASH_SOURCE[0]}" == "$0" && "${UPGRADE_SH_SOURCE_ONLY:-0}" != "1" ]]; then
  main "$@"
fi
