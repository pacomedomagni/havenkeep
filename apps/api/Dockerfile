# Base image
FROM node:20-alpine AS base

# Install pnpm
RUN npm install -g pnpm

# Builder stage
FROM base AS builder
WORKDIR /app

# Copy workspace files
COPY package.json pnpm-workspace.yaml pnpm-lock.yaml* ./
COPY apps/api/package.json ./apps/api/

# Install dependencies
RUN pnpm install --frozen-lockfile

# Copy source code
COPY apps/api ./apps/api

# Build the application
WORKDIR /app/apps/api
RUN pnpm run build

# Production stage
FROM base AS production
WORKDIR /app

# Copy dependencies and built files
COPY --from=builder /app/node_modules ./node_modules
COPY --from=builder /app/apps/api/node_modules ./apps/api/node_modules
COPY --from=builder /app/apps/api/dist ./apps/api/dist
COPY --from=builder /app/apps/api/package.json ./apps/api/

# Copy database files
COPY apps/api/src/db ./apps/api/src/db

WORKDIR /app/apps/api

EXPOSE 3000

CMD ["node", "dist/index.js"]

# Development stage
FROM base AS development
WORKDIR /app

# Copy workspace files
COPY package.json pnpm-workspace.yaml ./
COPY apps/api/package.json ./apps/api/package.json

# Install all dependencies
RUN pnpm install --no-frozen-lockfile

# Copy source code
COPY apps/api ./apps/api

WORKDIR /app/apps/api

EXPOSE 3000

CMD ["sh", "-c", "pnpm run dev"]
