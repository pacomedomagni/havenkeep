#!/bin/bash
# HavenKeep Staging Deployment — DO Droplet
# Usage: ./scripts/deploy-staging.sh [command]
# Commands: up, down, migrate, logs, status, rebuild, ssl-init, ssl-renew

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

COMPOSE_FILE="docker-compose.staging.yml"
ENV_FILE=".env.staging"

DOMAINS=(
  "api.havenkeep.kouakoudomagni.com"
  "havenkeep.kouakoudomagni.com"
  "admin.havenkeep.kouakoudomagni.com"
  "partener.havenkeep.kouakoudomagni.com"
)
CERT_EMAIL="info@noslag.com"

if [ ! -f "$ENV_FILE" ]; then
  echo -e "${RED}Error: $ENV_FILE not found${NC}"
  echo "Copy .env.example and fill in your values"
  exit 1
fi

# Check for placeholder values
if grep -q "CHANGE_ME" "$ENV_FILE"; then
  echo -e "${RED}Error: $ENV_FILE still has CHANGE_ME placeholders${NC}"
  echo "Fill in all values before deploying"
  exit 1
fi

CMD=${1:-up}

case "$CMD" in
  ssl-init)
    echo -e "${GREEN}Obtaining SSL certificates...${NC}"
    echo ""
    echo "Step 1: Starting Nginx with HTTP-only config for ACME challenge..."

    # Use initial HTTP-only config
    cp nginx/nginx-initial.conf nginx/nginx.conf.bak 2>/dev/null || true
    docker compose -f "$COMPOSE_FILE" --env-file "$ENV_FILE" up -d nginx

    sleep 3

    echo "Step 2: Requesting certificates from Let's Encrypt..."
    for domain in "${DOMAINS[@]}"; do
      echo -e "  Requesting cert for ${YELLOW}${domain}${NC}..."
      docker compose -f "$COMPOSE_FILE" --env-file "$ENV_FILE" run --rm certbot \
        certbot certonly --webroot \
        --webroot-path=/var/www/certbot \
        --email "$CERT_EMAIL" \
        --agree-tos \
        --no-eff-email \
        -d "$domain"
    done

    echo ""
    echo "Step 3: Switching to full HTTPS config..."
    docker compose -f "$COMPOSE_FILE" --env-file "$ENV_FILE" restart nginx

    echo ""
    echo -e "${GREEN}SSL setup complete!${NC}"
    echo "All domains should now be accessible over HTTPS."
    ;;

  ssl-renew)
    echo -e "${GREEN}Renewing SSL certificates...${NC}"
    docker compose -f "$COMPOSE_FILE" --env-file "$ENV_FILE" run --rm certbot certbot renew
    docker compose -f "$COMPOSE_FILE" --env-file "$ENV_FILE" restart nginx
    echo -e "${GREEN}SSL renewal complete${NC}"
    ;;

  up)
    echo -e "${GREEN}Starting HavenKeep staging...${NC}"
    docker compose -f "$COMPOSE_FILE" --env-file "$ENV_FILE" up -d --build
    echo ""
    echo -e "${GREEN}Services:${NC}"
    echo "  Marketing:  https://havenkeep.kouakoudomagni.com"
    echo "  API:        https://api.havenkeep.kouakoudomagni.com"
    echo "  Admin:      https://admin.havenkeep.kouakoudomagni.com"
    echo "  Partner:    https://partener.havenkeep.kouakoudomagni.com"
    ;;

  down)
    echo -e "${YELLOW}Stopping HavenKeep staging...${NC}"
    docker compose -f "$COMPOSE_FILE" --env-file "$ENV_FILE" down
    ;;

  migrate)
    echo -e "${GREEN}Running database migrations...${NC}"
    docker compose -f "$COMPOSE_FILE" --env-file "$ENV_FILE" --profile migrate run --rm migrate
    ;;

  logs)
    SERVICE=${2:-}
    if [ -n "$SERVICE" ]; then
      docker compose -f "$COMPOSE_FILE" logs -f "$SERVICE"
    else
      docker compose -f "$COMPOSE_FILE" logs -f api partner-dashboard marketing nginx
    fi
    ;;

  status)
    docker compose -f "$COMPOSE_FILE" ps
    echo ""
    echo -e "${GREEN}Health checks:${NC}"
    for domain in "${DOMAINS[@]}"; do
      if curl -f -s --max-time 5 "https://${domain}" > /dev/null 2>&1; then
        echo -e "  ${GREEN}✓${NC} ${domain}"
      else
        echo -e "  ${RED}✗${NC} ${domain}"
      fi
    done
    ;;

  rebuild)
    SERVICE=${2:-}
    if [ -n "$SERVICE" ]; then
      echo -e "${GREEN}Rebuilding $SERVICE...${NC}"
      docker compose -f "$COMPOSE_FILE" --env-file "$ENV_FILE" up -d --build "$SERVICE"
    else
      echo -e "${GREEN}Rebuilding all services...${NC}"
      docker compose -f "$COMPOSE_FILE" --env-file "$ENV_FILE" up -d --build
    fi
    ;;

  *)
    echo "Usage: ./scripts/deploy-staging.sh [command]"
    echo ""
    echo "Commands:"
    echo "  up          Build and start all services"
    echo "  down        Stop all services"
    echo "  migrate     Run database migrations"
    echo "  logs        Tail logs (optionally: logs api)"
    echo "  status      Show service status + health checks"
    echo "  rebuild     Rebuild (optionally: rebuild api)"
    echo "  ssl-init    Obtain SSL certificates (run once on first deploy)"
    echo "  ssl-renew   Renew SSL certificates"
    exit 1
    ;;
esac
