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

run() {
  local IFS=' '
  if (( DRY_RUN )); then
    log "[dry-run] $*"
  else
    log "+ $*"
    "$@"
  fi
}

apply_edit() {
  local description="$1"
  local IFS=' '
  shift
  if (( DRY_RUN )); then
    log "[dry-run] edit: $description"
  else
    "$@"
  fi
}

# --- in-place file edits (BSD-safe `sed -i ''`; bare `sed -i` is GNU-only) -------

# Replace every occurrence of $2 with $3 in $1.
replace_all_in_file() {
  local file="$1" from="$2" to="$3"
  sed -i '' "s#$from#$to#g" "$file"
}

# Insert $3 as its own line immediately after line $2 of $1 (1-based).
# BSD sed needs `a\` followed by a literal newline before the inserted text.
insert_line_after() {
  local file="$1" n="$2" text="$3"
  (( n >= 1 )) || return 1
  sed -i '' "$n a\\
$text" "$file"
}

# Insert $3 as its own line immediately before line $2 of $1 (1-based).
# BSD sed needs `i\` followed by a literal newline before the inserted text.
insert_line_before() {
  local file="$1" n="$2" text="$3"
  (( n >= 1 )) || return 1
  sed -i '' "$n i\\
$text" "$file"
}
