FROM node:18-alpine AS build-base

RUN \
		--mount=type=cache,target=/var/cache/apk\
		apk add build-base

FROM build-base AS yarn

WORKDIR /app

ENV NODE_ENV=production

COPY yarn.lock package.json .yarnrc.yml tsconfig.json ./
COPY .yarn .yarn

RUN yarn set version berry
RUN \
		--mount=type=cache,target=/app/.yarn/cache\
		yarn

FROM yarn as yarn-build

COPY . .

RUN yarn build

FROM node:18-alpine

WORKDIR /app

COPY --from=yarn-build /app .

CMD ["yarn", "start"]
