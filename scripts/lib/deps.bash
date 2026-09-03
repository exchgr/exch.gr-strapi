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
  reconcile_strapi_react || return $?
  dependabot_bumps
  run yarn install
  log "deps: phase complete"
}

# The react-family dependencies strapi constrains via peerDependencies. Each
# is reconciled independently against its own peer range: it floats (or is
# capped) to the highest major strapi accepts, never beyond. Strapi declares
# identical ranges for react and react-dom, which keeps the two on the same
# major — the exact match React requires. While strapi still accepts only 18
# this is a no-op for an ^18 project; when strapi allows 19 the next deps run
# picks the family up automatically.
STRAPI_PEER_DEPS=(react react-dom react-router-dom)

reconcile_strapi_react() {
  local peers dep moved=0
  if ! peers="$(fetch_strapi_peer_deps)" || [[ -z "$peers" ]]; then
    log "deps: no react-family peer ranges found — skipping reconcile"
    return 0
  fi
  for dep in "${STRAPI_PEER_DEPS[@]}"; do
    reconcile_dep "$dep" "$peers" && moved=1
  done
  if (( moved )); then
    # One install pays for the whole reconcile; phase_deps still ends with
    # its own final install.
    run yarn install
  fi
}

# Reconcile one dependency against its strapi peer range: no-op (with log)
# when the declared range's major already matches, otherwise `yarn up` to
# `^<target>.0.0`. Returns 0 iff a bump was issued; skips (missing peer,
# unparseable peer, undeclared dep) return 1; a FAILED bump dies — a
# half-reconciled react family must not silently continue to later phases.
reconcile_dep() {
  local dep="$1" peers="$2" peer target current current_major
  peer="$(peer_of "$peers" "$dep")"
  if [[ -z "$peer" ]]; then
    log "deps: no $dep peer range found — skipping"
    return 1
  fi
  if ! target="$(peer_range_major "$peer")"; then
    warn "deps: unparseable $dep peer range '$peer' — skipping"
    return 1
  fi
  current="$(declared_range "$dep")"
  if [[ -z "$current" ]]; then
    log "deps: $dep not declared in package.json — skipping reconcile"
    return 1
  fi
  current_major="$(peer_range_major "$current")" || current_major=""
  if [[ "$current_major" == "$target" ]]; then
    log "deps: $dep '$current' already matches strapi peer range '$peer' — no-op"
    return 1
  fi
  log "deps: strapi peer range '$peer' -> target major $target ($dep '$current' -> '^${target}.0.0')"
  run yarn up "$dep@^${target}.0.0" || die "deps: failed to bump $dep to ^${target}.0.0"
}

# Pure: the "dep=range" peers block + dep name -> the dep's peer range, empty
# when the dep has no peer entry. The anchor keeps "react" from matching
# "react-dom" (dep names are fixed literals without regex metacharacters).
peer_of() {
  printf '%s\n' "$1" | sed -n "s/^$2=//p" | head -n1
}

# The range declared for $1 in the repo's package.json — empty when
# undeclared. Reads a file, but is side-effect-free.
declared_range() {
  jq -r ".dependencies.\"$1\" // empty" "$REPO_DIR/package.json" 2>/dev/null
}

# Registry-fresh metadata after the trio upgrade. Every strapi package
# declares the same react-family peers, so one fetch serves the whole
# reconcile; the first package with a peerDependencies object wins. Bash
# functions are late-bound, so specs shadow this name directly to stub it.
fetch_strapi_peer_deps() {
  local pkg out
  for pkg in '@strapi/strapi' '@strapi/admin' '@strapi/plugin-graphql'; do
    if out="$(yarn npm info "${pkg}@latest" --fields peerDependencies --json 2>/dev/null | parse_strapi_peer_deps)" && [[ -n "$out" ]]; then
      printf '%s\n' "$out"
      return 0
    fi
  done
  return 1
}

parse_strapi_peer_deps() {
  # stdin: `yarn npm info <pkg> --fields peerDependencies --json` output
  # (shape tolerated either bare or wrapped). Prints one "dep=range" line per
  # react-family peer found in the first peerDependencies-bearing object.
  jq -r '(first(.. | objects | select(.peerDependencies?) | .peerDependencies) // {}) | to_entries[]
    | select(.key == "react" or .key == "react-dom" or .key == "react-router-dom")
    | "\(.key)=\(.value)"'
}

# Pure: target major from a semver range — the HIGHEST base major across the
# range's `||` alternatives ("^17.0.0 || ^18.0.0" -> 18); a single alternative
# takes its first number token (^18.0.0 -> 18, ~19.2.1 -> 19, >=18 -> 18,
# v20.0.0 -> 20). Returns non-zero for unparseable input; callers must skip,
# never guess.
peer_range_major() {
  local range="$1" alt best candidate
  best=""
  while IFS= read -r alt; do
    [[ "$alt" =~ (v?)([0-9]+) ]] || continue
    candidate="${BASH_REMATCH[2]}"
    if [[ -z "$best" ]] || (( candidate > best )); then
      best="$candidate"
    fi
  done <<<"${range//||/$'\n'}"
  [[ -n "$best" ]] || return 1
  printf '%s\n' "$best"
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
