# scripts/lib/yarn.bash — yarn phase: berry version set, stale release cleanup.
# selector: yarn
# Dependency: common.bash.
# shellcheck source=scripts/lib/common.bash
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/common.bash"

phase_yarn() {
  run yarn set version berry
  local installed
  installed="$(jq -r '.packageManager // empty' "$REPO_DIR/package.json" 2>/dev/null)"
  log "yarn: installed ${installed:-unknown} via 'yarn set version berry'"
  clean_stale_yarn_releases
  run yarn install
  log "yarn: phase complete"
}

# Drop .yarn/releases/*.cjs files that yarnPath no longer points at.
clean_stale_yarn_releases() {
  local releases_dir="$REPO_DIR/.yarn/releases"
  local yarnrc="$REPO_DIR/.yarnrc.yml"
  [[ -d "$releases_dir" && -f "$yarnrc" ]] || return 0
  local current
  current="$(sed -n 's/^yarnPath: *//p' "$yarnrc" | head -n1)"
  [[ -n "$current" ]] || return 0
  local path
  while IFS= read -r path; do
    [[ -n "$path" ]] || continue
    # yarnPath is usually relative while find emits absolute paths — compare basenames.
    if [[ "$(basename "$path")" != "$(basename "$current")" ]]; then
      apply_edit "remove stale yarn release $(basename "$path") (yarnPath -> $(basename "$current"))" rm -f "$path"
      log "yarn: removed stale release $(basename "$path")"
    fi
  done < <(find "$releases_dir" -maxdepth 1 -type f -name 'yarn-*.cjs' 2>/dev/null)
}
