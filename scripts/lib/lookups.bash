# scripts/lib/lookups.bash — lookups: network access is confined to the
# latest_* wrappers; the current_* wrappers read local files (side-effect-free);
# the parse_* functions are pure (JSON/text on stdin). The parse_* and current_*
# functions are what the spec exercises via fixtures.
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

# The yarn version currently recorded by a prior phase — empty when
# package.json has no packageManager entry.
current_yarn_version() {
  jq -r '.packageManager // empty' "$REPO_DIR/package.json" 2>/dev/null
}

# The node pin currently recorded in .tool-versions — empty when unset.
current_node_pin() {
  sed -n 's/^nodejs //p' "$REPO_DIR/.tool-versions" 2>/dev/null | head -n1
}

parse_uses_line() {
  # Input: a `uses: owner/repo@ref` workflow line (leading list dash tolerated).
  # Output: "owner/repo ref"; return 1 when there is no @ref after "uses:".
  # Step 1 (yq): parse the line as yaml — bare map or sequence item — and print
  # the raw `uses` value; lines without a usable `uses:` yield empty. The
  # fallback guard keeps a yaml parse failure a normal empty result, not a crash.
  local value
  value="$(printf '%s\n' "$1" | yq -r '.[0].uses? // .uses?' 2>/dev/null || true)"
  # Step 2: one anchored regex splits at the FIRST @ into "owner/repo ref".
  value="$(printf '%s' "$value" | sed -En 's/^([^@]+)@(.+)$/\1 \2/p')"
  [[ -n "$value" ]] || return 1
  printf '%s\n' "$value"
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
