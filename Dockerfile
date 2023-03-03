FROM node:18-alpine

RUN apk add build-base
RUN yarn set version berry
RUN yarn
