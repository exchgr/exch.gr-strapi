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
  # The react-family reconcile runs FIRST — before the blanket float — so the
  # family's declared ranges are already pinned to the peer-accepted major when
  # `yarn up '*'` runs. A range-constrained blanket float can then never cross
  # the family's majors, which kills the float-then-correct dance (and its
  # YN0060 non-overlapping-range warnings) and removes the blast radius of the
  # reconcile dying mid-way: the erroneous major bumps no longer exist to be
  # cleaned up, because they never happen.
  #
  # No drift between the pre-float peer lookup and the trio bump below: both
  # query `@latest` from the registry (fetch_strapi_peer_deps reads
  # @strapi/strapi@latest/@strapi/admin@latest; the trio bump targets
  # @latest too), and the two steps run back-to-back within one phase. Strapi
  # publishing a new latest between them would require a registry change
  # mid-phase; even then the next deps run re-reconciles against the new peer
  # ranges, so the family never lands out of range permanently. The reconcile
  # target therefore always derives from strapi's peer range, never from the
  # locally installed strapi version — coherent with reconcile_strapi_react's
  # registry-fresh design.
  reconcile_strapi_react || return $?
  run yarn up '*'
  run yarn up '@strapi/strapi@latest' '@strapi/plugin-graphql@latest' '@strapi/plugin-users-permissions@latest'
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

# Resolve one dep's desired range against the strapi peer ranges in $2 with
# its currently declared range $3: skip (return 1, no output) when the dep
# has no peer entry, the peer range is unparseable, or the declared range
# already sits in the peer-accepted major (no-op); otherwise print
# `^<latest release in the target major>`, falling back to the
# `^<target>.0.0` floor (with a warn) when the registry lookup fails. Skips
# log/warn their reason. Pure except for the latest_matching_version seam,
# which specs shadow.
desired_range_for() {
  local dep="$1" peers="$2" current="$3" peer target latest
  peer="$(peer_of "$peers" "$dep")"
  if [[ -z "$peer" ]]; then
    log "deps: no $dep peer range found — skipping"
    return 1
  fi
  if ! target="$(peer_range_major "$peer")"; then
    warn "deps: unparseable $dep peer range '$peer' — skipping"
    return 1
  fi
  if [[ "$(peer_range_major "$current")" == "$target" ]]; then
    log "deps: $dep '$current' already matches strapi peer range '$peer' — no-op"
    return 1
  fi
  if latest="$(latest_matching_version "$dep@^$target")" && [[ -n "$latest" ]]; then
    printf '^%s\n' "$latest"
  else
    warn "deps: could not resolve latest $dep@^$target — falling back to ^${target}.0.0"
    printf '^%s.0.0\n' "$target"
  fi
}

# Reconcile one dependency against its strapi peer range: resolve the
# declared range, resolve the desired range (desired_range_for), then
# `yarn up` to it. Returns 0 iff a bump was issued; skips return 1; a FAILED
# bump dies — a half-reconciled react family must not silently continue to
# later phases.
reconcile_dep() {
  current="$(declared_range "$dep")"
  if [[ -z "$current" ]]; then
    log "deps: $dep not declared in package.json — skipping reconcile"
    return 1
  fi
  if ! range="$(desired_range_for "$dep" "$peers" "$current")"; then
    return 1
  fi
  # Re-derive peer/target for the log; both are pure and cheap.
  local peer target
  peer="$(peer_of "$peers" "$dep")"
  target="$(peer_range_major "$range")"
  log "deps: strapi peer range '$peer' -> target major $target ($dep '$current' -> '$range')"
  # run now dies itself on failure ("command failed: ..."), so this die only
  # fires for run stubs that return non-zero without dying (spec seams); the
  # messages never double up.
  run yarn up "$dep@$range" || die "deps: failed to bump $dep to $range"
}

# Registry-fresh newest release matching a semver range (passed as
# "<dep>@^<major>"), so a reconcile bump pins the newest patch of the
# peer-accepted major instead of the ^X.0.0 floor. Specs shadow this name
# or stub yarn via PATH.
latest_matching_version() {
  yarn npm info "$1" --fields version --json 2>/dev/null | parse_version_field
}

# Pure: the "version" field from `yarn npm info --fields version --json`
# output. Empty when absent.
parse_version_field() {
  jq -r 'first(.. | objects | select(.version?) | .version) // empty'
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
# Per-package bumps are classified by bump_package; a failed per-package
# lookup is also soft (warn + skip that package), so one opaque package can
# never abort the security sweep.
dependabot_bumps() {
  local alerts pkgs pkg
  if ! alerts="$(fetch_dependabot_alerts)"; then
    warn "deps: gh dependabot alerts unavailable — skipping security bumps"
    return 0
  fi
  pkgs="$(printf '%s' "$alerts" | dependabot_pkgs)"
  while IFS= read -r pkg; do
    [[ -n "$pkg" ]] || continue
    bump_package "$pkg"
  done <<<"$pkgs"
}

# Bump one dependabot-alerted package by its dependency class:
# - declared in package.json -> `yarn up <pkg>@latest` (a direct dependency can
#   be floated normally);
# - transitive-only -> force the lockfile resolution to the latest release via
#   `yarn set resolution <pkg>@npm:* npm:<latest>` (yarn 4 syntax: the
#   resolution is `npm:`-prefixed). `yarn up` dies with a usage error on
#   packages no workspace references, so a bare up would abort the run — the
#   resolution override is the way to still honor the security intent for
#   transitive-only alerts. A failed latest lookup warns and skips the
#   package (soft-fail), never dies.
bump_package() {
  local pkg="$1" latest
  if [[ -n "$(declared_range "$pkg")" ]]; then
    run yarn up "${pkg}@latest"
    return 0
  fi
  if latest="$(latest_version_of "$pkg")" && [[ -n "$latest" ]]; then
    run yarn set resolution "${pkg}@npm:*" "npm:${latest}"
  else
    warn "deps: could not resolve latest $pkg — skipping transitive security bump"
  fi
}

# Registry-fresh latest release of a package. Specs shadow this name or stub
# yarn via PATH.
latest_version_of() {
  yarn npm info "$1@latest" --fields version --json 2>/dev/null | parse_version_field
}

# The gh call is stubbed in specs by shadowing this name directly.
fetch_dependabot_alerts() {
  gh api "/repos/$GH_REPO/dependabot/alerts?state=open" --paginate
}

# selector: transitive
phase_transitive() {
  # Same as above: production run dies itself; this return-guard covers
  # non-dying run stubs (spec seams) so the phase still fails loudly there.
  run yarn up -R '*' || return 1
  run yarn dedupe
  run yarn install
  log "transitive: phase complete"
}
