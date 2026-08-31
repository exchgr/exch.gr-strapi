# scripts/lib/lookups.bash — fetch-seam lookups: network access is confined to
# the latest_* wrappers; the parse_* functions are pure (JSON/text on stdin) and
# are what the spec exercises via fixtures.
# Dependencies: common.bash, helpers.bash.
# shellcheck source=scripts/lib/common.bash
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/common.bash"
# shellcheck source=scripts/lib/helpers.bash
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/helpers.bash"

parse_node_lts() {
  # stdin: https://nodejs.org/dist/index.json (newest-first)
  jq -r '[.[] | select(.lts != false)][0].version | ltrimstr("v")'
}

latest_node_lts() {
  curl -fsSL https://nodejs.org/dist/index.json | parse_node_lts
}

parse_yarn_version() {
  # stdin: https://registry.npmjs.org/yarn/latest
  jq -r '.version'
}

latest_yarn_version() {
  curl -fsSL https://registry.npmjs.org/yarn/latest | parse_yarn_version
}

parse_uses_line() {
  # "uses: owner/repo@ref" (list dashes tolerated) -> "owner/repo ref"
  local line="${1#*uses:}"
  line="${line#"${line%%[![:space:]]*}"}"
  local repo="${line%%@*}"
  local ref="${line#*@}"
  [[ "$line" == *@* ]] || return 1
  printf '%s %s\n' "$repo" "$ref"
}

parse_remote_tags() {
  # stdin: `git ls-remote --tags` lines -> highest ^v[0-9]+ tag
  awk '{ print $2 }' | sed 's#^refs/tags/##' | { grep -E '^v[0-9]+' || true; } | highest_vtag
}

latest_tag_git_fallback() {
  git ls-remote --tags "https://github.com/$1.git" 2>/dev/null | parse_remote_tags
}

latest_tag_for_repo() {
  local tag
  if tag="$(gh api "repos/$1/releases/latest" --jq .tag_name 2>/dev/null)" && [[ -n "$tag" ]]; then
    printf '%s\n' "$tag"
    return 0
  fi
  latest_tag_git_fallback "$1"
}
