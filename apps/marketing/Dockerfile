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

# Production stage — serve static output with nginx.
# We don't use `astro preview` because it (in Astro 4) doesn't accept arbitrary
# Host headers and has no config to permit them behind a reverse proxy.
FROM nginx:alpine AS production
RUN apk add --no-cache wget
COPY --from=builder /app/dist /usr/share/nginx/html

# Health endpoint (nginx default for /health)
RUN printf 'server {\n  listen 4321;\n  server_name _;\n  root /usr/share/nginx/html;\n  index index.html;\n  location = /health { default_type text/plain; return 200 "ok\\n"; }\n  location / { try_files $uri $uri/ $uri.html /index.html; }\n}\n' > /etc/nginx/conf.d/default.conf \
    && rm -f /etc/nginx/conf.d/default.conf.bak

EXPOSE 4321

CMD ["nginx", "-g", "daemon off;"]
