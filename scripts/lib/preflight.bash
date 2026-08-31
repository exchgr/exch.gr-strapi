# scripts/lib/preflight.bash — preflight phase: hard-fail environment checks; any
# failure aborts the run. Owns REQUIRED_TOOLS, derive_gh_repo, and GH_REPO.
# Dependency: common.bash.
# shellcheck source=scripts/lib/common.bash
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/common.bash"

REQUIRED_TOOLS=(yarn git gh jq curl asdf)

derive_gh_repo() {
  local url
  url="$(git -C "$REPO_DIR" remote get-url origin 2>/dev/null)" || return 1
  url="${url##*github.com[:/]}"
  url="${url%.git}"
  [[ "$url" == */* ]] || return 1
  printf '%s\n' "$url"
}

GH_REPO="$(derive_gh_repo || true)"

# Hard-error preflight: any failure aborts the run. No skip-and-continue.
phase_preflight() {
  local -a missing=()
  local tool
  for tool in "${REQUIRED_TOOLS[@]}"; do
    command -v "$tool" >/dev/null 2>&1 || missing+=("$tool")
  done
  if (( ${#missing[@]} > 0 )); then
    die "missing required tools: ${missing[*]}"
  fi
  gh auth status >/dev/null 2>&1 || die "gh is not authenticated — run 'gh auth login' first"
  if [[ -n "$(git -C "$REPO_DIR" status --porcelain)" ]]; then
    die "worktree is dirty — commit or stash before running the upgrade"
  fi
  log "preflight: all checks passed (repo: ${GH_REPO:-unknown})"
}
