# Base image
FROM node:20-alpine AS base

# Development stage
FROM base AS development
WORKDIR /app

COPY package.json package-lock.json* ./
RUN npm install

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

COPY --from=builder /app/node_modules ./node_modules
COPY --from=builder /app/dist ./dist
COPY --from=builder /app/package.json ./
COPY --from=builder /app/src/db ./src/db

EXPOSE 3000

CMD ["node", "dist/index.js"]
