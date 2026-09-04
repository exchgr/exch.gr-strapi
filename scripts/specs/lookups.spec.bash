#!/usr/bin/env bash
# scripts/specs/lookups.spec.bash — spec for scripts/lib/lookups.bash (fetch-seam lookups).
# Standalone: bash scripts/specs/lookups.spec.bash
set -u
SPEC_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/specs/test-utils.bash
source "$SPEC_DIR/test-utils.bash"
# shellcheck source=scripts/lib/lookups.bash
source "$SPEC_DIR/../lib/lookups.bash"
# The sourced lib hardens IFS; restore the default for spec-internal string ops.
IFS=$' \t\n'

ltmp="$(mktemp -d)"
trap 'rm -rf "$ltmp"' EXIT

# --- parse_node_lts (index.json is newest-first: skip non-LTS entries) ---
node_lts_fixture='[{"version":"v25.0.0","lts":false},{"version":"v24.99.0","lts":"Jod"}]'
assert_eq "$(parse_node_lts <<<"$node_lts_fixture")" "24.99.0" "parse_node_lts skips non-LTS v25, picks v24.99.0"

# --- parse_yarn_version ---
assert_eq "$(parse_yarn_version <<< '{"version":"4.12.0"}')" "4.12.0" "parse_yarn_version extracts .version"

# --- parse_uses_line ---
assert_eq "$(parse_uses_line "uses: actions/checkout@v7")" "actions/checkout v7" "parse_uses_line actions/checkout@v7"
assert_eq "$(parse_uses_line "uses: superfly/flyctl-actions/setup-flyctl@v1.4")" "superfly/flyctl-actions/setup-flyctl v1.4" "parse_uses_line nested repo path"

# Negative case: a `uses:` line with no @ref fails the parse contract.
uses_rc=0
uses_out="$(parse_uses_line "uses: actions/checkout")" || uses_rc=$?
assert_status "$uses_rc" 1 "parse_uses_line returns 1 for a uses: line with no @ref"
assert_eq "$uses_out" "" "parse_uses_line prints nothing for a refless uses: line"

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

# --- current_yarn_version / current_node_pin (local-file lookups, no network) ---
printf '{\n  "packageManager": "yarn@4.18.0"\n}\n' > "$ltmp/package.json"
printf 'yarn 4.12.0\nnodejs 24.9.0\n' > "$ltmp/.tool-versions"
assert_eq "$(REPO_DIR="$ltmp" current_yarn_version)" "yarn@4.18.0" \
  "current_yarn_version reads the packageManager entry from package.json"
assert_eq "$(REPO_DIR="$ltmp" current_node_pin)" "24.9.0" \
  "current_node_pin reads the nodejs pin from .tool-versions"
printf '{}\n' > "$ltmp/package.json"
assert_eq "$(REPO_DIR="$ltmp" current_yarn_version)" "" \
  "current_yarn_version is empty without a packageManager entry"

# Bottom guard: standalone run prints totals; sourced run defers to the runner.
finish_spec
