#!/usr/bin/env bash
# scripts/upgrade.spec.bash — combined spec runner.
# Sources every per-module spec under scripts/specs/ and prints one combined
# PASS/FAIL total; exits nonzero on any failure. Per-module specs are also
# runnable standalone (each has its own bottom guard).
#
# Run from repo root: bash scripts/upgrade.spec.bash
set -u
SPEC_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/specs"
# shellcheck source=scripts/specs/common.spec.bash
source "$SPEC_DIR/common.spec.bash"

for spec in helpers lookups preflight yarn node dispatch; do
  # shellcheck source=scripts/specs/helpers.spec.bash
  # shellcheck source=scripts/specs/lookups.spec.bash
  # shellcheck source=scripts/specs/preflight.spec.bash
  # shellcheck source=scripts/specs/yarn.spec.bash
  # shellcheck source=scripts/specs/node.spec.bash
  # shellcheck source=scripts/specs/dispatch.spec.bash
  source "$SPEC_DIR/$spec.spec.bash"
done

printf 'PASS: %d FAIL: %d\n' "$PASS" "$FAIL"
if [[ "$FAIL" -gt 0 ]]; then
  exit 1
fi
exit 0
