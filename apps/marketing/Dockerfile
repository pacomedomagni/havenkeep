# Base image
FROM node:20-alpine AS base

# Install pnpm
RUN npm install -g pnpm

# Builder stage
FROM base AS builder
WORKDIR /app

# Copy workspace files
COPY package.json pnpm-workspace.yaml pnpm-lock.yaml* ./
COPY apps/marketing/package.json ./apps/marketing/

# Install dependencies
RUN pnpm install --frozen-lockfile

# Copy source code
COPY apps/marketing ./apps/marketing

# Build the application
WORKDIR /app/apps/marketing
RUN pnpm run build

# Production stage
FROM base AS production
WORKDIR /app

# Copy dependencies and built files
COPY --from=builder /app/node_modules ./node_modules
COPY --from=builder /app/apps/marketing/node_modules ./apps/marketing/node_modules
COPY --from=builder /app/apps/marketing/dist ./apps/marketing/dist
COPY --from=builder /app/apps/marketing/package.json ./apps/marketing/

WORKDIR /app/apps/marketing

EXPOSE 4321

CMD ["pnpm", "run", "preview"]

# Development stage
FROM base AS development
WORKDIR /app

# Copy workspace files
COPY package.json pnpm-workspace.yaml ./
COPY apps/marketing/package.json ./apps/marketing/package.json

# Install all dependencies
RUN pnpm install --no-frozen-lockfile

# Copy source code
COPY apps/marketing ./apps/marketing

WORKDIR /app/apps/marketing

EXPOSE 4321

CMD ["sh", "-c", "pnpm run dev -- --host"]
