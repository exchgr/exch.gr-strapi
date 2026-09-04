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
# Prefix convention: log lines start with "<phase>: " (e.g. "node: ...",
# "deps: ..."); warn prints the bare message to stderr; die prefixes its
# message with "upgrade.sh:". No literal "[upgrade]" prefix exists anywhere.

log() {
  local IFS=' '
  printf '%s\n' "$*"
}

warn() {
  local IFS=' '
  printf '%s\n' "$*" >&2
}

die() {
  local IFS=' '
  warn "upgrade.sh: $*"
  exit 1
}

# --- execution wrappers (dry-run aware) ------------------------------------------

# Both wrappers enforce the documented blast-radius contract: a failed command
# or edit aborts the whole run instead of letting later phases mutate on a
# broken base. Dry-run paths never execute anything and cannot fail.
run() {
  local IFS=' '
  if (( DRY_RUN )); then
    log "[dry-run] $*"
  else
    log "+ $*"
    "$@" || die "command failed: $*"
  fi
}

apply_edit() {
  local description="$1"
  local IFS=' '
  shift
  if (( DRY_RUN )); then
    log "[dry-run] edit: $description"
  else
    "$@" || die "edit failed: $description"
  fi
}

# --- in-place file edits (BSD-safe `sed -i ''`; bare `sed -i` is GNU-only) -------

# Replace every occurrence of $2 with $3 in $1.
replace_all_in_file() {
  local file="$1" from="$2" to="$3"
  sed -i '' "s#$from#$to#g" "$file"
}
