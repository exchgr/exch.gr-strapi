# scripts/lib/helpers.bash — pure helpers: no network, no filesystem writes, no
# side effects. Dependency: common.bash.
# shellcheck source=scripts/lib/common.bash
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/common.bash"

# --- pure helpers ----------------------------------------------------------------

semver_major() {
  local version="${1#v}"
  printf '%s\n' "${version%%.*}"
}

semver_gte() {
  [[ "$(printf '%s\n' "$1" "$2" | sort -V | head -n1)" == "$2" ]]
}

is_lts_entry() {
  printf '%s' "$1" | jq -e '.lts != false' >/dev/null 2>&1
}

highest_vtag() {
  { grep -E '^v[0-9]+' || true; } | sort -V | tail -n1
}

dependabot_pkgs() {
  jq -r '[.[] | select(.state == "open") | .dependency.package.name] | unique | .[]'
}

is_vtag() {
  [[ "$1" =~ ^v[0-9]+([.][0-9]+)*$ ]]
}

action_tag_newer() {
  # True (status 0) iff $2 is a `v<major>` tag whose major is strictly greater
  # than $1's parseable major. @master, non-v tags, and garbage compare false.
  is_vtag "$1" || return 1
  is_vtag "$2" || return 1
  (( $(semver_major "$2") > $(semver_major "$1") ))
}
