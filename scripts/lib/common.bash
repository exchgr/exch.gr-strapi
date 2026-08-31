# scripts/lib/common.bash — shared logging, dry-run wrappers, and global state.
# Sourcing order contract: common.bash first; every other lib module sources it.
# Sourcing is idempotent: repeated source redefines the functions and never
# resets DRY_RUN once it has been set.
set -uo pipefail
IFS=$'\n\t'

DRY_RUN="${DRY_RUN:-0}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

# --- logging -------------------------------------------------------------------

log() {
  printf '%s\n' "$*"
}

warn() {
  printf '%s\n' "$*" >&2
}

die() {
  warn "upgrade.sh: $*"
  exit 1
}

# --- execution wrappers (dry-run aware) ------------------------------------------

run() {
  if (( DRY_RUN )); then
    log "[dry-run] $*"
  else
    log "+ $*"
    "$@"
  fi
}

apply_edit() {
  local description="$1"
  shift
  if (( DRY_RUN )); then
    log "[dry-run] edit: $description"
  else
    "$@"
  fi
}
