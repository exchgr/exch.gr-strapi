# scripts/lib/types.bash — types phase: regenerate strapi content types.
# Running `yarn strapi ts:generate-types` mutates types/generated/
# contentTypes.d.ts as a side effect of invoking strapi. This is the script's
# ONLY warn-and-continue execution: a failed generation warns and returns 0 so
# later phases still run (unlike the preflight/deps hard-fail contract).
# selector: types
# Dependency: common.bash.
# shellcheck source=scripts/lib/common.bash
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/common.bash"

# selector: types
phase_types() {
  log "types: generating strapi content types"
  if (( DRY_RUN )); then
    log "types: [dry-run] would run: yarn strapi ts:generate-types"
  else
    log "+ yarn strapi ts:generate-types"
    if ! yarn strapi ts:generate-types; then
      warn "types: ts:generate-types failed — continuing"
    fi
  fi
  log "types: phase complete"
}
