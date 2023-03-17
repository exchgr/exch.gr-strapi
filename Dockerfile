FROM --platform=$BUILDPLATFORM node:18-alpine AS build-base

RUN \
		--mount=type=cache,target=/var/cache/apk\
		apk add build-base

FROM --platform=$BUILDPLATFORM build-base AS yarn

WORKDIR /app

ARG TARGETARCH
ENV npm_config_arch=$TARGETARCH
ENV NODE_ENV=production

COPY yarn.lock package.json package-lock.json .yarnrc.yml tsconfig.json ./
COPY .yarn .yarn

RUN yarn set version berry
RUN \
		--mount=type=cache,target=/app/.yarn/cache\
		yarn

FROM --platform=$BUILDPLATFORM yarn as yarn-build

COPY . .

RUN yarn build

FROM --platform=$TARGETPLATFORM node:18-alpine

WORKDIR /app

COPY --from=yarn-build /app .

CMD ["yarn", "start"]
