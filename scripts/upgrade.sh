#!/usr/bin/env bash
# scripts/upgrade.sh — thin entry point for the idempotent exch.gr Strapi upgrade.
#
# Phases (in order): preflight → yarn → node
#
# --dry-run prints every mutation without applying it.
# Sourcing this file (e.g. from the specs) never executes a phase: main runs only
# when the file is executed directly.
#
# Canonical sourcing order for the lib modules (each module sources its own
# dependencies, so repeated sourcing is safe):
#   lib/common.bash
#   lib/helpers.bash
#   lib/lookups.bash
#   lib/preflight.bash
#   lib/yarn.bash
#   lib/node.bash
set -uo pipefail
IFS=$'\n\t'

LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib"
# shellcheck source=scripts/lib/common.bash
source "$LIB_DIR/common.bash"
# shellcheck source=scripts/lib/helpers.bash
source "$LIB_DIR/helpers.bash"
# shellcheck source=scripts/lib/lookups.bash
source "$LIB_DIR/lookups.bash"
# shellcheck source=scripts/lib/preflight.bash
source "$LIB_DIR/preflight.bash"
# shellcheck source=scripts/lib/yarn.bash
source "$LIB_DIR/yarn.bash"
# shellcheck source=scripts/lib/node.bash
source "$LIB_DIR/node.bash"

phase_order() {
  phase_preflight
  phase_yarn
  phase_node
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
