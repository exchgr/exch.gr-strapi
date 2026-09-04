#!/usr/bin/env bash
# scripts/specs/helpers.spec.bash — spec for scripts/lib/helpers.bash (pure helpers).
# Standalone: bash scripts/specs/helpers.spec.bash
set -u
SPEC_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/specs/test-utils.bash
source "$SPEC_DIR/test-utils.bash"
# shellcheck source=scripts/lib/helpers.bash
source "$SPEC_DIR/../lib/helpers.bash"
# The sourced lib hardens IFS; restore the default for spec-internal string ops.
IFS=$' \t\n'

# --- semver_major ---
assert_eq "$(semver_major "24.20.0")" "24" "semver_major 24.20.0 -> 24"
assert_eq "$(semver_major "v4.18.0")" "4" "semver_major v4.18.0 -> 4"

# --- highest_vtag ---
actual="$(printf 'v9/v7\nv6\nv10\n' | highest_vtag)"
assert_eq "$actual" "v10" "highest_vtag picks v10"
rc=0
actual="$(printf '' | highest_vtag)" || rc=$?
assert_eq "$actual" "" "highest_vtag empty stdin -> empty"
assert_status "$rc" 0 "highest_vtag empty stdin -> status 0"

# --- dependabot_pkgs ---
fixture='[{"state":"open","dependency":{"package":{"name":"@strapi/strapi"}}},{"state":"open","dependency":{"package":{"name":"@strapi/strapi"}}},{"state":"open","dependency":{"package":{"name":"qs"}}},{"state":"dismissed","dependency":{"package":{"name":"nanoid"}}}]'
actual="$(dependabot_pkgs <<<"$fixture")"
assert_eq "$actual" $'@strapi/strapi\nqs' "dependabot_pkgs distinct open scoped+plain"

# --- action_tag_newer ---
rc=0; action_tag_newer "v4" "v6" || rc=$?
assert_status "$rc" 0 "action_tag_newer v4 v6 -> 0 (v6 is a strictly newer major)"
rc=0; action_tag_newer "@master" "v1.4" || rc=$?
assert_status "$rc" 1 "action_tag_newer @master v1.4 -> 1 (unparseable ref)"
rc=0; action_tag_newer "v1.4" "" || rc=$?
assert_status "$rc" 1 "action_tag_newer v1.4 empty -> 1 (no candidate)"
rc=0; action_tag_newer "v4" "somebranch" || rc=$?
assert_status "$rc" 1 "action_tag_newer v4 somebranch -> 1 (non-v candidate)"
rc=0; action_tag_newer "v7" "v7" || rc=$?
assert_status "$rc" 1 "action_tag_newer v7 v7 -> 1 (equal major)"

# Bottom guard: standalone run prints totals; sourced run defers to the runner.
finish_spec
