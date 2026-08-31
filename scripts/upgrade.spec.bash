#!/usr/bin/env bash
# TDD spec harness for scripts/upgrade.sh (plain bash, no framework).
# Run from repo root: bash scripts/upgrade.spec.bash
set -u

PASS=0
FAIL=0

assert_eq() {
  local actual="$1" expected="$2" label="$3"
  if [[ "$actual" == "$expected" ]]; then
    PASS=$((PASS + 1))
  else
    FAIL=$((FAIL + 1))
    printf 'FAIL: %s\n  expected: <%s>\n  actual:   <%s>\n' "$label" "$expected" "$actual" >&2
  fi
}

assert_status() {
  local actual="$1" expected="$2" label="$3"
  if [[ "$actual" -eq "$expected" ]]; then
    PASS=$((PASS + 1))
  else
    FAIL=$((FAIL + 1))
    printf 'FAIL: %s\n  expected status: <%s>\n  actual status:   <%s>\n' "$label" "$expected" "$actual" >&2
  fi
}

export UPGRADE_SH_SOURCE_ONLY=1
# shellcheck source=scripts/upgrade.sh
source "$(dirname "$0")/upgrade.sh"
# The sourced script hardens IFS; restore the default for spec-internal string ops.
IFS=$' \t\n'

# --- semver_major ---
assert_eq "$(semver_major "24.20.0")" "24" "semver_major 24.20.0 -> 24"
assert_eq "$(semver_major "v4.18.0")" "4" "semver_major v4.18.0 -> 4"

# --- semver_gte ---
rc=0; semver_gte "4.18.0" "4.9.0" || rc=$?
assert_status "$rc" 0 "semver_gte 4.18.0 >= 4.9.0 -> 0"
rc=0; semver_gte "3.6.0" "4.0.0" || rc=$?
assert_status "$rc" 1 "semver_gte 3.6.0 >= 4.0.0 -> 1"
rc=0; semver_gte "4.18.0" "4.18.0" || rc=$?
assert_status "$rc" 0 "semver_gte 4.18.0 >= 4.18.0 -> 0"

# --- is_lts_entry ---
rc=0; is_lts_entry '{"lts":"Jod"}' || rc=$?
assert_status "$rc" 0 "is_lts_entry lts string -> 0"
rc=0; is_lts_entry '{"lts":false}' || rc=$?
assert_status "$rc" 1 "is_lts_entry lts false -> 1"

# --- highest_vtag ---
actual="$(printf 'v9/v7\nv6\nv10\n' | highest_vtag)"
assert_eq "$actual" "v10" "highest_vtag picks v10"
rc=0
actual="$(printf '' | highest_vtag)"
assert_eq "$actual" "" "highest_vtag empty stdin -> empty"
assert_status "$rc" 0 "highest_vtag empty stdin -> status 0"

# --- dependabot_pkgs ---
fixture='[{"state":"open","dependency":{"package":{"name":"@strapi/strapi"}}},{"state":"open","dependency":{"package":{"name":"@strapi/strapi"}}},{"state":"open","dependency":{"package":{"name":"qs"}}},{"state":"dismissed","dependency":{"package":{"name":"nanoid"}}}]'
actual="$(dependabot_pkgs <<<"$fixture")"
assert_eq "$actual" $'@strapi/strapi\nqs' "dependabot_pkgs distinct open scoped+plain"

# --- pick_action_tag ---
assert_eq "$(pick_action_tag "v4" "v6")" "v6" "pick_action_tag v4 v6 -> v6"
assert_eq "$(pick_action_tag "@master" "v1.4")" "@master" "pick_action_tag @master v1.4 -> @master"
assert_eq "$(pick_action_tag "v1.4" "")" "v1.4" "pick_action_tag v1.4 empty -> v1.4"
assert_eq "$(pick_action_tag "v4" "somebranch")" "v4" "pick_action_tag v4 somebranch -> v4"
assert_eq "$(pick_action_tag "v7" "v7")" "v7" "pick_action_tag v7 v7 equal major -> keep"

printf 'PASS: %d FAIL: %d\n' "$PASS" "$FAIL"
if [[ "$FAIL" -gt 0 ]]; then
  exit 1
fi
exit 0
