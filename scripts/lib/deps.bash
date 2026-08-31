# scripts/lib/deps.bash — deps phases: direct-dependency bumps, Strapi trio
# lockstep, strapi->react peer reconcile, dependabot security bumps,
# transitive refresh, dedupe, install.
# Selectors: deps (phase_deps), transitive (phase_transitive) — split so the
# CLI selectors can pick them independently.
# Dependencies: common.bash, helpers.bash.
# shellcheck source=scripts/lib/common.bash
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/common.bash"
# shellcheck source=scripts/lib/helpers.bash
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/helpers.bash"

# selector: deps
phase_deps() {
  run yarn up '*'
  run yarn up '@strapi/strapi@latest' '@strapi/plugin-graphql@latest' '@strapi/plugin-users-permissions@latest'
  reconcile_strapi_react
  dependabot_bumps
  run yarn install
  log "deps: phase complete"
}

# Float react to the newest major strapi's peer-dependency range allows — and
# no further. Safety: react NEVER floats past strapi's peer range, because the
# target major is derived FROM the peer range itself; while strapi still
# requires react 18 this step is a no-op, and when strapi allows 19 the next
# deps run picks react 19 up automatically.
reconcile_strapi_react() {
  local peer current target current_major
  if ! peer="$(fetch_strapi_peer_range)" || [[ -z "$peer" ]]; then
    log "deps: no react peer range found — skipping reconcile"
    return 0
  fi
  if ! target="$(peer_range_major "$peer")"; then
    warn "deps: unparseable react peer range '$peer' — skipping reconcile"
    return 0
  fi
  current="$(jq -r '.dependencies.react // empty' "$REPO_DIR/package.json" 2>/dev/null)"
  if [[ -z "$current" ]]; then
    log "deps: react not declared in package.json — skipping reconcile"
    return 0
  fi
  current_major="$(peer_range_major "$current")" || current_major=""
  if [[ "$current_major" == "$target" ]]; then
    log "deps: react '$current' already matches strapi peer range '$peer' — no-op"
    return 0
  fi
  log "deps: strapi peer range '$peer' -> target major $target (react '$current' -> '^${target}.0.0')"
  run yarn up "react@^${target}.0.0"
  # Lazy install: only reconcile pays for an install, and only when react
  # actually moved; phase_deps still ends with its own final install.
  run yarn install
}

# Registry-fresh metadata after the trio upgrade; strapi's react peer
# usually lives on @strapi/strapi, @strapi/admin as fallback source. Bash
# functions are late-bound, so specs shadow this name directly to stub it.
fetch_strapi_peer_range() {
  local pkg out
  for pkg in '@strapi/strapi' '@strapi/admin'; do
    if out="$(yarn npm info "${pkg}@latest" --fields peerDependencies --json 2>/dev/null | parse_strapi_react_peer)" && [[ -n "$out" ]]; then
      printf '%s\n' "$out"
      return 0
    fi
  done
  return 1
}

parse_strapi_react_peer() {
  # stdin: `yarn npm info <pkg> --fields peerDependencies --json` output
  # (shape tolerated either bare or wrapped). Prints the react peer range.
  jq -r 'first(.. | objects | .peerDependencies?.react? // empty) // empty'
}

# Pure: base major from a semver range — ^18.0.0, ~19.2.1, 18.3.1, >=18,
# ">=18 <20" (first number token wins), v20.0.0. Returns non-zero for
# unparseable input; callers must skip, never guess.
peer_range_major() {
  local range="$1"
  [[ "$range" =~ (v?)([0-9]+) ]] || return 1
  printf '%s\n' "${BASH_REMATCH[2]}"
}

# Dependabot security bumps: the gh call is the one soften point in deps — a
# failure warns and skips the sub-step while the rest of the phase continues.
dependabot_bumps() {
  local alerts pkgs pkg
  if ! alerts="$(fetch_dependabot_alerts)"; then
    warn "deps: gh dependabot alerts unavailable — skipping security bumps"
    return 0
  fi
  pkgs="$(printf '%s' "$alerts" | dependabot_pkgs)"
  while IFS= read -r pkg; do
    [[ -n "$pkg" ]] || continue
    run yarn up "${pkg}@latest"
  done <<<"$pkgs"
}

# The gh call is stubbed in specs by shadowing this name directly.
fetch_dependabot_alerts() {
  gh api "/repos/$GH_REPO/dependabot/alerts?state=open" --paginate
}

# selector: transitive
phase_transitive() {
  run yarn up -R '*' || return 1
  run yarn dedupe
  run yarn install
  log "transitive: phase complete"
}
