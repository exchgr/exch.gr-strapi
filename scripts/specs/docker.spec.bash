#!/usr/bin/env bash
# scripts/specs/docker.spec.bash — spec for scripts/lib/docker.bash (dockerfile
# phase: node LTS base-image rewrite only — the berry/COREPACK restore cases
# were removed along with the ensure_dockerfile_* helpers they covered).
# latest_node_lts is shadowed here; its production wiring lives in
# lookups.spec.bash — not duplicated.
# Standalone: bash scripts/specs/docker.spec.bash
set -u
SPEC_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/specs/common.spec.bash
source "$SPEC_DIR/common.spec.bash"
# shellcheck source=scripts/lib/docker.bash
source "$SPEC_DIR/../lib/docker.bash"
# The sourced lib hardens IFS; restore the default for spec-internal string ops.
IFS=$' \t\n'

dtmp="$(mktemp -d)"

# --- fresh fixture: node:22-alpine rewritten to the latest node LTS ---
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
assert_eq "$(grep -c 'FROM node:24.99.0-alpine' "$df")" "2" \
  "phase_dockerfile rewrites every node:22-alpine stage to the latest node LTS"
assert_eq "$(grep -c 'FROM node:22-alpine' "$df")" "0" \
  "phase_dockerfile leaves no stale node:22-alpine stages"

# --- real-Dockerfile shape (multi-line cache-mount RUN, COPY .yarn): both stages bumped ---
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
(
  latest_node_lts() { printf '24.99.0\n'; }
  REPO_DIR="$dtmp/real" phase_dockerfile
) > /dev/null
df="$dtmp/real/Dockerfile"
assert_eq "$(grep -c 'FROM node:24.99.0-alpine' "$df")" "2" \
  "phase_dockerfile rewrites both node:24-alpine stages in the real Dockerfile shape"

# --- already correct: byte-for-byte no-op ---
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
cmp -s "$dtmp/correct-before" "$dtmp/correct/Dockerfile"
assert_status "$?" 0 \
  "phase_dockerfile on an already-correct Dockerfile changes zero bytes"
assert_eq "$(grep -c 'no-op' "$correct_log")" "1" \
  "phase_dockerfile logs the base-image step as a no-op on an already-correct Dockerfile"

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

rm -rf "$dtmp"

# Bottom guard: standalone run prints totals; sourced run defers to the runner.
if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  printf 'PASS: %d FAIL: %d\n' "$PASS" "$FAIL"
  if [[ "$FAIL" -gt 0 ]]; then
    exit 1
  fi
  exit 0
fi
