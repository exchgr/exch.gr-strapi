#!/usr/bin/env bash
# scripts/specs/upgrade.spec.bash — outer-shell spec for scripts/upgrade.sh
# (entry-point integration: main's phase dispatch, phase_summary, bottom
# execution guard). Arg-parsing units live in cli.spec.bash.
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

# Scratch space for fixtures; the EXIT trap removes it even on a crashed run.
spec_tmp="${TMPDIR:-/tmp}/upgrade-spec.$$"
mkdir -p "$spec_tmp"
trap 'rm -rf "$spec_tmp"' EXIT

# --- phase_summary (real implementation against a read-only fixture repo) ---
summary_repo="$spec_tmp/summary"
mkdir -p "$summary_repo"
printf '{\n  "packageManager": "yarn@4.18.0"\n}\n' > "$summary_repo/package.json"
printf 'nodejs 24.9.0\n' > "$summary_repo/.tool-versions"
summary_out="$(
  REPO_DIR="$summary_repo"
  WANT_ALL=0 WANT_YARN=0 WANT_NODE=0 WANT_DEPS=1 WANT_TRANSITIVE=1
  WANT_TYPES=0 WANT_WORKFLOWS=0 WANT_DOCKERFILE=0
  phase_summary
)"
assert_eq "$summary_out" \
  $'summary: ran [deps transitive]\nsummary: resolved yarn=yarn@4.18.0 node=24.9.0\nsummary: inspect \'git diff\' before committing' \
  "phase_summary logs the selection, resolved yarn/node, and the git-diff reminder"

# --- dispatch: phases mocked to echo their name, so capturing main's stdout in
# a subshell records the dispatched sequence (no recorder variables or files) ---
phase_preflight() { echo preflight; }
phase_yarn() { echo yarn; }
phase_node() { echo node; }
phase_deps() { echo deps; }
phase_transitive() { echo transitive; }
phase_types() { echo types; }
phase_workflows() { echo workflows; }
phase_dockerfile() { echo dockerfile; }
phase_summary() { echo summary; }

# --- main --all dispatches preflight + all seven phases + summary, in order ---
dispatch_of="$(main --all)"
assert_eq "$dispatch_of" \
  $'preflight\nyarn\nnode\ndeps\ntransitive\ntypes\nworkflows\ndockerfile\nsummary' \
  "main --all dispatches all seven phases in canonical order"

# --- main -dt: preflight -> deps -> transitive -> summary, exactly ---
dispatch_of="$(main -dt)"
assert_eq "$dispatch_of" $'preflight\ndeps\ntransitive\nsummary' \
  "main -dt dispatches preflight deps transitive summary exactly"

# --- hard-error dispatch: a failing phase must abort the whole run — no later
# phase dispatched, no summary, non-zero exit (blast-radius control) ---
phase_deps() { echo deps; return 1; }

rc=0
out="$( { main -dt 2>&1 1>/dev/null; } )" || rc=$?
assert_status "$rc" 1 "main aborts with non-zero exit when a phase fails"
assert_contains "$out" "phase_deps failed" "main reports which phase failed on stderr"

out="$( { main -dt 2>/dev/null; } )" || rc=$?
assert_eq "$out" $'preflight\ndeps' \
  "a failing phase stops dispatch: later phases and summary are never run"

phase_deps() { echo deps; }
phase_preflight() { return 1; }
out="$( { main -dt 2>/dev/null; } )" || rc=$?
assert_eq "$out" "" "a failing preflight dispatches no phases at all"

# restore the happy-path mocks for the remaining guard tests
phase_preflight() { echo preflight; }

# --- main --dry-run -y: DRY_RUN set (last echo carries it out) and only yarn ---
dispatch_of="$(DRY_RUN=0; main --dry-run -y; echo "DRY_RUN=$DRY_RUN")"
assert_eq "$dispatch_of" $'preflight\nyarn\nsummary\nDRY_RUN=1' \
  "main --dry-run -y sets DRY_RUN=1 and dispatches only yarn"

# --- no selection: usage on stderr, exit 2, no phases dispatched ---
rc=0
err="$( { main 2>&1 1>/dev/null; } )" || rc=$?
assert_status "$rc" 2 "main with no selection exits 2"
assert_contains "$err" "Usage:" "main with no selection prints usage to stderr"

rc=0
out="$( { main 2>/dev/null; } )" || rc=$?
assert_status "$rc" 2 "main with no selection exits 2 on the stdout-only capture"
assert_eq "$out" "" "main with no selection dispatches no phases"

# --- unknown flag: exit 2, no phases dispatched ---
rc=0
out="$( { main --bogus 2>/dev/null; } )" || rc=$?
assert_status "$rc" 2 "main --bogus exits 2"
assert_eq "$out" "" "main --bogus dispatches no phases"

# --- bottom execution guard: stub PATH makes preflight deterministically die ---
stubdir="$spec_tmp/stub"
mkdir -p "$stubdir"
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
# A selection is required to get past arg parsing and reach preflight.
rc=0
(
  PATH="$stubdir:$PATH"
  unset UPGRADE_SH_SOURCE_ONLY
  bash "$UPGRADE_SH" --all >/dev/null 2>&1
) || rc=$?
assert_status "$rc" 1 "direct execution dispatches main (preflight dies on stub PATH)"

# Direct execution with UPGRADE_SH_SOURCE_ONLY=1: escape hatch suppresses main.
rc=0
(
  PATH="$stubdir:$PATH"
  export UPGRADE_SH_SOURCE_ONLY=1
  bash "$UPGRADE_SH" --all >/dev/null 2>&1
) || rc=$?
assert_status "$rc" 0 "UPGRADE_SH_SOURCE_ONLY=1 suppresses main on direct execution"

# Bottom guard: standalone run prints totals; sourced run defers to the runner.
if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  printf 'PASS: %d FAIL: %d\n' "$PASS" "$FAIL"
  if [[ "$FAIL" -gt 0 ]]; then
    exit 1
  fi
  exit 0
fi
