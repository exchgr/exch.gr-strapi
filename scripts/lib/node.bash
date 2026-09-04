# scripts/lib/node.bash — node phase: asdf LTS install/pin, .tool-versions pin,
# package.json engines rewrite.
# selector: node
# Dependencies: common.bash, helpers.bash, lookups.bash.
# shellcheck source=scripts/lib/common.bash
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/common.bash"
# shellcheck source=scripts/lib/helpers.bash
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/helpers.bash"
# shellcheck source=scripts/lib/lookups.bash
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lookups.bash"

phase_node() {
  local lts_full lts_major
  # The LTS lookup gates every mutation below (asdf install/set, the
  # .tool-versions pin, the engines rewrite), so it is a HARD lookup: proceeding
  # with an empty version would corrupt the pin file and engines. A failed or
  # empty lookup dies the phase (dispatch contract — node is a mutation phase),
  # unlike the soft warn-and-skip lookup in docker.bash.
  if ! lts_full="$(latest_node_lts)" || [[ -z "$lts_full" ]]; then
    die "node: could not resolve the latest node LTS"
  fi
  lts_major="$(semver_major "$lts_full")"
  log "node: latest LTS $lts_full (major $lts_major)"
  local current
  current="$(current_node_pin)"
  if [[ -n "$current" ]]; then
    log "node: $current -> $lts_full"
  else
    log "node: (unset) -> $lts_full"
  fi
  if asdf list nodejs 2>/dev/null | grep -q "$lts_full"; then
    log "node: $lts_full already installed"
  else
    run asdf install nodejs "$lts_full"
  fi
  run asdf set --home nodejs "$lts_full"
  pin_tool_versions_node "$lts_full"
  rewrite_engines "$lts_major"
  log "node: phase complete"
}

# Ensure .tool-versions pins exactly `nodejs <version>`; edit only if asdf didn't.
pin_tool_versions_node() {
  local version="$1"
  local toolfile="$REPO_DIR/.tool-versions"
  if [[ -f "$toolfile" ]] && grep -Eq "^nodejs ${version//./\\.}$" "$toolfile"; then
    log "node: .tool-versions already pins $version"
  else
    apply_edit "pin nodejs $version in .tool-versions" __pin_tool_versions "$toolfile" "$version"
    (( DRY_RUN )) || log "node: .tool-versions edit was needed (pinned $version)"
  fi
}

__pin_tool_versions() {
  local toolfile="$1" version="$2"
  if grep -q '^nodejs ' "$toolfile" 2>/dev/null; then
    replace_all_in_file "$toolfile" '^nodejs .*' "nodejs $version"
  else
    printf 'nodejs %s\n' "$version" >> "$toolfile"
  fi
}

# engines: node -> ^<major>.0.0, drop npm pin. Rewritten as a whole file so
# 2-space indent + trailing newline are guaranteed.
rewrite_engines() {
  local major="$1"
  local pkg="$REPO_DIR/package.json"
  local want="^${major}.0.0"
  local cur_node cur_npm
  cur_node="$(jq -r '.engines.node // empty' "$pkg" 2>/dev/null)"
  cur_npm="$(jq -r '.engines.npm // empty' "$pkg" 2>/dev/null)"
  if [[ "$cur_node" == "$want" && -z "$cur_npm" ]]; then
    log "node: engines already ^$major.0.0 without npm pin"
    return 0
  fi
  apply_edit "set engines.node to ^$major.0.0 and drop engines.npm" __rewrite_engines "$pkg" "$major"
  (( DRY_RUN )) || log "node: engines rewritten (node ^$major.0.0, npm pin dropped)"
}

__rewrite_engines() {
  local pkg="$1" major="$2" tmp
  tmp="$(mktemp "${pkg}.XXXXXX")" && \
    jq --arg major "$major" '.engines.node = ("^" + $major + ".0.0") | del(.engines.npm)' "$pkg" > "$tmp" && \
    mv "$tmp" "$pkg" || { rm -f "$tmp"; return 1; }
}
