FROM --platform=$BUILDPLATFORM node:18-alpine AS builder

WORKDIR /app
ENV NODE_ENV=production

RUN apk add build-base

ARG TARGETARCH
ENV npm_config_arch=$TARGETARCH
COPY yarn.lock .
COPY .yarn .yarn
COPY package.json .
COPY package-lock.json .
COPY .yarnrc.yml .
COPY tsconfig.json .

RUN yarn set version berry
RUN yarn

COPY . .

RUN yarn build

FROM --platform=$TARGETPLATFORM node:18-alpine

WORKDIR /app

COPY --from=builder /app .

CMD ["yarn", "start"]
