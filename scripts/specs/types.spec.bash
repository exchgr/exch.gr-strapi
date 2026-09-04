#!/usr/bin/env bash
# scripts/specs/types.spec.bash — spec for scripts/lib/types.bash (types phase:
# the guarded ts:generate-types invocation, the script's only warn-and-continue).
# Standalone: bash scripts/specs/types.spec.bash
set -u
SPEC_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/specs/test-utils.bash
source "$SPEC_DIR/test-utils.bash"
# shellcheck source=scripts/lib/types.bash
source "$SPEC_DIR/../lib/types.bash"
# The sourced lib hardens IFS; restore the default for spec-internal string ops.
IFS=$' \t\n'

ttmp="$(mktemp -d)"
trap 'rm -rf "$ttmp" "$dry_yarn" "$ok_yarn" "$fail_yarn"' EXIT

# --- dry-run: would-run line printed, yarn never executed ---
dry_yarn="$(mktemp -d)"
printf '#!/usr/bin/env sh\nprintf "%%s\\n" "$*" >> "$0.args"\n' > "$dry_yarn/yarn"
chmod +x "$dry_yarn/yarn"
dry_log="$ttmp/dry-log"
(
  PATH="$dry_yarn:$PATH"
  DRY_RUN=1
  phase_types
) > "$dry_log"
dry_rc=$?
assert_status "$dry_rc" 0 "phase_types in dry-run completes with status 0"
assert_eq "$(cat "$dry_yarn/yarn.args" 2>/dev/null)" "" \
  "phase_types in dry-run never executes yarn"
assert_eq "$(grep -c 'would run: yarn strapi ts:generate-types' "$dry_log")" "1" \
  "phase_types in dry-run prints the would-run line"

# --- real path, success: guarded direct invocation records the strapi args ---
ok_yarn="$(mktemp -d)"
printf '#!/usr/bin/env sh\nprintf "%%s\\n" "$*" >> "$0.args"\n' > "$ok_yarn/yarn"
chmod +x "$ok_yarn/yarn"
ok_log="$ttmp/ok-log"
(
  PATH="$ok_yarn:$PATH"
  phase_types
) > "$ok_log"
ok_rc=$?
assert_status "$ok_rc" 0 "phase_types on success completes with status 0"
assert_eq "$(cat "$ok_yarn/yarn.args")" "strapi ts:generate-types" \
  "phase_types runs yarn strapi ts:generate-types as a guarded direct invocation"
assert_eq "$(grep -c 'ts:generate-types failed' "$ok_log")" "0" \
  "phase_types on success does not warn"

# --- real path, failure: warn-and-continue, status stays 0 ---
fail_yarn="$(mktemp -d)"
printf '#!/usr/bin/env sh\nprintf "%%s\\n" "$*" >> "$0.args"\nexit 1\n' > "$fail_yarn/yarn"
chmod +x "$fail_yarn/yarn"
fail_rc=0
fail_err="$ttmp/fail-err"
(
  PATH="$fail_yarn:$PATH"
  {
    phase_types
  } 2> "$fail_err"
) || fail_rc=$?
assert_status "$fail_rc" 0 \
  "phase_types on ts:generate-types failure continues (status 0, never hard-fails)"
assert_eq "$(cat "$fail_yarn/yarn.args")" "strapi ts:generate-types" \
  "phase_types on failure still invoked yarn strapi ts:generate-types"
assert_eq "$(grep -c 'ts:generate-types failed — continuing' "$fail_err")" "1" \
  "phase_types on ts:generate-types failure warns and continues"

# Bottom guard: standalone run prints totals; sourced run defers to the runner.
finish_spec
