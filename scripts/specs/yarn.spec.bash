#!/usr/bin/env bash
# scripts/specs/yarn.spec.bash — spec for scripts/lib/yarn.bash (yarn phase).
# Standalone: bash scripts/specs/yarn.spec.bash
set -u
SPEC_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/specs/test-utils.bash
source "$SPEC_DIR/test-utils.bash"
# shellcheck source=scripts/lib/yarn.bash
source "$SPEC_DIR/../lib/yarn.bash"
# The sourced lib hardens IFS; restore the default for spec-internal string ops.
IFS=$' \t\n'

# --- clean_stale_yarn_releases (real fs fixture in a temp REPO_DIR) ---
ytmp="$(mktemp -d)"
trap 'rm -rf "$ytmp"' EXIT

# Keeps the release yarnPath points at, deletes only the stale one.
# Nuance: yarnPath is relative while find emits absolute
# paths — only a basename comparison decides what survives.
mkdir -p "$ytmp/.yarn/releases"
printf 'current\n' > "$ytmp/.yarn/releases/yarn-4.18.0.cjs"
printf 'stale\n' > "$ytmp/.yarn/releases/yarn-3.9.1.cjs"
printf 'yarnPath: .yarn/releases/yarn-4.18.0.cjs\n' > "$ytmp/.yarnrc.yml"
( REPO_DIR="$ytmp" DRY_RUN=0 clean_stale_yarn_releases ) >/dev/null
assert_eq "$(ls "$ytmp/.yarn/releases" | grep -c 'yarn-4.18.0.cjs')" "1" \
  "clean_stale_yarn_releases keeps the file yarnPath points at (relative yarnPath vs absolute find path)"
assert_eq "$(ls "$ytmp/.yarn/releases" | grep -c 'yarn-3.9.1.cjs')" "0" \
  "clean_stale_yarn_releases deletes the stale release file"

# No .yarnrc.yml -> no-op, status 0, release untouched.
mkdir -p "$ytmp/norcss/.yarn/releases"
printf 'keep\n' > "$ytmp/norcss/.yarn/releases/yarn-4.18.0.cjs"
( REPO_DIR="$ytmp/norcss" DRY_RUN=0 clean_stale_yarn_releases ) >/dev/null
assert_status "$?" 0 "clean_stale_yarn_releases returns 0 without .yarnrc.yml"
assert_eq "$(ls "$ytmp/norcss/.yarn/releases")" "yarn-4.18.0.cjs" \
  "clean_stale_yarn_releases without .yarnrc.yml is a no-op"

# No .yarn/releases dir -> no-op, status 0.
mkdir -p "$ytmp/norel"
printf 'yarnPath: .yarn/releases/yarn-4.18.0.cjs\n' > "$ytmp/norel/.yarnrc.yml"
( REPO_DIR="$ytmp/norel" DRY_RUN=0 clean_stale_yarn_releases ) >/dev/null
assert_status "$?" 0 "clean_stale_yarn_releases returns 0 without .yarn/releases dir"

# yarnPath missing -> no-op, nothing deleted.
mkdir -p "$ytmp/nopath/.yarn/releases"
printf 'keep\n' > "$ytmp/nopath/.yarn/releases/yarn-4.18.0.cjs"
printf 'keep\n' > "$ytmp/nopath/.yarn/releases/yarn-3.9.1.cjs"
printf 'nodeLinker: node-modules\n' > "$ytmp/nopath/.yarnrc.yml"
( REPO_DIR="$ytmp/nopath" DRY_RUN=0 clean_stale_yarn_releases ) >/dev/null
assert_status "$?" 0 "clean_stale_yarn_releases returns 0 when yarnPath is missing"
assert_eq "$(ls "$ytmp/nopath/.yarn/releases" | wc -l | tr -d ' ')" "2" \
  "clean_stale_yarn_releases with no yarnPath line deletes nothing"

# Quoted yarnPath (valid YAML): the quotes are stripped before comparing, so
# the pointed-at release survives and only the stale one is removed.
mkdir -p "$ytmp/quoted/.yarn/releases"
printf 'current\n' > "$ytmp/quoted/.yarn/releases/yarn-4.18.0.cjs"
printf 'stale\n' > "$ytmp/quoted/.yarn/releases/yarn-3.9.1.cjs"
printf 'yarnPath: ".yarn/releases/yarn-4.18.0.cjs"\n' > "$ytmp/quoted/.yarnrc.yml"
( REPO_DIR="$ytmp/quoted" DRY_RUN=0 clean_stale_yarn_releases ) >/dev/null
assert_eq "$(ls "$ytmp/quoted/.yarn/releases" | grep -c 'yarn-4.18.0.cjs')" "1" \
  "clean_stale_yarn_releases keeps the release a double-quoted yarnPath points at"
assert_eq "$(ls "$ytmp/quoted/.yarn/releases" | grep -c 'yarn-3.9.1.cjs')" "0" \
  "clean_stale_yarn_releases deletes the stale release next to a double-quoted yarnPath"

mkdir -p "$ytmp/squoted/.yarn/releases"
printf 'current\n' > "$ytmp/squoted/.yarn/releases/yarn-4.18.0.cjs"
printf 'stale\n' > "$ytmp/squoted/.yarn/releases/yarn-3.9.1.cjs"
printf "yarnPath: '.yarn/releases/yarn-4.18.0.cjs'\n" > "$ytmp/squoted/.yarnrc.yml"
( REPO_DIR="$ytmp/squoted" DRY_RUN=0 clean_stale_yarn_releases ) >/dev/null
assert_eq "$(ls "$ytmp/squoted/.yarn/releases" | grep -c 'yarn-4.18.0.cjs')" "1" \
  "clean_stale_yarn_releases keeps the release a single-quoted yarnPath points at"

# Fail closed: yarnPath names a release file that is absent — the current
# release can't be positively identified, so nothing is deleted.
mkdir -p "$ytmp/missingcur/.yarn/releases"
printf 'keep\n' > "$ytmp/missingcur/.yarn/releases/yarn-3.9.1.cjs"
printf 'yarnPath: .yarn/releases/yarn-4.18.0.cjs\n' > "$ytmp/missingcur/.yarnrc.yml"
( REPO_DIR="$ytmp/missingcur" DRY_RUN=0 clean_stale_yarn_releases ) >/dev/null
assert_eq "$(ls "$ytmp/missingcur/.yarn/releases" | grep -c 'yarn-3.9.1.cjs')" "1" \
  "clean_stale_yarn_releases deletes nothing when the yarnPath target file is absent"

# Dry-run: the planned edit is printed, never the completed-action line.
mkdir -p "$ytmp/dryrun/.yarn/releases"
printf 'current\n' > "$ytmp/dryrun/.yarn/releases/yarn-4.18.0.cjs"
printf 'stale\n' > "$ytmp/dryrun/.yarn/releases/yarn-3.9.1.cjs"
printf 'yarnPath: .yarn/releases/yarn-4.18.0.cjs\n' > "$ytmp/dryrun/.yarnrc.yml"
dry_log="$ytmp/dryrun-log"
( REPO_DIR="$ytmp/dryrun" DRY_RUN=1 clean_stale_yarn_releases ) > "$dry_log"
assert_eq "$(ls "$ytmp/dryrun/.yarn/releases" | wc -l | tr -d ' ')" "2" \
  "clean_stale_yarn_releases dry-run deletes nothing"
assert_contains "$(cat "$dry_log")" "[dry-run] edit: remove stale yarn release yarn-3.9.1.cjs" \
  "clean_stale_yarn_releases dry-run prints the planned edit"
assert_eq "$(grep -c 'removed stale release' "$dry_log")" "0" \
  "clean_stale_yarn_releases dry-run never claims a completed removal"

# --- phase_yarn composition (recorder `run` + stubbed clean, in a subshell) ---
mkdir -p "$ytmp/phase"
printf '{"packageManager":"yarn@4.99.0-spec"}\n' > "$ytmp/phase/package.json"
yarn_calls_file="$ytmp/phase/calls"
: > "$yarn_calls_file"
yarn_out="$(
  run() { printf '%s\n' "$*" >> "$yarn_calls_file"; }
  clean_stale_yarn_releases() { printf '%s\n' 'clean_stale_yarn_releases' >> "$yarn_calls_file"; }
  REPO_DIR="$ytmp/phase" phase_yarn
)"
assert_eq "$(cat "$yarn_calls_file")" $'yarn set version berry\nclean_stale_yarn_releases\nyarn install' \
  "phase_yarn records: yarn set version berry, then clean (stubbed), then yarn install"
assert_eq "$(printf '%s\n' "$yarn_out" | grep -c "installed yarn@4.99.0-spec via 'yarn set version berry'")" "1" \
  "phase_yarn logs the packageManager jq readback from the package.json fixture"

# --- mid-phase run failure: the phase aborts, later steps never run ---
mkdir -p "$ytmp/failbin" "$ytmp/failphase"
printf '#!/usr/bin/env sh\nexit 1\n' > "$ytmp/failbin/yarn"
chmod +x "$ytmp/failbin/yarn"
yfail_calls="$ytmp/yfail-calls"
: > "$yfail_calls"
yfail_rc=0
(
  clean_stale_yarn_releases() { printf '%s\n' 'cleaned' >> "$yfail_calls"; }
  PATH="$ytmp/failbin:$PATH"
  DRY_RUN=0
  REPO_DIR="$ytmp/failphase" phase_yarn
) > "$ytmp/yfail-out" 2> "$ytmp/yfail-err" || yfail_rc=$?
assert_status "$yfail_rc" 1 "phase_yarn aborts when 'yarn set version berry' fails mid-phase"
assert_contains "$(cat "$ytmp/yfail-err")" "command failed: yarn set version berry" \
  "phase_yarn leaves a named diagnostic for the failed command"
assert_eq "$(cat "$yfail_calls")" "" \
  "phase_yarn records nothing after the failed command (no release cleanup, no yarn install)"
# Bottom guard: standalone run prints totals; sourced run defers to the runner.
finish_spec
