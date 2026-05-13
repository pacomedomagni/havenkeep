# Base image
FROM node:20-alpine@sha256:fb4cd12c85ee03686f6af5362a0b0d56d50c58a04632e6c0fb8363f609372293 AS base

# Development stage
FROM base AS development
WORKDIR /app

COPY package.json package-lock.json* ./
# Use npm ci so local images match the lockfile, matching the builder stage.
RUN npm ci

COPY . .

EXPOSE 3000

CMD ["npx", "tsx", "watch", "src/index.ts"]

# Builder stage
FROM base AS builder
WORKDIR /app

COPY package.json package-lock.json* ./
RUN npm ci

COPY . .
RUN npm run build

# Production stage
FROM base AS production
WORKDIR /app

RUN apk add --no-cache curl

COPY --from=builder /app/node_modules ./node_modules
COPY --from=builder /app/dist ./dist
COPY --from=builder /app/package.json ./
# Ship the full src/ tree so `npm run db:migrate` and `npm run db:seed`
# (both `tsx src/...`) can resolve their cross-directory imports — seed
# pulls in src/config + src/utils, not just src/db. The runtime entrypoint
# is still `node dist/index.js`; src/ is only walked by admin commands.
COPY --from=builder /app/src ./src
# Copy SQL migration files alongside compiled JS so `node dist/db/migrations/run-migration.js` works
COPY --from=builder /app/src/db/schema.sql ./dist/db/schema.sql
COPY --from=builder /app/src/db/migrations/*.sql ./dist/db/migrations/

EXPOSE 3000

CMD ["node", "dist/index.js"]
