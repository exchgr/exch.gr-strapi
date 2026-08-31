#!/usr/bin/env bash
# scripts/specs/yarn.spec.bash — spec for scripts/lib/yarn.bash (yarn phase).
# Standalone: bash scripts/specs/yarn.spec.bash
set -u
SPEC_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/specs/common.spec.bash
source "$SPEC_DIR/common.spec.bash"
# shellcheck source=scripts/lib/yarn.bash
source "$SPEC_DIR/../lib/yarn.bash"
# The sourced lib hardens IFS; restore the default for spec-internal string ops.
IFS=$' \t\n'

# --- clean_stale_yarn_releases (real fs fixture in a temp REPO_DIR) ---
ytmp="$(mktemp -d)"

# Keeps the release yarnPath points at, deletes only the stale one.
# Nuance (Subtask-2 fix): yarnPath is relative while find emits absolute
# paths — only a basename comparison decides what survives.
mkdir -p "$ytmp/.yarn/releases"
printf 'current\n' > "$ytmp/.yarn/releases/yarn-4.18.0.cjs"
printf 'stale\n' > "$ytmp/.yarn/releases/yarn-3.9.1.cjs"
printf 'yarnPath: .yarn/releases/yarn-4.18.0.cjs\n' > "$ytmp/.yarnrc.yml"
REPO_DIR="$ytmp" DRY_RUN=0 clean_stale_yarn_releases >/dev/null
assert_eq "$(ls "$ytmp/.yarn/releases" | grep -c 'yarn-4.18.0.cjs')" "1" \
  "clean_stale_yarn_releases keeps the file yarnPath points at (relative yarnPath vs absolute find path)"
assert_eq "$(ls "$ytmp/.yarn/releases" | grep -c 'yarn-3.9.1.cjs')" "0" \
  "clean_stale_yarn_releases deletes the stale release file"

# No .yarnrc.yml -> no-op, status 0, release untouched.
mkdir -p "$ytmp/norcss/.yarn/releases"
printf 'keep\n' > "$ytmp/norcss/.yarn/releases/yarn-4.18.0.cjs"
REPO_DIR="$ytmp/norcss" DRY_RUN=0 clean_stale_yarn_releases >/dev/null
assert_status "$?" 0 "clean_stale_yarn_releases returns 0 without .yarnrc.yml"
assert_eq "$(ls "$ytmp/norcss/.yarn/releases")" "yarn-4.18.0.cjs" \
  "clean_stale_yarn_releases without .yarnrc.yml is a no-op"

# No .yarn/releases dir -> no-op, status 0.
mkdir -p "$ytmp/norel"
printf 'yarnPath: .yarn/releases/yarn-4.18.0.cjs\n' > "$ytmp/norel/.yarnrc.yml"
REPO_DIR="$ytmp/norel" DRY_RUN=0 clean_stale_yarn_releases >/dev/null
assert_status "$?" 0 "clean_stale_yarn_releases returns 0 without .yarn/releases dir"

# yarnPath missing -> no-op, nothing deleted.
mkdir -p "$ytmp/nopath/.yarn/releases"
printf 'keep\n' > "$ytmp/nopath/.yarn/releases/yarn-4.18.0.cjs"
printf 'keep\n' > "$ytmp/nopath/.yarn/releases/yarn-3.9.1.cjs"
printf 'nodeLinker: node-modules\n' > "$ytmp/nopath/.yarnrc.yml"
REPO_DIR="$ytmp/nopath" DRY_RUN=0 clean_stale_yarn_releases >/dev/null
assert_status "$?" 0 "clean_stale_yarn_releases returns 0 when yarnPath is missing"
assert_eq "$(ls "$ytmp/nopath/.yarn/releases" | wc -l | tr -d ' ')" "2" \
  "clean_stale_yarn_releases with no yarnPath line deletes nothing"

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
rm -rf "$ytmp"

# Bottom guard: standalone run prints totals; sourced run defers to the runner.
if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  printf 'PASS: %d FAIL: %d\n' "$PASS" "$FAIL"
  if [[ "$FAIL" -gt 0 ]]; then
    exit 1
  fi
  exit 0
fi
