# Base image
FROM node:20-alpine AS base

# Development stage
FROM base AS development
WORKDIR /app

COPY package.json package-lock.json* ./
RUN npm install

COPY . .

EXPOSE 4321

CMD ["npx", "astro", "dev", "--host"]

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

EXPOSE 4321

CMD ["npx", "astro", "preview", "--host"]
