#!/usr/bin/env bash
# scripts/specs/preflight.spec.bash — spec for scripts/lib/preflight.bash.
# Standalone: bash scripts/specs/preflight.spec.bash
set -u
SPEC_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/specs/common.spec.bash
source "$SPEC_DIR/common.spec.bash"
# shellcheck source=scripts/lib/preflight.bash
source "$SPEC_DIR/../lib/preflight.bash"
# The sourced lib hardens IFS; restore the default for spec-internal string ops.
IFS=$' \t\n'

# --- REQUIRED_TOOLS ---
assert_eq "$(printf '%s\n' "${REQUIRED_TOOLS[@]}")" $'yarn\ngit\ngh\njq\nyq\ncurl\nasdf' "REQUIRED_TOOLS covers yarn git gh jq yq curl asdf"

# --- derive_gh_repo (command seam: mocked git remote get-url) ---
git() { printf 'https://github.com/exchgr/exch.gr-strapi.git\n'; }
assert_eq "$(derive_gh_repo)" "exchgr/exch.gr-strapi" "derive_gh_repo strips https github URL"
unset -f git

git() { printf 'git@github.com:exchgr/exch.gr-strapi.git\n'; }
assert_eq "$(derive_gh_repo)" "exchgr/exch.gr-strapi" "derive_gh_repo strips ssh github URL"
unset -f git

rc=0
git() { return 1; }
derive_gh_repo || rc=$?
assert_status "$rc" 1 "derive_gh_repo without origin -> status 1"
unset -f git

# Bottom guard: standalone run prints totals; sourced run defers to the runner.
if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  printf 'PASS: %d FAIL: %d\n' "$PASS" "$FAIL"
  if [[ "$FAIL" -gt 0 ]]; then
    exit 1
  fi
  exit 0
fi
