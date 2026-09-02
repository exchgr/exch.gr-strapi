#!/usr/bin/env bash
# scripts/specs/common.spec.bash — specs for scripts/lib/common.bash's
# logging and execution wrappers. The orchestrator hardens IFS to $'\n\t', so
# these wrappers must join "$*" with SPACES regardless of the ambient IFS —
# otherwise dry-run and real-run logs fragment one word per line.
# Standalone: bash scripts/specs/common.spec.bash
set -u
SPEC_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/specs/test-utils.bash
source "$SPEC_DIR/test-utils.bash"
# shellcheck source=scripts/lib/common.bash
source "$SPEC_DIR/../lib/common.bash"
IFS=$' \t\n'

hardened() { IFS=$'\n\t'; "$@"; }

# --- log / warn / die: args joined with spaces on a single line ---

out="$(hardened log yarn set version berry)"
assert_eq "$out" "yarn set version berry" "log joins args with spaces under hardened IFS"

err="$(hardened warn node pinned to 24 2>&1)"
assert_eq "$err" "node pinned to 24" "warn joins args with spaces under hardened IFS"

rc=0
err="$(hardened die engines missing 2>&1)" || rc=$?
assert_status "$rc" 1 "die exits 1"
assert_eq "$err" "upgrade.sh: engines missing" "die prefixes and joins on one line"

# --- run: one-line [dry-run] preview / one-line + preview, then execution ---

out="$( IFS=$'\n\t' DRY_RUN=1; run yarn set version berry )"
assert_eq "$out" "[dry-run] yarn set version berry" \
  "run prints a one-line [dry-run] preview under hardened IFS"

fake_cmd() { echo "executed: $1 $2"; }
out="$( IFS=$'\n\t'; DRY_RUN=0; run fake_cmd --flag value )"
assert_eq "$out" $'+ fake_cmd --flag value\nexecuted: --flag value' \
  "run prints a one-line + preview then executes the command under hardened IFS"

# --- apply_edit: one-line dry-run message / execution passthrough ---

out="$( IFS=$'\n\t' DRY_RUN=1; apply_edit 'rewrite FROM lines' fake_cmd a b )"
assert_eq "$out" "[dry-run] edit: rewrite FROM lines" \
  "apply_edit prints a one-line [dry-run] edit message under hardened IFS"

out="$( IFS=$'\n\t'; DRY_RUN=0; apply_edit 'my edit' fake_cmd arg1 arg2 )"
assert_eq "$out" "executed: arg1 arg2" \
  "apply_edit executes the edit command under hardened IFS"

# Bottom guard: standalone run prints totals; sourced run defers to the runner.
if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  printf 'PASS: %d FAIL: %d\n' "$PASS" "$FAIL"
  if [[ "$FAIL" -gt 0 ]]; then
    exit 1
  fi
  exit 0
fi
