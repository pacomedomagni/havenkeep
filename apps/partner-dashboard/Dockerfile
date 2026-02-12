# Base image
FROM node:20-alpine AS base

# Development stage
FROM base AS development
WORKDIR /app

COPY package.json package-lock.json* ./
RUN npm install

COPY . .

EXPOSE 3001

CMD ["npx", "next", "dev", "--port", "3001"]

# Builder stage
FROM base AS builder
WORKDIR /app

COPY package.json package-lock.json* ./
RUN npm ci

COPY . .

# API_URL is used at runtime via next.config.js rewrites (server-side)
# NEXT_PUBLIC_API_URL is baked into client JS at build time
ARG NEXT_PUBLIC_API_URL=http://localhost:8001
ENV NEXT_PUBLIC_API_URL=${NEXT_PUBLIC_API_URL}

RUN npm run build

# Production stage
FROM base AS production
WORKDIR /app

COPY --from=builder /app/node_modules ./node_modules
COPY --from=builder /app/.next ./.next
COPY --from=builder /app/public ./public
COPY --from=builder /app/package.json ./
COPY --from=builder /app/next.config.js ./

EXPOSE 3001

CMD ["npx", "next", "start", "--port", "3001"]
