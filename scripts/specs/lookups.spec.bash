#!/usr/bin/env bash
# scripts/specs/lookups.spec.bash — spec for scripts/lib/lookups.bash (fetch-seam lookups).
# Standalone: bash scripts/specs/lookups.spec.bash
set -u
SPEC_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/specs/common.spec.bash
source "$SPEC_DIR/common.spec.bash"
# shellcheck source=scripts/lib/lookups.bash
source "$SPEC_DIR/../lib/lookups.bash"
# The sourced lib hardens IFS; restore the default for spec-internal string ops.
IFS=$' \t\n'

# --- parse_node_lts (index.json is newest-first: skip non-LTS entries) ---
node_lts_fixture='[{"version":"v25.0.0","lts":false},{"version":"v24.99.0","lts":"Jod"}]'
assert_eq "$(parse_node_lts <<<"$node_lts_fixture")" "24.99.0" "parse_node_lts skips non-LTS v25, picks v24.99.0"

# --- parse_yarn_version ---
assert_eq "$(parse_yarn_version <<< '{"version":"4.12.0"}')" "4.12.0" "parse_yarn_version extracts .version"

# --- parse_uses_line ---
assert_eq "$(parse_uses_line "uses: actions/checkout@v7")" "actions/checkout v7" "parse_uses_line actions/checkout@v7"
assert_eq "$(parse_uses_line "uses: superfly/flyctl-actions/setup-flyctl@v1.4")" "superfly/flyctl-actions/setup-flyctl v1.4" "parse_uses_line nested repo path"

# --- parse_remote_tags (pure fallback parsing behind latest_tag_for_repo) ---
remote_tags_fixture='abc123	refs/tags/v9.1.0
def456	refs/tags/v10.2.0
abc123^{}	refs/tags/v10.2.0
zzz	refs/tags/some-branch'
assert_eq "$(parse_remote_tags <<<"$remote_tags_fixture")" "v10.2.0" "parse_remote_tags strips refs, filters ^v, picks highest"
assert_eq "$(printf 'abc\trefs/tags/main\n' | parse_remote_tags)" "" "parse_remote_tags no vtags -> empty"

# --- latest_tag_for_repo (command seam: gh first, git ls-remote fallback) ---
gh() { printf 'v4.1.0\n'; }
assert_eq "$(latest_tag_for_repo "owner/repo")" "v4.1.0" "latest_tag_for_repo uses gh api path"
unset -f gh

gh() { return 1; }
git() { printf 'abc\trefs/tags/v3.2.1\n'; }
assert_eq "$(latest_tag_for_repo "owner/repo")" "v3.2.1" "latest_tag_for_repo falls back to git ls-remote"
unset -f gh git

# Bottom guard: standalone run prints totals; sourced run defers to the runner.
if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  printf 'PASS: %d FAIL: %d\n' "$PASS" "$FAIL"
  if [[ "$FAIL" -gt 0 ]]; then
    exit 1
  fi
  exit 0
fi
