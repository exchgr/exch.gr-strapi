FROM node:18-alpine

WORKDIR /app
ENV NODE_ENV=production

RUN apk add build-base

COPY . .

RUN yarn set version berry
RUN yarn
RUN yarn build
