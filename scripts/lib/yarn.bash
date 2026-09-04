# scripts/lib/yarn.bash — yarn phase: berry version set, stale release cleanup.
# selector: yarn
# Dependencies: common.bash, lookups.bash.
# shellcheck source=scripts/lib/common.bash
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/common.bash"
# shellcheck source=scripts/lib/lookups.bash
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lookups.bash"

phase_yarn() {
  run yarn set version berry
  local installed
  installed="$(current_yarn_version)"
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
  current="$(resolve_yarn_path "$yarnrc")"
  # Fail closed: never delete when the current release can't be positively
  # identified — an empty yarnPath or an absent target file means no-op.
  [[ -n "$current" ]] || return 0
  [[ -f "$releases_dir/$(basename "$current")" ]] || return 0
  local path
  while IFS= read -r path; do
    [[ -n "$path" ]] || continue
    is_stale_release "$path" "$current" || continue
    apply_edit "remove stale yarn release $(basename "$path") (yarnPath -> $(basename "$current"))" rm -f "$path"
    (( DRY_RUN )) || log "yarn: removed stale release $(basename "$path")"
  done < <(find "$releases_dir" -maxdepth 1 -type f -name 'yarn-*.cjs' 2>/dev/null)
}

# The yarnPath value from $1 with one pair of surrounding double or single
# quotes stripped: quoted values are valid YAML and would otherwise never
# match a release basename (and in real mode every release, including the one
# yarnPath points at, would be deleted). Empty when no yarnPath line exists.
resolve_yarn_path() {
  local current
  current="$(sed -n 's/^yarnPath: *//p' "$1" | head -n1)"
  current="${current%\"}"
  current="${current#\"}"
  current="${current%\'}"
  current="${current#\'}"
  printf '%s\n' "$current"
}

# True iff $1 is a release $2 does NOT point at. yarnPath is usually relative
# while find emits absolute paths — compare basenames.
is_stale_release() {
  [[ "$(basename "$1")" != "$(basename "$2")" ]]
}
