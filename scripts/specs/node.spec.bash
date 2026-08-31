#!/usr/bin/env bash
# scripts/specs/node.spec.bash — spec for scripts/lib/node.bash (node phase edit functions).
# Standalone: bash scripts/specs/node.spec.bash
set -u
SPEC_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/specs/common.spec.bash
source "$SPEC_DIR/common.spec.bash"
# shellcheck source=scripts/lib/node.bash
source "$SPEC_DIR/../lib/node.bash"
# The sourced lib hardens IFS; restore the default for spec-internal string ops.
IFS=$' \t\n'

# --- __pin_tool_versions (side-effect seam: edits only the tmpfile) ---
tmpdir="$(mktemp -d)"
toolfile="$tmpdir/.tool-versions"
__pin_tool_versions "$toolfile" "24.20.0"
assert_eq "$(grep -c '^nodejs 24.20.0$' "$toolfile")" "1" "__pin_tool_versions appends pin when file has no nodejs line"

printf 'yarn 4.12.0\nnodejs 22.0.0\n' > "$toolfile"
__pin_tool_versions "$toolfile" "24.20.0"
assert_eq "$(printf '%s\n' "$(cat "$toolfile")")" $'yarn 4.12.0\nnodejs 24.20.0' "__pin_tool_versions replaces existing nodejs line"
assert_eq "$(find "$tmpdir" -name '*.bak' | wc -l | tr -d ' ')" "0" "__pin_tool_versions leaves no .bak"

# --- pin_tool_versions_node (already-pinned -> no edit needed) ---
printf 'nodejs 24.20.0\n' > "$toolfile"
REPO_DIR="$tmpdir" DRY_RUN=0 pin_tool_versions_node "24.20.0"
assert_eq "$(printf '%s\n' "$(cat "$toolfile")")" "nodejs 24.20.0" "pin_tool_versions_node keeps correct pin untouched"

# --- rewrite_engines (node ^<major>.0.0, npm pin dropped; unrelated keys untouched) ---
printf '{"name":"x","packageManager":"yarn@4.12.0","engines":{"node":">=22","npm":">=10"},"dependencies":{"react":"^18.0.0"}}\n' > "$tmpdir/package.json"
REPO_DIR="$tmpdir" DRY_RUN=0 rewrite_engines "24"
assert_eq "$(jq -r '.engines.node' "$tmpdir/package.json")" "^24.0.0" "rewrite_engines sets engines.node to ^24.0.0"
assert_eq "$(jq -r '.engines | has("npm")' "$tmpdir/package.json")" "false" "rewrite_engines drops engines.npm"
assert_eq "$(tail -c 1 "$tmpdir/package.json" | od -An -c | tr -d ' ')" "\n" "rewrite_engines guarantees trailing newline"
assert_eq "$(grep -c '^  "dependencies"' "$tmpdir/package.json")" "1" "rewrite_engines preserves 2-space indent"
assert_eq "$(grep -c '^    "react"' "$tmpdir/package.json")" "1" "rewrite_engines preserves nested 2-space indent"
assert_eq "$(jq -c '.dependencies' "$tmpdir/package.json")" '{"react":"^18.0.0"}' "rewrite_engines leaves dependencies byte-for-byte"
assert_eq "$(jq -r '.packageManager' "$tmpdir/package.json")" "yarn@4.12.0" "rewrite_engines leaves packageManager byte-for-byte"

# --- rewrite_engines dry-run (no mutation applied) ---
printf '{"name":"x","engines":{"node":">=22","npm":">=10"}}\n' > "$tmpdir/package.json"
REPO_DIR="$tmpdir" DRY_RUN=1 rewrite_engines "24" >/dev/null
assert_eq "$(jq -r '.engines.node' "$tmpdir/package.json")" ">=22" "rewrite_engines dry-run leaves file unchanged"
rm -rf "$tmpdir"

# Bottom guard: standalone run prints totals; sourced run defers to the runner.
if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  printf 'PASS: %d FAIL: %d\n' "$PASS" "$FAIL"
  if [[ "$FAIL" -gt 0 ]]; then
    exit 1
  fi
  exit 0
fi
