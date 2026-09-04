#!/usr/bin/env bash
# scripts/specs/preflight.spec.bash — spec for scripts/lib/preflight.bash.
# Standalone: bash scripts/specs/preflight.spec.bash
set -u
SPEC_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/specs/test-utils.bash
source "$SPEC_DIR/test-utils.bash"
# shellcheck source=scripts/lib/preflight.bash
source "$SPEC_DIR/../lib/preflight.bash"
# The sourced lib hardens IFS; restore the default for spec-internal string ops.
IFS=$' \t\n'

# --- derive_gh_repo (command seam: mocked git remote get-url) ---
git() { printf 'https://github.com/exchgr/exch.gr-strapi.git\n'; }
assert_eq "$(derive_gh_repo)" "exchgr/exch.gr-strapi" "derive_gh_repo strips https github URL"
unset -f git

git() { printf 'git@github.com:exchgr/exch.gr-strapi.git\n'; }
assert_eq "$(derive_gh_repo)" "exchgr/exch.gr-strapi" "derive_gh_repo strips ssh github URL"
unset -f git

rc=0
git() { return 1; }
derive_gh_repo || rc=$?
assert_status "$rc" 1 "derive_gh_repo without origin -> status 1"
unset -f git

# --- derive_gh_repo: invalid slugs are rejected (GH_REPO goes into gh api URLs) ---
rc=0
git() { printf 'https://github.com/bad slug/x.git\n'; }
out="$(derive_gh_repo)" || rc=$?
assert_status "$rc" 1 "derive_gh_repo rejects a slug containing a space"
assert_eq "$out" "" "derive_gh_repo prints nothing for an invalid slug"
unset -f git

rc=0
git() { printf 'https://github.com/a//b.git\n'; }
out="$(derive_gh_repo)" || rc=$?
assert_status "$rc" 1 "derive_gh_repo rejects a double-slash slug"
unset -f git

rc=0
git() { printf 'git@github.com:exchgr/exch.gr-strapi;x.git\n'; }
out="$(derive_gh_repo)" || rc=$?
assert_status "$rc" 1 "derive_gh_repo rejects a slug containing a shell metacharacter"
unset -f git

# --- phase_preflight: a wrong-flavor yq hard-fails (mikefarah v4 required) ---
pf_tmp="$(mktemp -d)"
trap 'rm -rf "$pf_tmp"' EXIT
mkdir -p "$pf_tmp/wrongyq"
for pf_tool in yarn git gh jq curl asdf; do
  printf '#!/usr/bin/env sh\nexit 0\n' > "$pf_tmp/wrongyq/$pf_tool"
  chmod +x "$pf_tmp/wrongyq/$pf_tool"
done
printf '#!/usr/bin/env sh\necho "yq 3.4.1"\n' > "$pf_tmp/wrongyq/yq"
chmod +x "$pf_tmp/wrongyq/yq"
wyq_rc=0
(
  PATH="$pf_tmp/wrongyq:$PATH"
  phase_preflight
) > "$pf_tmp/wrongyq-out" 2> "$pf_tmp/wrongyq-err" || wyq_rc=$?
assert_status "$wyq_rc" 1 "phase_preflight dies when yq is not the mikefarah flavor"
assert_contains "$(cat "$pf_tmp/wrongyq-err")" "mikefarah yq v4" \
  "phase_preflight names the wrong flavor and the expected mikefarah yq v4"
assert_contains "$(cat "$pf_tmp/wrongyq-err")" "yq 3.4.1" \
  "phase_preflight reports the flavor it actually found"

# mikefarah-style version output passes the flavor gate (no "wrong flavor" die).
mkdir -p "$pf_tmp/rightyq"
for pf_tool in yarn git gh jq curl asdf; do
  printf '#!/usr/bin/env sh\nexit 0\n' > "$pf_tmp/rightyq/$pf_tool"
  chmod +x "$pf_tmp/rightyq/$pf_tool"
done
printf '#!/usr/bin/env sh\necho "yq (https://github.com/mikefarah/yq/) version v4.44.1"\n' > "$pf_tmp/rightyq/yq"
chmod +x "$pf_tmp/rightyq/yq"
ryq_err="$pf_tmp/rightyq-err"
(
  PATH="$pf_tmp/rightyq:$PATH"
  phase_preflight
) > /dev/null 2> "$ryq_err"
assert_eq "$(grep -c 'wrong flavor' "$ryq_err")" "0" \
  "phase_preflight accepts mikefarah yq v4 version output"

# --- phase_preflight composition: hard-fail entry points + success path ---
pf2="$(mktemp -d)"
trap 'rm -rf "$pf_tmp" "$pf2"' EXIT

# Stub factory: yarn jq yq curl asdf (+gh with the given exit code). git is
# intentionally NOT stubbed so the worktree check exercises the real git.
mk_pf_stubdir() {
  local dir="$1" gh_rc="$2" t
  mkdir -p "$dir"
  for t in yarn jq curl asdf; do
    printf '#!/usr/bin/env sh\nexit 0\n' > "$dir/$t"
    chmod +x "$dir/$t"
  done
  printf '#!/usr/bin/env sh\nexit %s\n' "$gh_rc" > "$dir/gh"
  chmod +x "$dir/gh"
  printf '#!/usr/bin/env sh\necho "yq (https://github.com/mikefarah/yq/) version v4.44.1"\n' > "$dir/yq"
  chmod +x "$dir/yq"
}

# Minimal real-git fixture repo; $1 = dir, $2 = leave it dirty afterwards.
mk_pf_git_repo() {
  git init -q "$1" 2>/dev/null
  git -C "$1" -c user.email=spec@t.io -c user.name=spec commit --allow-empty -q -m init 2>/dev/null
  [[ "$2" == dirty ]] && touch "$1/uncommitted.txt"
  return 0
}

# Missing tool (asdf unreachable): die naming it. PATH drops every dir that
# could carry a real asdf, keeping only the stub dir + system dirs.
mkdir -p "$pf2/missing"
for t in yarn git gh jq yq curl; do
  printf '#!/usr/bin/env sh\nexit 0\n' > "$pf2/missing/$t"
  chmod +x "$pf2/missing/$t"
done
mt_rc=0
(
  PATH="$pf2/missing:/usr/bin:/bin"
  phase_preflight
) > /dev/null 2> "$pf2/missing-err" || mt_rc=$?
assert_status "$mt_rc" 1 "phase_preflight dies when a required tool is missing"
assert_contains "$(cat "$pf2/missing-err")" "missing required tools: asdf" \
  "phase_preflight names every missing required tool"

# gh unauthenticated: die with the auth hint.
mk_pf_stubdir "$pf2/unauth" 1
ua_rc=0
(
  PATH="$pf2/unauth:$PATH"
  phase_preflight
) > /dev/null 2> "$pf2/unauth-err" || ua_rc=$?
assert_status "$ua_rc" 1 "phase_preflight dies when gh is not authenticated"
assert_contains "$(cat "$pf2/unauth-err")" "gh is not authenticated" \
  "phase_preflight tells the user to run gh auth login"

# Dirty worktree (fixture repo, checked via the REAL git through REPO_DIR): die.
mk_pf_stubdir "$pf2/stub" 0
mk_pf_git_repo "$pf2/dirtyrepo" dirty
dw_rc=0
(
  PATH="$pf2/stub:$PATH"
  REPO_DIR="$pf2/dirtyrepo"
  phase_preflight
) > /dev/null 2> "$pf2/dirty-err" || dw_rc=$?
assert_status "$dw_rc" 1 "phase_preflight dies when the worktree is dirty"
assert_contains "$(cat "$pf2/dirty-err")" "worktree is dirty" \
  "phase_preflight tells the user to commit or stash"

# Success path: all stubs pass, clean fixture repo -> all-checks log with GH_REPO.
mk_pf_git_repo "$pf2/cleanrepo" clean
ok_log="$pf2/ok-log"
(
  PATH="$pf2/stub:$PATH"
  REPO_DIR="$pf2/cleanrepo"
  phase_preflight
) > "$ok_log" 2> "$pf2/ok-err"
ok_rc=$?
assert_status "$ok_rc" 0 "phase_preflight succeeds on a clean worktree with all tools"
assert_contains "$(cat "$ok_log")" "preflight: all checks passed" \
  "phase_preflight logs success"
assert_contains "$(cat "$ok_log")" "repo: ${GH_REPO:-unknown}" \
  "phase_preflight logs the derived GH_REPO"

# Bottom guard: standalone run prints totals; sourced run defers to the runner.
finish_spec
