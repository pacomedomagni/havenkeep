#!/bin/bash
# HavenKeep Staging Deployment — Remote via SSH
# Droplet: 104.248.51.126 (shared with Loni + Restorae)
# Ports: 8080 (HTTP) / 8443 (HTTPS) — avoids conflict with other apps
# Usage: ./scripts/deploy-staging.sh [command]

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

# ─── Config ──────────────────────────────────────────────
REMOTE_USER="root"
REMOTE_HOST="104.248.51.126"
SSH_KEY="$HOME/.ssh/loni_deploy"
REMOTE_DIR="/opt/havenkeep"

COMPOSE_FILE="docker-compose.staging.yml"
ENV_FILE=".env.staging"

DOMAINS=(
  "api.havenkeep.kouakoudomagni.com"
  "havenkeep.kouakoudomagni.com"
  "partener.havenkeep.kouakoudomagni.com"
)
CERT_EMAIL="info@noslag.com"

SSH_CMD="ssh -i $SSH_KEY -o StrictHostKeyChecking=accept-new $REMOTE_USER@$REMOTE_HOST"
SCP_CMD="scp -i $SSH_KEY"

# ─── Helpers ─────────────────────────────────────────────
remote() {
  $SSH_CMD "$@"
}

check_local_env() {
  if [ ! -f "$ENV_FILE" ]; then
    echo -e "${RED}Error: $ENV_FILE not found${NC}"
    echo "Create it from .env.staging.example and fill in your values"
    exit 1
  fi
  if grep -q "CHANGE_ME" "$ENV_FILE"; then
    echo -e "${RED}Error: $ENV_FILE still has CHANGE_ME placeholders${NC}"
    exit 1
  fi
}

# ─── Commands ────────────────────────────────────────────
CMD=${1:-help}

case "$CMD" in

  # ── Sync files to droplet ──
  sync)
    check_local_env
    echo -e "${GREEN}Syncing project to $REMOTE_HOST:$REMOTE_DIR ...${NC}"

    # Create remote directory
    remote "mkdir -p $REMOTE_DIR"

    # Rsync the project (exclude heavy/local stuff)
    rsync -avz --progress \
      -e "ssh -i $SSH_KEY" \
      --exclude='node_modules' \
      --exclude='.next' \
      --exclude='dist' \
      --exclude='build' \
      --exclude='.dart_tool' \
      --exclude='.pub-cache' \
      --exclude='.git' \
      --exclude='apps/mobile' \
      --exclude='.env' \
      --exclude='.env.local' \
      --exclude='.env.staging' \
      --exclude='.env.production' \
      --exclude='*.log' \
      --exclude='.DS_Store' \
      --delete \
      ./ "$REMOTE_USER@$REMOTE_HOST:$REMOTE_DIR/"

    # Send .env.staging separately
    echo -e "${CYAN}Sending .env.staging...${NC}"
    $SCP_CMD "$ENV_FILE" "$REMOTE_USER@$REMOTE_HOST:$REMOTE_DIR/$ENV_FILE"

    echo -e "${GREEN}✓ Sync complete${NC}"
    ;;

  # ── Deploy (sync + build + start) ──
  up)
    check_local_env
    echo -e "${GREEN}Deploying HavenKeep staging...${NC}"
    echo ""

    # Step 1: Sync
    $0 sync

    echo ""
    echo -e "${CYAN}Building and starting containers on remote...${NC}"

    # Step 2: Use HTTP-only nginx config if no SSL certs yet
    remote "cd $REMOTE_DIR && \
      if [ ! -d /var/lib/docker/volumes/havenkeep_certbot_certs/_data/live ]; then \
        echo 'No SSL certs found — using HTTP-only nginx config'; \
        cp nginx/nginx-initial.conf nginx/nginx-active.conf; \
      else \
        echo 'SSL certs found — using HTTPS nginx config'; \
        cp nginx/nginx.conf nginx/nginx-active.conf; \
      fi"

    # Step 3: Build and start
    remote "cd $REMOTE_DIR && \
      docker compose -f $COMPOSE_FILE --env-file $ENV_FILE up -d --build"

    echo ""
    echo -e "${GREEN}═══════════════════════════════════════${NC}"
    echo -e "${GREEN}  HavenKeep staging is live!${NC}"
    echo -e "${GREEN}═══════════════════════════════════════${NC}"
    echo ""
    echo -e "  Marketing:  ${CYAN}http://havenkeep.kouakoudomagni.com:8080${NC}"
    echo -e "  API:        ${CYAN}http://api.havenkeep.kouakoudomagni.com:8080${NC}"
    echo -e "  Partner:    ${CYAN}http://partener.havenkeep.kouakoudomagni.com:8080${NC}"
    echo ""
    echo -e "  ${YELLOW}After setting DNS + SSL: replace http→https and :8080→:8443${NC}"
    ;;

  # ── Stop ──
  down)
    echo -e "${YELLOW}Stopping HavenKeep staging...${NC}"
    remote "cd $REMOTE_DIR && docker compose -f $COMPOSE_FILE --env-file $ENV_FILE down"
    echo -e "${GREEN}✓ Stopped${NC}"
    ;;

  # ── Rebuild a specific service ──
  rebuild)
    SERVICE=${2:-}
    if [ -n "$SERVICE" ]; then
      echo -e "${GREEN}Rebuilding $SERVICE...${NC}"
      $0 sync
      remote "cd $REMOTE_DIR && docker compose -f $COMPOSE_FILE --env-file $ENV_FILE up -d --build $SERVICE"
    else
      echo -e "${GREEN}Rebuilding all services...${NC}"
      $0 sync
      remote "cd $REMOTE_DIR && docker compose -f $COMPOSE_FILE --env-file $ENV_FILE up -d --build"
    fi
    echo -e "${GREEN}✓ Rebuild complete${NC}"
    ;;

  # ── Database migration ──
  migrate)
    echo -e "${GREEN}Running database migrations...${NC}"
    remote "cd $REMOTE_DIR && docker compose -f $COMPOSE_FILE --env-file $ENV_FILE --profile migrate run --rm migrate"
    echo -e "${GREEN}✓ Migration complete${NC}"
    ;;

  # ── Logs ──
  logs)
    SERVICE=${2:-}
    if [ -n "$SERVICE" ]; then
      remote "cd $REMOTE_DIR && docker compose -f $COMPOSE_FILE logs -f --tail=100 $SERVICE"
    else
      remote "cd $REMOTE_DIR && docker compose -f $COMPOSE_FILE logs -f --tail=100 api partner-dashboard marketing nginx"
    fi
    ;;

  # ── Status ──
  status)
    echo -e "${CYAN}Container status:${NC}"
    remote "cd $REMOTE_DIR && docker compose -f $COMPOSE_FILE ps"
    echo ""
    echo -e "${CYAN}Health checks:${NC}"
    for domain in "${DOMAINS[@]}"; do
      HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" --max-time 5 "http://${domain}:8080" 2>/dev/null || echo "000")
      if [ "$HTTP_CODE" = "200" ] || [ "$HTTP_CODE" = "301" ] || [ "$HTTP_CODE" = "302" ]; then
        echo -e "  ${GREEN}✓${NC} ${domain} (HTTP $HTTP_CODE)"
      else
        echo -e "  ${RED}✗${NC} ${domain} (HTTP $HTTP_CODE)"
      fi
    done
    ;;

  # ── SSH into the droplet ──
  ssh)
    echo -e "${CYAN}Connecting to droplet...${NC}"
    $SSH_CMD
    ;;

  # ── SSL init via certbot ──
  ssl-init)
    echo -e "${GREEN}Obtaining SSL certificates...${NC}"
    echo ""
    echo -e "${YELLOW}Note: DNS A records must point to $REMOTE_HOST for all domains.${NC}"
    echo ""

    # Ensure nginx is running with HTTP config for ACME challenges
    remote "cd $REMOTE_DIR && \
      cp nginx/nginx-initial.conf nginx/nginx-active.conf && \
      docker compose -f $COMPOSE_FILE --env-file $ENV_FILE up -d nginx"

    sleep 3

    for domain in "${DOMAINS[@]}"; do
      echo -e "  Requesting cert for ${YELLOW}${domain}${NC}..."
      remote "cd $REMOTE_DIR && \
        docker compose -f $COMPOSE_FILE --env-file $ENV_FILE run --rm certbot \
          certbot certonly --webroot \
          --webroot-path=/var/www/certbot \
          --email $CERT_EMAIL \
          --agree-tos \
          --no-eff-email \
          -d $domain" || echo -e "  ${RED}Failed for $domain${NC}"
    done

    echo ""
    echo -e "${CYAN}Switching to HTTPS nginx config...${NC}"
    remote "cd $REMOTE_DIR && \
      cp nginx/nginx.conf nginx/nginx-active.conf && \
      docker compose -f $COMPOSE_FILE --env-file $ENV_FILE restart nginx"

    echo ""
    echo -e "${GREEN}SSL setup complete!${NC}"
    echo -e "  API:        ${CYAN}https://api.havenkeep.kouakoudomagni.com:8443${NC}"
    echo -e "  Marketing:  ${CYAN}https://havenkeep.kouakoudomagni.com:8443${NC}"
    echo -e "  Partner:    ${CYAN}https://partener.havenkeep.kouakoudomagni.com:8443${NC}"
    ;;

  # ── SSL renew ──
  ssl-renew)
    echo -e "${GREEN}Renewing SSL certificates...${NC}"
    remote "cd $REMOTE_DIR && \
      docker compose -f $COMPOSE_FILE --env-file $ENV_FILE run --rm certbot certbot renew && \
      docker compose -f $COMPOSE_FILE --env-file $ENV_FILE restart nginx"
    echo -e "${GREEN}✓ SSL renewal complete${NC}"
    ;;

  # ── Quick remote shell into a container ──
  exec)
    SERVICE=${2:-api}
    echo -e "${CYAN}Entering $SERVICE container...${NC}"
    remote "cd $REMOTE_DIR && docker compose -f $COMPOSE_FILE exec $SERVICE sh"
    ;;

  # ── Help ──
  *)
    echo ""
    echo -e "${CYAN}HavenKeep Staging Deploy${NC}"
    echo -e "${CYAN}========================${NC}"
    echo ""
    echo "Usage: ./scripts/deploy-staging.sh [command]"
    echo ""
    echo "Commands:"
    echo "  up          Sync + build + start all services"
    echo "  down        Stop all services"
    echo "  sync        Rsync project files to droplet"
    echo "  rebuild     Rebuild (optionally: rebuild api)"
    echo "  migrate     Run database migrations"
    echo "  logs        Tail logs (optionally: logs api)"
    echo "  status      Show container status + health checks"
    echo "  ssh         SSH into the droplet"
    echo "  exec        Shell into container (optionally: exec api)"
    echo "  ssl-init    Obtain SSL certs (run after DNS is set)"
    echo "  ssl-renew   Renew SSL certificates"
    echo ""
    echo -e "Droplet: ${YELLOW}$REMOTE_HOST${NC}"
    echo -e "Remote:  ${YELLOW}$REMOTE_DIR${NC}"
    echo ""
    exit 1
    ;;
esac
