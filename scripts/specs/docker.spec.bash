#!/usr/bin/env bash
# scripts/specs/docker.spec.bash — spec for scripts/lib/docker.bash (dockerfile
# phase: node LTS base-image rewrite only).
# latest_node_lts is shadowed here; its production wiring lives in
# lookups.spec.bash — not duplicated.
# Standalone: bash scripts/specs/docker.spec.bash
set -u
SPEC_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/specs/test-utils.bash
source "$SPEC_DIR/test-utils.bash"
# shellcheck source=scripts/lib/docker.bash
source "$SPEC_DIR/../lib/docker.bash"
# The sourced lib hardens IFS; restore the default for spec-internal string ops.
IFS=$' \t\n'

dtmp="$(mktemp -d)"
trap 'rm -rf "$dtmp"' EXIT

# --- major bump: node:22-alpine rewritten to the latest LTS MAJOR alias ---
mkdir -p "$dtmp/fresh"
cat > "$dtmp/fresh/Dockerfile" <<'EOF'
FROM node:22-alpine AS build-base

WORKDIR /app

ENV NODE_ENV=production

COPY package.json yarn.lock ./

RUN yarn install

FROM node:22-alpine

WORKDIR /app

COPY --from=build-base /app .

CMD ["yarn", "start"]
EOF
(
  latest_node_lts() { printf '24.99.0\n'; }
  REPO_DIR="$dtmp/fresh" phase_dockerfile
) > /dev/null
df="$dtmp/fresh/Dockerfile"
assert_eq "$(grep -c 'FROM node:24-alpine' "$df")" "2" \
  "phase_dockerfile rewrites every node:22-alpine stage to the latest LTS major alias node:24-alpine"
assert_eq "$(grep -c 'FROM node:22-alpine' "$df")" "0" \
  "phase_dockerfile leaves no stale node:22-alpine stages"
assert_eq "$(grep -c 'FROM node:24.99.0-alpine' "$df")" "0" \
  "phase_dockerfile never pins a patch-specific base image"

# --- mixed majors across stages: EVERY distinct node:*-alpine version moves ---
mkdir -p "$dtmp/mixed"
cat > "$dtmp/mixed/Dockerfile" <<'EOF'
FROM node:20-alpine AS deps

RUN yarn install

FROM node:22-alpine AS build

COPY --from=deps /app .

RUN yarn build

FROM node:22-alpine

CMD ["yarn", "start"]
EOF
(
  latest_node_lts() { printf '24.99.0\n'; }
  REPO_DIR="$dtmp/mixed" phase_dockerfile
) > /dev/null
mf="$dtmp/mixed/Dockerfile"
assert_eq "$(grep -c 'FROM node:20-alpine' "$mf")" "0" \
  "phase_dockerfile does not leave the older node:20-alpine stage stale"
assert_eq "$(grep -c 'FROM node:24-alpine' "$mf")" "3" \
  "phase_dockerfile rewrites every distinct node:*-alpine version (all stages) to the LTS major alias"

# --- dry-run: the planned edit is printed, never the completed rewrite line ---
mkdir -p "$dtmp/dryrun"
printf 'FROM node:22-alpine\n\nRUN yarn install\n' > "$dtmp/dryrun/Dockerfile"
cp "$dtmp/dryrun/Dockerfile" "$dtmp/dryrun-before"
dry_log="$dtmp/dryrun-log"
(
  latest_node_lts() { printf '24.99.0\n'; }
  DRY_RUN=1
  REPO_DIR="$dtmp/dryrun" phase_dockerfile
) > "$dry_log"
cmp -s "$dtmp/dryrun-before" "$dtmp/dryrun/Dockerfile"
assert_status "$?" 0 "phase_dockerfile dry-run leaves the Dockerfile byte-for-byte"
assert_contains "$(cat "$dry_log")" "[dry-run] edit: rewrite node:22-alpine -> node:24-alpine" \
  "phase_dockerfile dry-run prints the planned edit"
assert_eq "$(grep -c 'base image node:22-alpine -> node:24-alpine' "$dry_log")" "0" \
  "phase_dockerfile dry-run never claims a completed base-image rewrite"

# --- real-Dockerfile shape (multi-line cache-mount RUN, COPY .yarn) already on the
# --- latest major alias: byte-for-byte no-op — the floating alias fetches patches ---
mkdir -p "$dtmp/real"
cat > "$dtmp/real/Dockerfile" <<'EOF'
FROM node:24-alpine AS build-base

RUN \
		--mount=type=cache,target=/var/cache/apk\
		apk add build-base

FROM build-base AS yarn

WORKDIR /app

ENV NODE_ENV=production

COPY yarn.lock package.json .yarnrc.yml tsconfig.json ./
COPY .yarn .yarn

RUN \
		--mount=type=cache,target=/app/.yarn/cache\
		yarn

FROM yarn as yarn-build

COPY . .

RUN yarn build

FROM node:24-alpine

WORKDIR /app

COPY --from=yarn-build /app .

CMD ["yarn", "start"]
EOF
cp "$dtmp/real/Dockerfile" "$dtmp/real-before"
real_log="$dtmp/real-log"
(
  latest_node_lts() { printf '24.99.0\n'; }
  REPO_DIR="$dtmp/real" phase_dockerfile
) > "$real_log"
df="$dtmp/real/Dockerfile"
cmp -s "$dtmp/real-before" "$df"
assert_status "$?" 0 \
  "phase_dockerfile on the floating major alias node:24-alpine changes zero bytes"
assert_eq "$(grep -c 'no-op' "$real_log")" "1" \
  "phase_dockerfile logs the base-image step as a no-op when the major alias is current"

# --- patch-pinned but current image: normalized back to the floating major alias ---
mkdir -p "$dtmp/correct"
cat > "$dtmp/correct/Dockerfile" <<'EOF'
FROM node:24.99.0-alpine AS build-base

ENV NODE_ENV=production
ENV COREPACK_ENABLE_DOWNLOAD_PROMPT=0

COPY package.json ./

RUN yarn set version berry

RUN yarn install

FROM node:24.99.0-alpine

CMD ["yarn", "start"]
EOF
cp "$dtmp/correct/Dockerfile" "$dtmp/correct-before"
correct_log="$dtmp/correct-log"
(
  latest_node_lts() { printf '24.99.0\n'; }
  REPO_DIR="$dtmp/correct" phase_dockerfile
) > "$correct_log"
assert_eq "$(grep -c 'FROM node:24-alpine' "$dtmp/correct/Dockerfile")" "2" \
  "phase_dockerfile normalizes a patch-pinned current image back to the floating major alias"

# --- latest_node_lts failure: warn, Dockerfile untouched byte-for-byte ---
mkdir -p "$dtmp/ltsfail"
cat > "$dtmp/ltsfail/Dockerfile" <<'EOF'
FROM node:22-alpine

ENV NODE_ENV=production
ENV COREPACK_ENABLE_DOWNLOAD_PROMPT=0

RUN yarn set version berry

RUN yarn install
EOF
cp "$dtmp/ltsfail/Dockerfile" "$dtmp/ltsfail-before"
ltsfail_err="$dtmp/ltsfail-err"
(
  latest_node_lts() { return 1; }
  REPO_DIR="$dtmp/ltsfail" phase_dockerfile
) > /dev/null 2> "$ltsfail_err"
assert_eq "$(grep -c 'could not resolve the latest node LTS' "$ltsfail_err")" "1" \
  "phase_dockerfile warns when the node LTS lookup fails"
cmp -s "$dtmp/ltsfail-before" "$dtmp/ltsfail/Dockerfile"
assert_status "$?" 0 \
  "phase_dockerfile keeps the Dockerfile byte-for-byte when the LTS lookup fails"

# --- missing Dockerfile: soft skip with a warn ---
miss_err="$dtmp/miss-err"
(
  REPO_DIR="$dtmp/missing-repo" phase_dockerfile
) > /dev/null 2> "$miss_err"
assert_eq "$(grep -c 'Dockerfile not found — skipping phase' "$miss_err")" "1" \
  "phase_dockerfile warns and skips when the Dockerfile is missing"

# Bottom guard: standalone run prints totals; sourced run defers to the runner.
finish_spec
