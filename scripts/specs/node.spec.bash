#!/usr/bin/env bash
# scripts/specs/node.spec.bash — spec for scripts/lib/node.bash (node phase edit functions).
# Standalone: bash scripts/specs/node.spec.bash
set -u
SPEC_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/specs/test-utils.bash
source "$SPEC_DIR/test-utils.bash"
# shellcheck source=scripts/lib/node.bash
source "$SPEC_DIR/../lib/node.bash"
# The sourced lib hardens IFS; restore the default for spec-internal string ops.
IFS=$' \t\n'

# --- __pin_tool_versions (side-effect seam: edits only the tmpfile) ---
tmpdir="$(mktemp -d)"
trap 'rm -rf "$tmpdir"' EXIT
toolfile="$tmpdir/.tool-versions"
__pin_tool_versions "$toolfile" "24.20.0"
assert_eq "$(grep -c '^nodejs 24.20.0$' "$toolfile")" "1" "__pin_tool_versions appends pin when file has no nodejs line"

printf 'yarn 4.12.0\nnodejs 22.0.0\n' > "$toolfile"
__pin_tool_versions "$toolfile" "24.20.0"
assert_eq "$(printf '%s\n' "$(cat "$toolfile")")" $'yarn 4.12.0\nnodejs 24.20.0' "__pin_tool_versions replaces existing nodejs line"

# --- pin_tool_versions_node (already-pinned -> no edit needed) ---
printf 'nodejs 24.20.0\n' > "$toolfile"
( REPO_DIR="$tmpdir" DRY_RUN=0 pin_tool_versions_node "24.20.0" )
assert_eq "$(printf '%s\n' "$(cat "$toolfile")")" "nodejs 24.20.0" "pin_tool_versions_node keeps correct pin untouched"

# --- rewrite_engines (node ^<major>.0.0, npm pin dropped; unrelated keys untouched) ---
printf '{"name":"x","packageManager":"yarn@4.12.0","engines":{"node":">=22","npm":">=10"},"dependencies":{"react":"^18.0.0"}}\n' > "$tmpdir/package.json"
( REPO_DIR="$tmpdir" DRY_RUN=0 rewrite_engines "24" )
assert_eq "$(jq -r '.engines.node' "$tmpdir/package.json")" "^24.0.0" "rewrite_engines sets engines.node to ^24.0.0"
assert_eq "$(jq -r '.engines | has("npm")' "$tmpdir/package.json")" "false" "rewrite_engines drops engines.npm"
assert_eq "$(tail -c 1 "$tmpdir/package.json" | od -An -c | tr -d ' ')" "\n" "rewrite_engines guarantees trailing newline"
assert_eq "$(grep -c '^  "dependencies"' "$tmpdir/package.json")" "1" "rewrite_engines preserves 2-space indent"
assert_eq "$(grep -c '^    "react"' "$tmpdir/package.json")" "1" "rewrite_engines preserves nested 2-space indent"
assert_eq "$(jq -c '.dependencies' "$tmpdir/package.json")" '{"react":"^18.0.0"}' "rewrite_engines leaves dependencies byte-for-byte"
assert_eq "$(jq -r '.packageManager' "$tmpdir/package.json")" "yarn@4.12.0" "rewrite_engines leaves packageManager byte-for-byte"

# --- rewrite_engines dry-run (no mutation applied) ---
printf '{"name":"x","engines":{"node":">=22","npm":">=10"}}\n' > "$tmpdir/package.json"
( REPO_DIR="$tmpdir" DRY_RUN=1 rewrite_engines "24" ) > "$tmpdir/engines-dry-log"
assert_eq "$(jq -r '.engines.node' "$tmpdir/package.json")" ">=22" "rewrite_engines dry-run leaves file unchanged"
assert_contains "$(cat "$tmpdir/engines-dry-log")" "[dry-run] edit: set engines.node to ^24.0.0" \
  "rewrite_engines dry-run prints the planned edit"
assert_eq "$(grep -c 'engines rewritten' "$tmpdir/engines-dry-log")" "0" \
  "rewrite_engines dry-run never claims a completed engines rewrite"

# --- pin_tool_versions_node dry-run: planned edit only, no completed-pin claim ---
printf 'nodejs 22.0.0\n' > "$toolfile"
( REPO_DIR="$tmpdir" DRY_RUN=1 pin_tool_versions_node "24.20.0" ) > "$tmpdir/pin-dry-log"
assert_eq "$(printf '%s\n' "$(cat "$toolfile")")" "nodejs 22.0.0" \
  "pin_tool_versions_node dry-run leaves .tool-versions unchanged"
assert_contains "$(cat "$tmpdir/pin-dry-log")" "[dry-run] edit: pin nodejs 24.20.0 in .tool-versions" \
  "pin_tool_versions_node dry-run prints the planned edit"
assert_eq "$(grep -c 'edit was needed' "$tmpdir/pin-dry-log")" "0" \
  "pin_tool_versions_node dry-run never claims a completed pin"

# --- phase_node: a failed/empty LTS lookup hard-fails before any mutation ---
mkdir -p "$tmpdir/node-ltsfail"
printf 'nodejs 22.0.0\n' > "$tmpdir/node-ltsfail/.tool-versions"
printf '{"name":"x","engines":{"node":">=22","npm":">=10"}}\n' > "$tmpdir/node-ltsfail/package.json"
nl_rc=0
(
  latest_node_lts() { return 1; }
  REPO_DIR="$tmpdir/node-ltsfail" phase_node
) > "$tmpdir/node-ltsfail-out" 2> "$tmpdir/node-ltsfail-err" || nl_rc=$?
assert_status "$nl_rc" 1 "phase_node aborts when the node LTS lookup fails"
assert_contains "$(cat "$tmpdir/node-ltsfail-err")" "could not resolve the latest node LTS" \
  "phase_node names the failed LTS lookup on stderr"
assert_eq "$(printf '%s\n' "$(cat "$tmpdir/node-ltsfail/.tool-versions")")" "nodejs 22.0.0" \
  "phase_node leaves .tool-versions untouched when the LTS lookup fails"
assert_eq "$(jq -r '.engines.node' "$tmpdir/node-ltsfail/package.json")" ">=22" \
  "phase_node leaves package.json engines untouched when the LTS lookup fails"

nl_rc=0
(
  latest_node_lts() { printf '\n'; }
  REPO_DIR="$tmpdir/node-ltsfail" phase_node
) > /dev/null 2> "$tmpdir/node-ltsfail-err2" || nl_rc=$?
assert_status "$nl_rc" 1 "phase_node aborts when the node LTS lookup returns empty"

# --- phase_node: a mid-phase failing run aborts before the pin/engines steps ---
mkdir -p "$tmpdir/node-midfail"
printf 'nodejs 22.0.0\n' > "$tmpdir/node-midfail/.tool-versions"
printf '{"name":"x","engines":{"node":">=22"}}\n' > "$tmpdir/node-midfail/package.json"
nf_calls="$tmpdir/node-midfail-calls"
: > "$nf_calls"
nf_rc=0
(
  latest_node_lts() { printf '24.99.0\n'; }
  asdf() {
    case "$1" in
      list) printf 'nodejs 22.0.0\n' ;;
      install) return 1 ;;
    esac
  }
  pin_tool_versions_node() { printf 'pin %s\n' "$1" >> "$nf_calls"; }
  rewrite_engines() { printf 'engines %s\n' "$1" >> "$nf_calls"; }
  REPO_DIR="$tmpdir/node-midfail" phase_node
) > /dev/null 2> "$tmpdir/node-midfail-err" || nf_rc=$?
assert_status "$nf_rc" 1 "phase_node aborts when asdf install fails mid-phase"
assert_contains "$(cat "$tmpdir/node-midfail-err")" "command failed: asdf install nodejs 24.99.0" \
  "phase_node names the failed asdf install on stderr"
assert_eq "$(cat "$nf_calls")" "" \
  "phase_node never reaches the pin/engines steps after a failed install"

# --- phase_node composition: ordering + branches (recorder/PATH-stub pattern) ---
mkdir -p "$tmpdir/node-comp"
printf 'nodejs 22.0.0\n' > "$tmpdir/node-comp/.tool-versions"
printf '{"name":"x","engines":{"node":">=22"}}\n' > "$tmpdir/node-comp/package.json"

# Not installed: asdf install -> asdf set --home -> pin -> rewrite_engines, in order.
nc_calls="$tmpdir/node-comp-notinstalled-calls"
: > "$nc_calls"
(
  run() { printf '%s\n' "$*" >> "$nc_calls"; }
  latest_node_lts() { printf '24.99.0\n'; }
  asdf() {
    case "$1" in
      list) printf 'nodejs 22.0.0\n' ;;
    esac
  }
  pin_tool_versions_node() { printf 'pin %s\n' "$1" >> "$nc_calls"; }
  rewrite_engines() { printf 'engines %s\n' "$1" >> "$nc_calls"; }
  REPO_DIR="$tmpdir/node-comp" phase_node > /dev/null
)
assert_eq "$(cat "$nc_calls")" \
  $'asdf install nodejs 24.99.0\nasdf set --home nodejs 24.99.0\npin 24.99.0\nengines 24' \
  "phase_node records asdf install -> asdf set --home -> pin -> engines in order when the LTS is not installed"

# Already installed: no asdf install, the rest unchanged.
nc_calls="$tmpdir/node-comp-installed-calls"
: > "$nc_calls"
(
  run() { printf '%s\n' "$*" >> "$nc_calls"; }
  latest_node_lts() { printf '24.99.0\n'; }
  asdf() {
    case "$1" in
      list) printf 'nodejs 24.99.0\n' ;;
    esac
  }
  pin_tool_versions_node() { printf 'pin %s\n' "$1" >> "$nc_calls"; }
  rewrite_engines() { printf 'engines %s\n' "$1" >> "$nc_calls"; }
  REPO_DIR="$tmpdir/node-comp" phase_node > /dev/null
)
assert_eq "$(cat "$nc_calls")" \
  $'asdf set --home nodejs 24.99.0\npin 24.99.0\nengines 24' \
  "phase_node skips asdf install when the LTS version is already installed"

# rewrite_engines already-correct early-return: no edit, file untouched.
mkdir -p "$tmpdir/node-engines-ok"
printf '{"name":"x","engines":{"node":"^24.0.0"}}\n' > "$tmpdir/node-engines-ok/package.json"
cp "$tmpdir/node-engines-ok/package.json" "$tmpdir/engines-ok-before"
( REPO_DIR="$tmpdir/node-engines-ok" DRY_RUN=0 rewrite_engines "24" ) > "$tmpdir/engines-ok-log"
cmp -s "$tmpdir/engines-ok-before" "$tmpdir/node-engines-ok/package.json"
assert_status "$?" 0 \
  "rewrite_engines with engines already ^major.0.0 (no npm pin) changes zero bytes"
assert_contains "$(cat "$tmpdir/engines-ok-log")" "engines already ^24.0.0 without npm pin" \
  "rewrite_engines early-returns with an already-correct log"

# Bottom guard: standalone run prints totals; sourced run defers to the runner.
finish_spec
