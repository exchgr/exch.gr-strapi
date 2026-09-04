#!/usr/bin/env bash
# scripts/specs/cli.spec.bash — spec for scripts/lib/cli.bash (arg parsing only:
# flags -> WANT_* selection booleans, usage text, error exits).
# Standalone: bash scripts/specs/cli.spec.bash
set -u
SPEC_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/specs/test-utils.bash
source "$SPEC_DIR/test-utils.bash"
# shellcheck source=scripts/lib/cli.bash
source "$SPEC_DIR/../lib/cli.bash"
# The sourced lib hardens IFS; restore the default for spec-internal string ops.
IFS=$' \t\n'

reset_selection() {
  WANT_ALL=0 WANT_YARN=0 WANT_NODE=0 WANT_DEPS=0 WANT_TRANSITIVE=0
  WANT_TYPES=0 WANT_WORKFLOWS=0 WANT_DOCKERFILE=0
  DRY_RUN=0
}

# --- combined short flags select exactly their phases ---
reset_selection
parse_args -dt
assert_eq "$WANT_DEPS" "1" "parse_args -dt selects deps"
assert_eq "$WANT_TRANSITIVE" "1" "parse_args -dt selects transitive"
assert_eq "$WANT_YARN" "0" "parse_args -dt does not select yarn"
assert_eq "$WANT_ALL" "0" "parse_args -dt does not select all"
assert_eq "$DRY_RUN" "0" "parse_args -dt does not set dry-run"

# --- independent combined shorts ---
reset_selection
parse_args -yd
assert_eq "$WANT_YARN" "1" "parse_args -yd selects yarn"
assert_eq "$WANT_DEPS" "1" "parse_args -yd selects deps"

# --- --all selects everything ---
reset_selection
parse_args --all
assert_eq "$WANT_ALL" "1" "parse_args --all selects all"

# --- long forms match their short forms ---
reset_selection
parse_args --dependencies --transitive
assert_eq "$WANT_DEPS" "1" "parse_args --dependencies selects deps"
assert_eq "$WANT_TRANSITIVE" "1" "parse_args --transitive selects transitive"

# --- --dry-run composes with a selection ---
reset_selection
parse_args --dry-run -y
assert_eq "$DRY_RUN" "1" "parse_args --dry-run sets DRY_RUN"
assert_eq "$WANT_YARN" "1" "parse_args --dry-run -y still selects yarn"

# --- combined short forms: -sniw selects exactly node, types, workflows, docker ---
reset_selection
parse_args -sniw
assert_eq "$WANT_NODE" "1" "parse_args -sniw selects node"
assert_eq "$WANT_TYPES" "1" "parse_args -sniw selects types"
assert_eq "$WANT_WORKFLOWS" "1" "parse_args -sniw selects workflows"
assert_eq "$WANT_DOCKERFILE" "1" "parse_args -sniw selects docker"

# --- --help long form: usage to stdout, exit 0 ---
rc=0
help_out="$( { parse_args --help; } )" || rc=$?
assert_status "$rc" 0 "parse_args --help exits 0"
assert_contains "$help_out" "Usage:" "parse_args --help prints usage to stdout"

# --- long-form selection ---
reset_selection
parse_args --workflows
assert_eq "$WANT_WORKFLOWS" "1" "parse_args --workflows selects workflows"

# --- no selection: usage on stderr, exit 2 ---
rc=0
err="$( { parse_args 2>&1 1>/dev/null; } )" || rc=$?
assert_status "$rc" 2 "parse_args with no selection exits 2"
assert_contains "$err" "no phases selected" "parse_args no-selection explains the error"
assert_contains "$err" "Usage:" "parse_args no-selection prints usage to stderr"

# --- unknown flag / stray operand: usage error, exit 2 ---
rc=0
( parse_args --bogus ) 2>/dev/null || rc=$?
assert_status "$rc" 2 "parse_args --bogus exits 2"

rc=0
( parse_args bogus-arg ) 2>/dev/null || rc=$?
assert_status "$rc" 2 "parse_args positional argument exits 2"

# --- -h: usage to stdout, exit 0 ---
rc=0
help_out="$( { parse_args -h; } )" || rc=$?
assert_status "$rc" 0 "parse_args -h exits 0"
assert_contains "$help_out" "Usage:" "parse_args -h prints usage to stdout"

# --- usage text lists every flag ---
usage_text="$(usage)"
for flag in --all --yarn --node --dependencies --transitive --strapi-types --workflows --docker --dry-run; do
  assert_contains "$usage_text" "$flag" "usage mentions $flag"
done

# Bottom guard: standalone run prints totals; sourced run defers to the runner.
finish_spec
