#!/usr/bin/env bash
# scripts/specs/upgrade.spec.bash — outer-shell spec for scripts/upgrade.sh
# (the entry point shell: sourcing, arg parsing, phase dispatch, bottom execution guard).
# Standalone: bash scripts/specs/upgrade.spec.bash
set -u
SPEC_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
UPGRADE_SH="$SPEC_DIR/../upgrade.sh"
# shellcheck source=scripts/specs/common.spec.bash
source "$SPEC_DIR/common.spec.bash"
# shellcheck source=scripts/upgrade.sh
source "$UPGRADE_SH"
# The sourced entry point hardens IFS; restore the default for spec-internal string ops.
IFS=$' \t\n'

# --- phase_order dispatches phases in order (phases mocked: happy path only) ---
CALLS=""
mock_phase() { CALLS+="$1"$'\n'; }
phase_preflight() { mock_phase preflight; }
phase_yarn() { mock_phase yarn; }
phase_node() { mock_phase node; }
phase_deps() { mock_phase deps; }
phase_types() { mock_phase types; }
phase_workflows() { mock_phase workflows; }
phase_dockerfile() { mock_phase dockerfile; }

phase_order
assert_eq "$CALLS" $'preflight\nyarn\nnode\ndeps\ntypes\nworkflows\ndockerfile\n' \
  "phase_order dispatches preflight yarn node deps types workflows dockerfile in order"

# --- main parses --dry-run and dispatches ---
DRY_RUN=0
CALLS=""
main --dry-run
assert_eq "$CALLS" $'preflight\nyarn\nnode\ndeps\ntypes\nworkflows\ndockerfile\n' \
  "main --dry-run dispatches phase_order"
assert_eq "$DRY_RUN" "1" "main --dry-run sets DRY_RUN=1"

# --- main rejects unknown arguments ---
rc=0
( main "bogus-arg" ) || rc=$?
assert_status "$rc" 1 "main unknown argument dies with status 1"

# --- bottom execution guard: stub PATH makes preflight deterministically die ---
stubdir="$(mktemp -d)"
for guard_tool in yarn git gh jq curl asdf; do
  printf '#!/usr/bin/env sh\nexit 9\n' > "$stubdir/$guard_tool"
  chmod +x "$stubdir/$guard_tool"
done

# Sourced (no escape hatch): guard must NOT fire — subshell exits 0.
rc=0
(
  PATH="$stubdir:$PATH"
  unset UPGRADE_SH_SOURCE_ONLY
  source "$UPGRADE_SH" >/dev/null 2>&1
) || rc=$?
assert_status "$rc" 0 "sourcing upgrade.sh never executes phases (guard honored)"

# Direct execution: guard fires, main runs, preflight dies on the stub PATH.
rc=0
(
  PATH="$stubdir:$PATH"
  unset UPGRADE_SH_SOURCE_ONLY
  bash "$UPGRADE_SH" >/dev/null 2>&1
) || rc=$?
assert_status "$rc" 1 "direct execution dispatches main (preflight dies on stub PATH)"

# Direct execution with UPGRADE_SH_SOURCE_ONLY=1: escape hatch suppresses main.
rc=0
(
  PATH="$stubdir:$PATH"
  export UPGRADE_SH_SOURCE_ONLY=1
  bash "$UPGRADE_SH" >/dev/null 2>&1
) || rc=$?
assert_status "$rc" 0 "UPGRADE_SH_SOURCE_ONLY=1 suppresses main on direct execution"

rm -rf "$stubdir"

# Bottom guard: standalone run prints totals; sourced run defers to the runner.
if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  printf 'PASS: %d FAIL: %d\n' "$PASS" "$FAIL"
  if [[ "$FAIL" -gt 0 ]]; then
    exit 1
  fi
  exit 0
fi
