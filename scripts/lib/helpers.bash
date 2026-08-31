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

pick_action_tag() {
  local current="$1" candidate="$2"
  if ! is_vtag "$current" || ! is_vtag "$candidate"; then
    printf '%s\n' "$current"
  elif (( $(semver_major "$candidate") > $(semver_major "$current") )); then
    printf '%s\n' "$candidate"
  else
    printf '%s\n' "$current"
  fi
}
