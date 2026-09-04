#!/usr/bin/env bash
# scripts/specs/deps.spec.bash — spec for scripts/lib/deps.bash (deps + transitive
# phases). All mocks live inside subshells so they can't leak into the combined
# runner, and die/exit can't escape them.
# Standalone: bash scripts/specs/deps.spec.bash
set -u
SPEC_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/specs/test-utils.bash
source "$SPEC_DIR/test-utils.bash"
# shellcheck source=scripts/lib/deps.bash
source "$SPEC_DIR/../lib/deps.bash"
# The sourced lib hardens IFS; restore the default for spec-internal string ops.
IFS=$' \t\n'

dtmp="$(mktemp -d)"
trap 'rm -rf "$dtmp"' EXIT

# --- fetch_dependabot_alerts (production gh wiring via PATH stub, in a subshell) ---
ghstub="$(mktemp -d)"
printf '#!/usr/bin/env sh\nprintf "%%s\\n" "$*" >> "$0.args"\n' > "$ghstub/gh"
chmod +x "$ghstub/gh"
rc=0
(
  PATH="$ghstub:$PATH"
  export GH_REPO="exchgr/exch.gr"
  fetch_dependabot_alerts >/dev/null
) || rc=$?
assert_status "$rc" 0 "fetch_dependabot_alerts succeeds via the gh PATH stub"
assert_eq "$(cat "$ghstub/gh.args")" "api /repos/exchgr/exch.gr/dependabot/alerts?state=open --paginate" \
  "fetch_dependabot_alerts invokes gh api with the open-state paginate query against GH_REPO"
rm -rf "$ghstub"

# --- fetch_strapi_peer_deps (production yarn wiring via PATH stub, in a subshell) ---
yarnstub="$(mktemp -d)"
cat > "$yarnstub/yarn" <<'EOF'
#!/usr/bin/env sh
printf '%s\n' "$*" >> "$0.args"
printf '%s\n' '{"peerDependencies":{"react":"^19.0.0","react-dom":"^19.0.0","react-router-dom":"^6.30.3"}}'
EOF
chmod +x "$yarnstub/yarn"
rc=0
(
  PATH="$yarnstub:$PATH"
  fetch_strapi_peer_deps
) > "$yarnstub/out" || rc=$?
assert_status "$rc" 0 "fetch_strapi_peer_deps succeeds via the yarn npm info PATH stub"
assert_eq "$(cat "$yarnstub/yarn.args")" "npm info @strapi/strapi@latest --fields peerDependencies --json" \
  "fetch_strapi_peer_deps queries registry-fresh peerDependencies of @strapi/strapi@latest"
assert_eq "$(cat "$yarnstub/out")" $'react=^19.0.0\nreact-dom=^19.0.0\nreact-router-dom=^6.30.3' \
  "fetch_strapi_peer_deps extracts the whole react-family peer set from the npm metadata"
rm -rf "$yarnstub"

# --- peer_range_major (pure): base major from a strapi react peer range ---
assert_eq "$(peer_range_major '^18.0.0')" "18" "peer_range_major caret range ^18.0.0 -> 18"
assert_eq "$(peer_range_major '~19.2.1')" "19" "peer_range_major tilde range ~19.2.1 -> 19"
assert_eq "$(peer_range_major '18.3.1')" "18" "peer_range_major exact range 18.3.1 -> 18"
assert_eq "$(peer_range_major '>=18')" "18" "peer_range_major gte range >=18 -> 18"
assert_eq "$(peer_range_major '>=18 <20')" "18" "peer_range_major compound range >=18 <20 -> first token 18"
assert_eq "$(peer_range_major 'v20.0.0')" "20" "peer_range_major v-prefixed range v20.0.0 -> 20"
assert_eq "$(peer_range_major '^17.0.0 || ^18.0.0')" "18" \
  "peer_range_major OR-compound range ^17.0.0 || ^18.0.0 -> highest alternative 18"
assert_eq "$(peer_range_major '^17.0.0 || ^18.0.0 || ^19.0.0')" "19" \
  "peer_range_major three-way OR-compound range -> highest alternative 19"
prc=0
pout="$(peer_range_major 'banana')" || prc=$?
assert_status "$prc" 1 "peer_range_major garbage range returns non-zero (skip contract)"
assert_eq "$pout" "" "peer_range_major garbage range prints nothing"

# --- peer_of (pure): extract one dep's range from the peers block ---
assert_eq "$(peer_of $'react=^17.0.0 || ^18.0.0\nreact-dom=^18.0.0' 'react')" '^17.0.0 || ^18.0.0' \
  "peer_of extracts the dep's own range from the dep=range block"
assert_eq "$(peer_of 'react-dom=^18.0.0' 'react')" "" \
  "peer_of returns empty for an absent dep (no prefix match against react-dom)"

# --- declared_range: the dep's range from the fixture repo's package.json ---
mkdir -p "$dtmp/declared"
printf '{"dependencies":{"react":"^18.0.0"}}\n' > "$dtmp/declared/package.json"
assert_eq "$(REPO_DIR="$dtmp/declared" declared_range react)" "^18.0.0" \
  "declared_range reads the dep's range from package.json"
assert_eq "$(REPO_DIR="$dtmp/declared" declared_range vue)" "" \
  "declared_range returns empty for an undeclared dep"

# --- parse_version_field (pure): the version field from yarn npm info output ---
assert_eq "$(printf '%s\n' '{"name":"react-router-dom","version":"6.30.6"}' | parse_version_field)" "6.30.6" \
  "parse_version_field extracts the version from yarn npm info --fields version --json output"
assert_eq "$(printf '%s\n' '{"name":"react-router-dom"}' | parse_version_field)" "" \
  "parse_version_field returns empty when no version field is present"

# --- latest_matching_version (production yarn wiring via PATH stub, in a subshell) ---
verstub="$(mktemp -d)"
cat > "$verstub/yarn" <<'EOF'
#!/usr/bin/env sh
printf '%s\n' "$*" >> "$0.args"
printf '%s\n' '{"name":"react-router-dom","version":"6.30.6"}'
EOF
chmod +x "$verstub/yarn"
rc=0
(
  PATH="$verstub:$PATH"
  latest_matching_version 'react-router-dom@^6'
) > "$verstub/out" || rc=$?
assert_status "$rc" 0 "latest_matching_version succeeds via the yarn npm info PATH stub"
assert_eq "$(cat "$verstub/yarn.args")" "npm info react-router-dom@^6 --fields version --json" \
  "latest_matching_version queries the registry for the newest release matching the range"
assert_eq "$(cat "$verstub/out")" "6.30.6" \
  "latest_matching_version prints the latest version matching the range"
rm -rf "$verstub"

# --- reconcile_strapi_react: OR-compound peers align the whole react family ---
mkdir -p "$dtmp/recon-or"
printf '{"dependencies":{"react":"^17.0.0","react-dom":"^19.2.8","react-router-dom":"^7.18.3"}}\n' > "$dtmp/recon-or/package.json"
recon_or_calls="$dtmp/recon-or-calls"
: > "$recon_or_calls"
(
  run() { printf '%s\n' "$*" >> "$recon_or_calls"; }
  fetch_strapi_peer_deps() { printf 'react=^17.0.0 || ^18.0.0\nreact-dom=^17.0.0 || ^18.0.0\nreact-router-dom=^6.30.3\n'; }
  # Seam stub, subshell-scoped per the header contract: newest release of
  # each peer-accepted major.
  latest_matching_version() {
    case "$1" in
      react@^18) printf '18.3.1' ;;
      react-dom@^18) printf '18.3.1' ;;
      react@^19) printf '19.2.0' ;;
      react-router-dom@^6) printf '6.30.6' ;;
      *) return 1 ;;
    esac
  }
  REPO_DIR="$dtmp/recon-or" reconcile_strapi_react
)
assert_eq "$(cat "$recon_or_calls")" \
  $'yarn up react@^18.3.1\nyarn up react-dom@^18.3.1\nyarn up react-router-dom@^6.30.6\nyarn install' \
  "reconcile_strapi_react on OR-compound peers floats react/react-dom to the latest 18.x, caps react-router-dom to the latest 6.x, then installs once"

# --- reconcile_strapi_react: peer ^19 + react ^18 -> yarn up react@^19.0.0 + yarn install ---
mkdir -p "$dtmp/recon-up"
printf '{"dependencies":{"react":"^18.0.0"}}\n' > "$dtmp/recon-up/package.json"
recon_calls="$dtmp/recon-up-calls"
: > "$recon_calls"
(
  run() { printf '%s\n' "$*" >> "$recon_calls"; }
  fetch_strapi_peer_deps() { printf 'react=^19.0.0\n'; }
  # Same seam stub, subshell-scoped per the header contract.
  latest_matching_version() {
    case "$1" in
      react@^18) printf '18.3.1' ;;
      react-dom@^18) printf '18.3.1' ;;
      react@^19) printf '19.2.0' ;;
      react-router-dom@^6) printf '6.30.6' ;;
      *) return 1 ;;
    esac
  }
  REPO_DIR="$dtmp/recon-up" reconcile_strapi_react
)
assert_eq "$(cat "$recon_calls")" $'yarn up react@^19.2.0\nyarn install' \
  "reconcile_strapi_react on peer ^19 vs react ^18 records yarn up react@^19.2.0 then yarn install"

# --- reconcile_strapi_react: unresolvable latest -> falls back to the ^major.0.0 floor ---
mkdir -p "$dtmp/recon-fallback"
printf '{"dependencies":{"react":"^18.0.0"}}\n' > "$dtmp/recon-fallback/package.json"
recon_fallback_calls="$dtmp/recon-fallback-calls"
recon_fallback_err="$dtmp/recon-fallback-err"
: > "$recon_fallback_calls"
(
  run() { printf '%s\n' "$*" >> "$recon_fallback_calls"; }
  fetch_strapi_peer_deps() { printf 'react=^19.0.0\n'; }
  latest_matching_version() { return 1; }
  {
    REPO_DIR="$dtmp/recon-fallback" reconcile_strapi_react
  } 2> "$recon_fallback_err"
)
assert_eq "$(cat "$recon_fallback_calls")" $'yarn up react@^19.0.0\nyarn install' \
  "reconcile_strapi_react with an unresolvable latest falls back to the ^major.0.0 floor bump"
assert_eq "$(grep -c 'could not resolve latest react@^19' "$recon_fallback_err")" "1" \
  "reconcile_strapi_react warns when falling back to the floor bump"

# --- reconcile_strapi_react: react already at peer major -> no-op ---
mkdir -p "$dtmp/recon-noop"
printf '{"dependencies":{"react":"^18.2.1","react-dom":"^18.3.1","react-router-dom":"^6.30.3"}}\n' > "$dtmp/recon-noop/package.json"
recon_noop_calls="$dtmp/recon-noop-calls"
: > "$recon_noop_calls"
(
  run() { printf '%s\n' "$*" >> "$recon_noop_calls"; }
  fetch_strapi_peer_deps() { printf 'react=^17.0.0 || ^18.0.0\nreact-dom=^17.0.0 || ^18.0.0\nreact-router-dom=^6.30.3\n'; }
  REPO_DIR="$dtmp/recon-noop" reconcile_strapi_react
)
assert_eq "$(cat "$recon_noop_calls")" "" \
  "reconcile_strapi_react with every react-family dep already at its peer major records no yarn calls (no-op)"

# --- reconcile_strapi_react: empty peer range -> no-op + skip log ---
recon_empty_calls="$dtmp/recon-empty-calls"
recon_empty_log="$dtmp/recon-empty-log"
: > "$recon_empty_calls"
(
  run() { printf '%s\n' "$*" >> "$recon_empty_calls"; }
  fetch_strapi_peer_deps() { return 1; }
  REPO_DIR="$dtmp/recon-noop" reconcile_strapi_react
) > "$recon_empty_log"
assert_eq "$(cat "$recon_empty_calls")" "" \
  "reconcile_strapi_react with an empty peer range records no yarn calls"
assert_eq "$(grep -c 'no react-family peer ranges found — skipping reconcile' "$recon_empty_log")" "1" \
  "reconcile_strapi_react with an empty peer range logs the skip"

# --- reconcile_strapi_react: unparseable peer range -> no-op + warn ---
recon_bad_calls="$dtmp/recon-bad-calls"
recon_bad_err="$dtmp/recon-bad-err"
: > "$recon_bad_calls"
(
  run() { printf '%s\n' "$*" >> "$recon_bad_calls"; }
  fetch_strapi_peer_deps() { printf 'react=banana\n'; }
  REPO_DIR="$dtmp/recon-noop" reconcile_strapi_react
) 2> "$recon_bad_err" > /dev/null
assert_eq "$(cat "$recon_bad_calls")" "" \
  "reconcile_strapi_react with an unparseable peer range records no yarn calls"
assert_eq "$(grep -c 'unparseable react peer range' "$recon_bad_err")" "1" \
  "reconcile_strapi_react with an unparseable peer range warns"

# --- reconcile_dep hard-fail contract: a failing bump dies, install never runs ---
mkdir -p "$dtmp/bumpfail"
printf '{"dependencies":{"react":"^18.0.0"}}\n' > "$dtmp/bumpfail/package.json"
bumpfail_calls="$dtmp/bumpfail-calls"
bumpfail_err="$dtmp/bumpfail-err"
: > "$bumpfail_calls"
bf_rc=0
(
  run() {
    printf '%s\n' "$*" >> "$bumpfail_calls"
    [[ "$*" == 'yarn up react@^19.2.0' ]] && return 1
    return 0
  }
  fetch_strapi_peer_deps() { printf 'react=^19.0.0\n'; }
  # Same seam stub, subshell-scoped per the header contract.
  latest_matching_version() {
    case "$1" in
      react@^18) printf '18.3.1' ;;
      react@^19) printf '19.2.0' ;;
      *) return 1 ;;
    esac
  }
  {
    REPO_DIR="$dtmp/bumpfail" reconcile_strapi_react
  } 2> "$bumpfail_err"
) || bf_rc=$?
assert_status "$bf_rc" 1 "reconcile_dep dies when the yarn up bump fails"
assert_contains "$(cat "$bumpfail_err")" "deps: failed to bump react to ^19.2.0" \
  "reconcile_dep names the failed dep and range"
assert_eq "$(cat "$bumpfail_calls")" "yarn up react@^19.2.0" \
  "reconcile_dep records nothing after the failed bump (no lazy yarn install)"

# --- latest_version_of (production yarn wiring via PATH stub, in a subshell) ---
lvstub="$(mktemp -d)"
cat > "$lvstub/yarn" <<'EOF'
#!/usr/bin/env sh
printf '%s\n' "$*" >> "$0.args"
printf '%s\n' '{"name":"qs","version":"6.15.3"}'
EOF
chmod +x "$lvstub/yarn"
rc=0
(
  PATH="$lvstub:$PATH"
  latest_version_of qs
) > "$lvstub/out" || rc=$?
assert_status "$rc" 0 "latest_version_of succeeds via the yarn npm info PATH stub"
assert_eq "$(cat "$lvstub/yarn.args")" "npm info qs@latest --fields version --json" \
  "latest_version_of queries the registry for the newest release of the package"
assert_eq "$(cat "$lvstub/out")" "6.15.3" \
  "latest_version_of prints the package's latest version"
rm -rf "$lvstub"

# --- bump_package: declared pkg -> yarn up @latest ---
mkdir -p "$dtmp/bump-declared"
printf '{"dependencies":{"react":"^18.2.1"}}\n' > "$dtmp/bump-declared/package.json"
bump_declared_calls="$dtmp/bump-declared-calls"
: > "$bump_declared_calls"
(
  run() { printf '%s\n' "$*" >> "$bump_declared_calls"; }
  REPO_DIR="$dtmp/bump-declared" bump_package react
)
assert_eq "$(cat "$bump_declared_calls")" "yarn up react@latest" \
  "bump_package bumps a package declared in package.json with yarn up @latest"

# --- bump_package: transitive-only pkg -> yarn set resolution to the latest version ---
mkdir -p "$dtmp/bump-transitive"
printf '{"dependencies":{"react":"^18.2.1"}}\n' > "$dtmp/bump-transitive/package.json"
bump_transitive_calls="$dtmp/bump-transitive-calls"
: > "$bump_transitive_calls"
(
  run() { printf '%s\n' "$*" >> "$bump_transitive_calls"; }
  latest_version_of() { printf '6.15.3'; }
  REPO_DIR="$dtmp/bump-transitive" bump_package qs
)
assert_eq "$(cat "$bump_transitive_calls")" "yarn set resolution qs@npm:* npm:6.15.3" \
  "bump_package forces a transitive-only package's lockfile resolution to its latest version (yarn 4 set resolution syntax)"

# --- bump_package: unresolvable latest -> warn + skip, no run calls, no die ---
mkdir -p "$dtmp/bump-lookup-fail"
printf '{"dependencies":{"react":"^18.2.1"}}\n' > "$dtmp/bump-lookup-fail/package.json"
bump_lookup_calls="$dtmp/bump-lookup-fail-calls"
bump_lookup_err="$dtmp/bump-lookup-fail-err"
: > "$bump_lookup_calls"
bump_lookup_rc=0
(
  run() { printf '%s\n' "$*" >> "$bump_lookup_calls"; }
  latest_version_of() { return 1; }
  {
    REPO_DIR="$dtmp/bump-lookup-fail" bump_package qs
  } 2> "$bump_lookup_err"
) || bump_lookup_rc=$?
assert_status "$bump_lookup_rc" 0 \
  "bump_package on a failed latest lookup skips the package instead of dying (soft-fail step)"
assert_eq "$(cat "$bump_lookup_calls")" "" \
  "bump_package on a failed latest lookup records no run calls for that package"
assert_contains "$(cat "$bump_lookup_err")" "could not resolve latest qs" \
  "bump_package warns when it skips a transitive bump over a failed latest lookup"

# --- dependabot_bumps: declared + transitive-only alerts get their class-correct bumps ---
mkdir -p "$dtmp/depbumps"
printf '{"dependencies":{"react":"^18.2.1"}}\n' > "$dtmp/depbumps/package.json"
depbumps_calls="$dtmp/depbumps-calls"
: > "$depbumps_calls"
(
  run() { printf '%s\n' "$*" >> "$depbumps_calls"; }
  fetch_dependabot_alerts() { printf '%s\n' '[{"state":"open","dependency":{"package":{"name":"react"}}},{"state":"open","dependency":{"package":{"name":"qs"}}}]'; }
  latest_version_of() { printf '6.15.3'; }
  REPO_DIR="$dtmp/depbumps" dependabot_bumps
)
assert_eq "$(cat "$depbumps_calls")" $'yarn set resolution qs@npm:* npm:6.15.3\nyarn up react@latest' \
  "dependabot_bumps bumps declared packages with yarn up and transitive-only packages with yarn set resolution (sorted alert order)"

# --- react_family_names (pure): the names reconcile owns, from the peers block ---
assert_eq "$(react_family_names $'react=^17.0.0 || ^18.0.0\nreact-dom=^18.0.0\nreact-router-dom=^6.30.3')" \
  $'react\nreact-dom\nreact-router-dom' \
  "react_family_names extracts every dep name from the dep=range peers block"
assert_eq "$(react_family_names '')" "" "react_family_names of an empty peers block names nothing"
assert_eq "$(react_family_names 'garbage line')" "" \
  "react_family_names skips lines without a dep=range shape"

# --- blanket_up_args (pure): declared deps minus the family, as <dep>@latest ---
assert_eq "$(blanket_up_args $'@strapi/strapi\nreact\npg' 'react')" $'@strapi/strapi@latest\npg@latest' \
  "blanket_up_args drops exactly the excluded dep and adds @latest to the rest"
assert_eq "$(blanket_up_args $'react\nreact-dom' 'react')" $'react-dom@latest' \
  "blanket_up_args matches exclusions exactly (react does not exclude react-dom)"
assert_eq "$(blanket_up_args $'pg\nstyled-components' '')" $'pg@latest\nstyled-components@latest' \
  "blanket_up_args with an empty exclusion list covers every declared dep"
assert_eq "$(blanket_up_args 'react' $'react\nreact-dom')" "" \
  "blanket_up_args with every dep excluded names nothing (no blanket run)"

# --- declared_deps: the declared top-level dependency names ---
mkdir -p "$dtmp/declared-deps"
printf '{"dependencies":{"react":"^18.0.0","@strapi/strapi":"^5.0.0"}}\n' > "$dtmp/declared-deps/package.json"
assert_eq "$(REPO_DIR="$dtmp/declared-deps" declared_deps)" $'@strapi/strapi\nreact' \
  "declared_deps lists the manifest's dependency names"

# --- phase_deps happy path (recorder run + fixture alerts via the seam, in a subshell) ---
# Fixture: @strapi/strapi duplicated, qs open, nanoid dismissed. dependabot_pkgs
# (reused from helpers.bash) must dedupe to the sorted open set.
dep_fixture='[{"state":"open","dependency":{"package":{"name":"@strapi/strapi"}}},{"state":"open","dependency":{"package":{"name":"qs"}}},{"state":"open","dependency":{"package":{"name":"@strapi/strapi"}}},{"state":"dismissed","dependency":{"package":{"name":"nanoid"}}}]'
# Fixture package.json: react one major behind the stubbed strapi peer range so
# the reconcile step actually fires (yarn up react + its lazy install) inside
# the composition; @strapi/strapi is declared like the real repo so its
# dependabot alert classifies as a direct bump.
printf '{"dependencies":{"react":"^18.0.0","@strapi/strapi":"^5.0.0"}}\n' > "$dtmp/package.json"
dep_calls="$dtmp/dep-calls"
: > "$dep_calls"
deps_out="$(
  run() { printf '%s\n' "$*" >> "$dep_calls"; }
  fetch_dependabot_alerts() { printf '%s\n' "$dep_fixture"; }
  fetch_strapi_peer_deps() { printf 'react=^19.0.0\n'; }
  # Same seam stub, subshell-scoped per the header contract.
  latest_matching_version() {
    case "$1" in
      react@^18) printf '18.3.1' ;;
      react@^19) printf '19.2.0' ;;
      *) return 1 ;;
    esac
  }
  # Transitive-only dependabot alerts resolve their latest through this seam;
  # qs is transitive in the fixture package.json (only react is declared).
  latest_version_of() { printf '6.15.3'; }
  REPO_DIR="$dtmp" phase_deps
)"
assert_eq "$(cat "$dep_calls")" $'yarn up @strapi/strapi@latest\nyarn up @strapi/strapi@latest @strapi/plugin-graphql@latest @strapi/plugin-users-permissions@latest\nyarn up react@^19.2.0\nyarn install\nyarn up @strapi/strapi@latest\nyarn set resolution qs@npm:* npm:6.15.3\nyarn install' \
  "phase_deps excludes the react family from the blanket float (react is never offered to yarn up *, only to the reconcile), runs the strapi trio, reconcile up + lazy install, deduped+ordered dependabot ups (declared -> yarn up, transitive-only -> set resolution), final yarn install"

# --- phase_deps exclusion: the family is owned by the reconcile, in any order ---
# The blanket float never sees the react family at all, so no ordering between
# the blanket bump and the reconcile matters: react's declared range is never
# rewritten by the blanket, whether or not the reconcile had anything to do.
# With react the ONLY declared dep the blanket enumeration is empty (no yarn up
# at all); the trio and the final install still run.
mkdir -p "$dtmp/pinned"
printf '{"dependencies":{"react":"^18.2.1"}}\n' > "$dtmp/pinned/package.json"
pinned_calls="$dtmp/pinned-calls"
: > "$pinned_calls"
(
  run() { printf '%s\n' "$*" >> "$pinned_calls"; }
  fetch_dependabot_alerts() { printf '[]\n'; }
  fetch_strapi_peer_deps() { printf 'react=^18.0.0\n'; }
  REPO_DIR="$dtmp/pinned" phase_deps
)
assert_eq "$(cat "$pinned_calls")" $'yarn up @strapi/strapi@latest @strapi/plugin-graphql@latest @strapi/plugin-users-permissions@latest\nyarn install' \
  "phase_deps with react the only declared dep records no blanket up at all (family excluded, reconcile is a no-op), just the trio and install"
assert_eq "$(REPO_DIR="$dtmp/pinned" declared_range react)" "^18.2.1" \
  "phase_deps never rewrites the declared react range with the blanket float (the family is excluded from it, ordering-independent)"

# --- phase_deps exclusion: an unparseable family peer range still excludes the family ---
# Family membership comes from the peers block's NAMES, not from whether each
# range parses: the family is owned by the reconcile whatever the reconcile
# decides (including its skip path), so react is excluded from the blanket
# even with a garbage peer range, while pg still floats.
mkdir -p "$dtmp/badpeer"
printf '{"dependencies":{"react":"^18.2.1","pg":"^8.0.0"}}\n' > "$dtmp/badpeer/package.json"
badpeer_calls="$dtmp/badpeer-calls"
badpeer_err="$dtmp/badpeer-err"
: > "$badpeer_calls"
(
  run() { printf '%s\n' "$*" >> "$badpeer_calls"; }
  fetch_dependabot_alerts() { printf '[]\n'; }
  fetch_strapi_peer_deps() { printf 'react=banana\n'; }
  {
    REPO_DIR="$dtmp/badpeer" phase_deps
  } 2> "$badpeer_err"
)
assert_eq "$(cat "$badpeer_calls")" $'yarn up pg@latest\nyarn up @strapi/strapi@latest @strapi/plugin-graphql@latest @strapi/plugin-users-permissions@latest\nyarn install' \
  "phase_deps excludes react from the blanket float even with an unparseable peer range (pg still floats), and the reconcile skips react with a warn"
assert_contains "$(cat "$badpeer_err")" "unparseable react peer range" \
  "phase_deps surfaces the reconcile's unparseable-peer-range warn for the excluded family member"

# --- phase_deps exclusion: no peer data -> the blanket covers every declared dep ---
# With the peer-deps seam unavailable the exclusion list is empty, so the
# blanket enumeration includes the whole manifest (including react); the
# reconcile logs its skip. Accepted edge: the family only ever moves back in
# range via the reconcile, which is exactly what a later deps run does.
mkdir -p "$dtmp/nopeers"
printf '{"dependencies":{"react":"^18.2.1","@strapi/strapi":"^5.0.0"}}\n' > "$dtmp/nopeers/package.json"
nopeers_calls="$dtmp/nopeers-calls"
nopeers_log="$dtmp/nopeers-log"
: > "$nopeers_calls"
(
  run() { printf '%s\n' "$*" >> "$nopeers_calls"; }
  fetch_dependabot_alerts() { printf '[]\n'; }
  fetch_strapi_peer_deps() { return 1; }
  REPO_DIR="$dtmp/nopeers" phase_deps
) > "$nopeers_log"
assert_eq "$(cat "$nopeers_calls")" $'yarn up @strapi/strapi@latest react@latest\nyarn up @strapi/strapi@latest @strapi/plugin-graphql@latest @strapi/plugin-users-permissions@latest\nyarn install' \
  "phase_deps with no peer data records a blanket up covering every declared dep (empty exclusion list) and skips the reconcile"
assert_eq "$(grep -c 'no react-family peer ranges found — skipping reconcile' "$nopeers_log")" "1" \
  "phase_deps with no peer data logs the reconcile skip"

# --- phase_deps with gh failure: warn + skip dependabot, keep the rest of the phase ---
gh_fail_calls="$dtmp/gh-fail-calls"
gh_fail_err="$dtmp/gh-fail-err"
: > "$gh_fail_calls"
(
  run() { printf '%s\n' "$*" >> "$gh_fail_calls"; }
  fetch_dependabot_alerts() { return 1; }
  fetch_strapi_peer_deps() { printf 'react=^18.0.0\n'; }
  {
    REPO_DIR="$dtmp" phase_deps
  } 2> "$gh_fail_err"
)
assert_eq "$(cat "$gh_fail_calls")" $'yarn up @strapi/strapi@latest\nyarn up @strapi/strapi@latest @strapi/plugin-graphql@latest @strapi/plugin-users-permissions@latest\nyarn install' \
  "phase_deps on gh failure still records the blanket up (react excluded), strapi trio, and yarn install (no dependabot ups)"
assert_eq "$(grep -c 'skipping security bumps' "$gh_fail_err")" "1" \
  "phase_deps on gh failure warns about skipping the security bumps"

# --- phase_deps with zero open alerts: no dependabot ups, phase still completes ---
empty_calls="$dtmp/empty-calls"
: > "$empty_calls"
(
  run() { printf '%s\n' "$*" >> "$empty_calls"; }
  fetch_dependabot_alerts() { printf '[]\n'; }
  fetch_strapi_peer_deps() { printf 'react=^18.0.0\n'; }
  REPO_DIR="$dtmp" phase_deps
)
assert_eq "$(cat "$empty_calls")" $'yarn up @strapi/strapi@latest\nyarn up @strapi/strapi@latest @strapi/plugin-graphql@latest @strapi/plugin-users-permissions@latest\nyarn install' \
  "phase_deps with zero open alerts records no dependabot ups and still ends with yarn install"

# --- phase_transitive happy path (recorder run, in a subshell) ---
happy_calls="$dtmp/happy-calls"
: > "$happy_calls"
(
  run() { printf '%s\n' "$*" >> "$happy_calls"; }
  REPO_DIR="$dtmp" phase_transitive
)
assert_eq "$(cat "$happy_calls")" $'yarn up -R *\nyarn dedupe\nyarn install' \
  "phase_transitive records: yarn up -R *, yarn dedupe, yarn install"

# --- phase_transitive hard failure: wildcard -R fails -> propagates, nothing further runs ---
tf_calls="$dtmp/tf-calls"
: > "$tf_calls"
tf_rc=0
(
  run() {
    printf '%s\n' "$*" >> "$tf_calls"
    [[ "$*" == 'yarn up -R *' ]] && return 1
    return 0
  }
  REPO_DIR="$dtmp" phase_transitive
) || tf_rc=$?
assert_status "$tf_rc" 1 \
  "phase_transitive propagates a failing wildcard -R as a hard error (no fallback)"
assert_eq "$(cat "$tf_calls")" "yarn up -R *" \
  "phase_transitive records nothing after a failing wildcard -R (no per-package -R, no dedupe, no install)"

# Bottom guard: standalone run prints totals; sourced run defers to the runner.
finish_spec
