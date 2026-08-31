# scripts/lib/workflows.bash — workflows phase: bump `uses: owner/repo@ref`
# pins across every .github/workflows/*.yml. Only `uses:` lines are matched, so
# `runs-on:` lines can never be touched. The tag lookup is a sanctioned
# warn-and-continue seam: a failed lookup warns, keeps the old pin, and keeps
# going (preflight remains hard-fail for the environment itself).
# Dependencies: common.bash, helpers.bash, lookups.bash.
# shellcheck source=scripts/lib/common.bash
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/common.bash"
# shellcheck source=scripts/lib/helpers.bash
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/helpers.bash"
# shellcheck source=scripts/lib/lookups.bash
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lookups.bash"

# selector: workflows
phase_workflows() {
  local dir="$REPO_DIR/.github/workflows"
  if [[ ! -d "$dir" ]]; then
    log "workflows: no .github/workflows directory — skipping"
    return 0
  fi
  local file
  for file in "$dir"/*.yml; do
    [[ -e "$file" ]] || continue
    bump_workflow_pins "$file"
  done
  log "workflows: phase complete"
}

# For each unique `uses: owner/repo@ref` pin in the file: resolve the latest
# tag via latest_tag_for_repo, bump only when action_tag_newer says the latest
# is a strictly-higher major, and replace the exact `uses:$repo@$old` token.
# Pins are deduped so a repo referenced twice is bumped once and logged once.
bump_workflow_pins() {
  local file="$1" raw_pins pins pin repo ref new
  raw_pins="$(grep 'uses:' "$file" 2>/dev/null)" || raw_pins=""
  pins="$(printf '%s\n' "$raw_pins" | while IFS= read -r line; do
    parse_uses_line "$line" 2>/dev/null || true
  done | sort -u)"
  if [[ -z "${pins//[[:space:]]/}" ]]; then
    log "workflows: $(basename "$file") has no uses: pins — skipping"
    return 0
  fi
  while IFS= read -r pin; do
    [[ -n "$pin" ]] || continue
    repo="${pin% *}"
    ref="${pin#* }"
    if ! new="$(latest_tag_for_repo "$repo")" || [[ -z "$new" ]]; then
      warn "workflows: no latest tag found for $repo — keeping $repo@$ref"
      continue
    fi
    if action_tag_newer "$ref" "$new"; then
      apply_edit "bump $repo@$ref -> $repo@$new in $(basename "$file")" \
        replace_all_in_file "$file" "$repo@$ref" "$repo@$new"
      log "workflows: bumped $repo@$ref -> $repo@$new in $(basename "$file")"
    else
      log "workflows: $repo@$ref in $(basename "$file") already current — no-op"
    fi
  done <<<"$pins"
}
