#!/usr/bin/env bash
# scripts/upgrade.sh — thin entry point for the idempotent exch.gr Strapi
# upgrade (phases: preflight → yarn → node → deps → types → workflows → docker).
# --dry-run prints every mutation without applying it.
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

phase_order() {
  phase_preflight
  phase_yarn
  phase_node
  phase_deps
  phase_types
  phase_workflows
  phase_dockerfile
}

# --- entry point -------------------------------------------------------------------

main() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --dry-run) export DRY_RUN=1 ;;
      *) die "unknown argument: $1" ;;
    esac
    shift
  done
  phase_order
}

# Bottom execution guard: never run phases when sourced (also honors the
# spec harness's UPGRADE_SH_SOURCE_ONLY escape hatch). Lives only here.
if [[ "${BASH_SOURCE[0]}" == "$0" && "${UPGRADE_SH_SOURCE_ONLY:-0}" != "1" ]]; then
  main "$@"
fi
