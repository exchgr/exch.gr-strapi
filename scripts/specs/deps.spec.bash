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

# --- phase_deps happy path (recorder run + fixture alerts via the seam, in a subshell) ---
# Fixture: @strapi/strapi duplicated, qs open, nanoid dismissed. dependabot_pkgs
# (reused from helpers.bash) must dedupe to the sorted open set.
dep_fixture='[{"state":"open","dependency":{"package":{"name":"@strapi/strapi"}}},{"state":"open","dependency":{"package":{"name":"qs"}}},{"state":"open","dependency":{"package":{"name":"@strapi/strapi"}}},{"state":"dismissed","dependency":{"package":{"name":"nanoid"}}}]'
# Fixture package.json: react one major behind the stubbed strapi peer range so
# the reconcile step actually fires (yarn up react + its lazy install) inside
# the composition.
printf '{"dependencies":{"react":"^18.0.0"}}\n' > "$dtmp/package.json"
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
  REPO_DIR="$dtmp" phase_deps
)"
assert_eq "$(cat "$dep_calls")" $'yarn up *\nyarn up @strapi/strapi@latest @strapi/plugin-graphql@latest @strapi/plugin-users-permissions@latest\nyarn up react@^19.2.0\nyarn install\nyarn up @strapi/strapi@latest\nyarn up qs@latest\nyarn install' \
  "phase_deps records: yarn up *, strapi trio, react reconcile (up + lazy install), deduped+ordered dependabot ups, final yarn install"

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
assert_eq "$(cat "$gh_fail_calls")" $'yarn up *\nyarn up @strapi/strapi@latest @strapi/plugin-graphql@latest @strapi/plugin-users-permissions@latest\nyarn install' \
  "phase_deps on gh failure still records yarn up *, strapi trio, and yarn install (no dependabot ups)"
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
assert_eq "$(cat "$empty_calls")" $'yarn up *\nyarn up @strapi/strapi@latest @strapi/plugin-graphql@latest @strapi/plugin-users-permissions@latest\nyarn install' \
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
