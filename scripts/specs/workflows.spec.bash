#!/usr/bin/env bash
# scripts/specs/workflows.spec.bash — spec for scripts/lib/workflows.bash
# (workflow pin bumps across .github/workflows/*.yml).
# The production wiring for latest_tag_for_repo lives in lookups.spec.bash —
# these cases shadow the lookup seam directly.
# Standalone: bash scripts/specs/workflows.spec.bash
set -u
SPEC_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/specs/test-utils.bash
source "$SPEC_DIR/test-utils.bash"
# shellcheck source=scripts/lib/workflows.bash
source "$SPEC_DIR/../lib/workflows.bash"
# The sourced lib hardens IFS; restore the default for spec-internal string ops.
IFS=$' \t\n'

wtmp="$(mktemp -d)"
trap 'rm -rf "$wtmp"' EXIT

# --- collect_workflow_pins (pure text-in/text-out: uses: lines only, deduped) ---
mkdir -p "$wtmp/pins"
cat > "$wtmp/pins/wf.yml" <<'EOF'
jobs:
  build:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v7
      - uses: actions/checkout@v7
      - uses: foo/bar@v1
EOF
assert_eq "$(collect_workflow_pins "$wtmp/pins/wf.yml")" $'actions/checkout v7\nfoo/bar v1' \
  "collect_workflow_pins yields deduped owner/repo ref pairs and ignores runs-on: lines"

# --- happy path: both checkout pins bumped, flyctl kept, runs-on untouched ---
mkdir -p "$wtmp/happy/.github/workflows"
cat > "$wtmp/happy/.github/workflows/ci.yml" <<'EOF'
name: ci
on: [push]
jobs:
  build:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v7
      - uses: actions/checkout@v7
      - uses: superfly/flyctl-actions/setup-flyctl@v1.4
EOF
happy_log="$wtmp/happy-log"
(
  latest_tag_for_repo() {
    case "$1" in
      actions/checkout) printf 'v8\n' ;;
      superfly/flyctl-actions/setup-flyctl) printf 'v1.4\n' ;;
      *) return 1 ;;
    esac
  }
  REPO_DIR="$wtmp/happy" phase_workflows
) > "$happy_log"
happy_rc=$?
wf="$wtmp/happy/.github/workflows/ci.yml"
assert_status "$happy_rc" 0 "phase_workflows happy path completes with status 0"
assert_eq "$(grep -c 'uses: actions/checkout@v8' "$wf")" "2" \
  "phase_workflows bumps both actions/checkout@v7 pins to v8"
assert_eq "$(grep -c 'uses: actions/checkout@v7' "$wf")" "0" \
  "phase_workflows leaves no stale actions/checkout@v7 pins"
assert_eq "$(grep -c 'uses: superfly/flyctl-actions/setup-flyctl@v1.4' "$wf")" "1" \
  "phase_workflows keeps superfly/flyctl-actions/setup-flyctl@v1.4 (same tag — no-op)"
assert_eq "$(grep -c 'runs-on: ubuntu-latest' "$wf")" "1" \
  "phase_workflows never touches runs-on: lines (only uses: lines are matched)"
assert_eq "$(grep -c 'bumped actions/checkout@v7 -> actions/checkout@v8' "$happy_log")" "1" \
  "phase_workflows logs the checkout bump once (pins deduped)"
assert_eq "$(grep -c 'setup-flyctl@v1.4.*no-op' "$happy_log")" "1" \
  "phase_workflows logs the unchanged flyctl pin as a no-op"

# --- lookup failure: old pin kept + warn, other pins still processed ---
mkdir -p "$wtmp/fail/.github/workflows"
cat > "$wtmp/fail/.github/workflows/ci.yml" <<'EOF'
jobs:
  build:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v7
      - uses: foo/bar@v1
EOF
fail_log="$wtmp/fail-log"
fail_err="$wtmp/fail-err"
(
  latest_tag_for_repo() {
    [[ "$1" == 'actions/checkout' ]] && return 1
    [[ "$1" == 'foo/bar' ]] && printf 'v2\n'
  }
  REPO_DIR="$wtmp/fail" phase_workflows
) > "$fail_log" 2> "$fail_err"
wff="$wtmp/fail/.github/workflows/ci.yml"
assert_eq "$(grep -c 'uses: actions/checkout@v7' "$wff")" "1" \
  "phase_workflows keeps the old pin when the latest-tag lookup fails"
assert_eq "$(grep -c 'uses: foo/bar@v2' "$wff")" "1" \
  "phase_workflows still processes the other pins when one lookup fails"
assert_eq "$(grep -c 'no latest tag found for actions/checkout' "$fail_err")" "1" \
  "phase_workflows warns on a failed lookup and keeps the old pin"

# --- no uses: pins in a file -> skip log ---
mkdir -p "$wtmp/empty/.github/workflows"
printf 'jobs:\n  build:\n    runs-on: ubuntu-latest\n' > "$wtmp/empty/.github/workflows/ci.yml"
empty_log="$wtmp/empty-log"
(
  latest_tag_for_repo() { printf 'v9\n'; }
  REPO_DIR="$wtmp/empty" phase_workflows
) > "$empty_log"
assert_eq "$(grep -c 'no uses: pins — skipping' "$empty_log")" "1" \
  "phase_workflows logs a skip for a workflow file with no uses: pins"

# --- missing .github/workflows directory -> skip log ---
mkdir -p "$wtmp/no-dir"
no_dir_log="$wtmp/nodir-log"
(
  REPO_DIR="$wtmp/no-dir" phase_workflows
) > "$no_dir_log"
assert_eq "$(grep -c 'no .github/workflows directory — skipping' "$no_dir_log")" "1" \
  "phase_workflows skips when .github/workflows is missing"

# --- dry-run: the planned edit is printed, never the completed bump line ---
mkdir -p "$wtmp/dryrun/.github/workflows"
cat > "$wtmp/dryrun/.github/workflows/ci.yml" <<'EOF'
jobs:
  build:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v7
EOF
dryrun_log="$wtmp/dryrun-log"
(
  latest_tag_for_repo() { printf 'v8\n'; }
  DRY_RUN=1
  REPO_DIR="$wtmp/dryrun" phase_workflows
) > "$dryrun_log"
dryrun_rc=$?
assert_status "$dryrun_rc" 0 "phase_workflows dry-run completes with status 0"
assert_eq "$(grep -c 'uses: actions/checkout@v8' "$wtmp/dryrun/.github/workflows/ci.yml")" "0" \
  "phase_workflows dry-run leaves the pin untouched"
assert_contains "$(cat "$dryrun_log")" "[dry-run] edit: bump actions/checkout@v7 -> actions/checkout@v8" \
  "phase_workflows dry-run prints the planned edit"
assert_eq "$(grep -c 'workflows: bumped' "$dryrun_log")" "0" \
  "phase_workflows dry-run never claims a completed bump"

# Bottom guard: standalone run prints totals; sourced run defers to the runner.
finish_spec
