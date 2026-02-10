# Base image
FROM node:20-alpine AS base

# Install pnpm
RUN npm install -g pnpm

# Builder stage
FROM base AS builder
WORKDIR /app

# Copy workspace files
COPY package.json pnpm-workspace.yaml pnpm-lock.yaml* ./
COPY apps/partner-dashboard/package.json ./apps/partner-dashboard/

# Install dependencies
RUN pnpm install --frozen-lockfile

# Copy source code
COPY apps/partner-dashboard ./apps/partner-dashboard

# Build the application
WORKDIR /app/apps/partner-dashboard
RUN pnpm run build

# Production stage
FROM base AS production
WORKDIR /app

# Copy dependencies and built files
COPY --from=builder /app/node_modules ./node_modules
COPY --from=builder /app/apps/partner-dashboard/node_modules ./apps/partner-dashboard/node_modules
COPY --from=builder /app/apps/partner-dashboard/.next ./apps/partner-dashboard/.next
COPY --from=builder /app/apps/partner-dashboard/public ./apps/partner-dashboard/public
COPY --from=builder /app/apps/partner-dashboard/package.json ./apps/partner-dashboard/
COPY --from=builder /app/apps/partner-dashboard/next.config.js ./apps/partner-dashboard/

WORKDIR /app/apps/partner-dashboard

EXPOSE 3001

CMD ["pnpm", "run", "start"]

# Development stage
FROM base AS development
WORKDIR /app

# Copy workspace files
COPY package.json pnpm-workspace.yaml ./
COPY apps/partner-dashboard/package.json ./apps/partner-dashboard/package.json

# Install all dependencies
RUN pnpm install --no-frozen-lockfile

# Copy source code
COPY apps/partner-dashboard ./apps/partner-dashboard

WORKDIR /app/apps/partner-dashboard

EXPOSE 3001

CMD ["sh", "-c", "pnpm run dev"]
