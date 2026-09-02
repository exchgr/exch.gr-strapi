#!/usr/bin/env bash
# scripts/all.spec.bash — combined spec runner. Run: bash scripts/all.spec.bash
set -u
SPEC_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/specs"
# shellcheck source=scripts/specs/common.spec.bash
source "$SPEC_DIR/common.spec.bash"

for spec in helpers lookups preflight yarn node deps types workflows docker cli upgrade; do
  source "$SPEC_DIR/$spec.spec.bash"
done

printf 'PASS: %d FAIL: %d\n' "$PASS" "$FAIL"
if [[ "$FAIL" -gt 0 ]]; then
  exit 1
fi
exit 0
