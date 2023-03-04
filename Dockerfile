FROM node:18-alpine

WORKDIR /app
ENV NODE_ENV=production

RUN apk add build-base

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

ENTRYPOINT ["yarn", "start"]
