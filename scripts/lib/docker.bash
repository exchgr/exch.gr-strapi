# scripts/lib/docker.bash — dockerfile phase: move every `node:<ver>-alpine`
# stage to the latest node LTS. A missing Dockerfile is a soft, standalone-safe
# skip (warn + return 0): unlike preflight it is not a blocker for the other
# phases, and the user can point the script elsewhere later.
# Dependencies: common.bash, lookups.bash.
# shellcheck source=scripts/lib/common.bash
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/common.bash"
# shellcheck source=scripts/lib/lookups.bash
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lookups.bash"

# selector: docker
phase_dockerfile() {
  local dockerfile="$REPO_DIR/Dockerfile"
  if [[ ! -f "$dockerfile" ]]; then
    warn "docker: $dockerfile not found — skipping phase"
    return 0
  fi
  rewrite_dockerfile_base_image "$dockerfile"
  log "docker: phase complete"
}

# Every `node:<ver>-alpine` base image (all stages — the /g rewrite hits both)
# moves to the latest node LTS MAJOR alias (`node:<major>-alpine`), never a
# patch-pinned image: the floating alias lets a fresh CI runner fetch the
# newest patch at build time, so a current patch-pinned image is normalized
# back to the alias. A failed LTS lookup warns and leaves the file untouched
# (the base image is a soft lookup, unlike preflight).
rewrite_dockerfile_base_image() {
  local dockerfile="$1" lts lts_major old
  if ! lts="$(latest_node_lts)" || [[ -z "$lts" ]]; then
    warn "docker: could not resolve the latest node LTS — leaving the base image untouched"
    return 0
  fi
  lts_major="$(semver_major "$lts")"
  old="$(grep -m1 -Eo 'node:[0-9.]+-alpine' "$dockerfile" | sed 's/^node://; s/-alpine$//')"
  if [[ -z "$old" ]]; then
    log "docker: no node:*-alpine base image in the Dockerfile — no-op"
    return 0
  fi
  if [[ "$old" == "$lts_major" ]]; then
    log "docker: base image already node:$old-alpine (latest LTS major $lts_major) — no-op"
    return 0
  fi
  apply_edit "rewrite node:$old-alpine -> node:$lts_major-alpine in Dockerfile" \
    replace_all_in_file "$dockerfile" "node:$old-alpine" "node:$lts_major-alpine"
  log "docker: base image node:$old-alpine -> node:$lts_major-alpine (all stages)"
}
