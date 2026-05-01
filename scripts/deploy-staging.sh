#!/bin/bash
# ═══════════════════════════════════════════════════════════════════════════════
# HavenKeep Staging Deployment — Local Build + SSH Push
# ═══════════════════════════════════════════════════════════════════════════════
# Droplet: 104.248.51.126 (shared with Loni + Restorae)
# Ports: 20** series (2000 API, 2001 Dashboard, 2002 Marketing)
# SSL: Handled by Loni's Caddy
#
# Usage: ./scripts/deploy-staging.sh [command]
# ═══════════════════════════════════════════════════════════════════════════════

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
PLATFORM="linux/amd64"

# Image names
API_IMAGE="havenkeep-api:staging"
DASHBOARD_IMAGE="havenkeep-dashboard:staging"
MARKETING_IMAGE="havenkeep-marketing:staging"

# Tar output directory
TAR_DIR=".docker-images"

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

  # ── Build images locally for AMD64 ──
  build)
    SERVICE=${2:-all}
    echo -e "${GREEN}Building images for $PLATFORM ...${NC}"
    mkdir -p "$TAR_DIR"

    if [ "$SERVICE" = "all" ] || [ "$SERVICE" = "api" ]; then
      echo -e "${CYAN}  Building API...${NC}"
      docker build --platform "$PLATFORM" \
        -f apps/api/Dockerfile \
        --target production \
        -t "$API_IMAGE" \
        apps/api
      echo -e "${CYAN}  Saving API image...${NC}"
      docker save "$API_IMAGE" | gzip > "$TAR_DIR/api.tar.gz"
    fi

    if [ "$SERVICE" = "all" ] || [ "$SERVICE" = "dashboard" ]; then
      echo -e "${CYAN}  Building Partner Dashboard...${NC}"
      docker build --platform "$PLATFORM" \
        -f apps/partner-dashboard/Dockerfile \
        --target production \
        --build-arg NEXT_PUBLIC_API_URL=https://api.staging.havenkeep.app \
        -t "$DASHBOARD_IMAGE" \
        apps/partner-dashboard
      echo -e "${CYAN}  Saving Dashboard image...${NC}"
      docker save "$DASHBOARD_IMAGE" | gzip > "$TAR_DIR/dashboard.tar.gz"
    fi

    if [ "$SERVICE" = "all" ] || [ "$SERVICE" = "marketing" ]; then
      echo -e "${CYAN}  Building Marketing site...${NC}"
      docker build --platform "$PLATFORM" \
        -f apps/marketing/Dockerfile.staging \
        -t "$MARKETING_IMAGE" \
        apps/marketing
      echo -e "${CYAN}  Saving Marketing image...${NC}"
      docker save "$MARKETING_IMAGE" | gzip > "$TAR_DIR/marketing.tar.gz"
    fi

    echo ""
    echo -e "${GREEN}Images built:${NC}"
    ls -lh "$TAR_DIR"/*.tar.gz 2>/dev/null
    echo -e "${GREEN}Done.${NC}"
    ;;

  # ── Push image tarballs to server ──
  push)
    SERVICE=${2:-all}
    echo -e "${GREEN}Pushing images to $REMOTE_HOST ...${NC}"

    remote "mkdir -p $REMOTE_DIR/images"

    if [ "$SERVICE" = "all" ] || [ "$SERVICE" = "api" ]; then
      echo -e "${CYAN}  Uploading API image...${NC}"
      $SCP_CMD "$TAR_DIR/api.tar.gz" "$REMOTE_USER@$REMOTE_HOST:$REMOTE_DIR/images/api.tar.gz"
      echo -e "${CYAN}  Loading API image on server...${NC}"
      remote "gunzip -c $REMOTE_DIR/images/api.tar.gz | docker load"
    fi

    if [ "$SERVICE" = "all" ] || [ "$SERVICE" = "dashboard" ]; then
      echo -e "${CYAN}  Uploading Dashboard image...${NC}"
      $SCP_CMD "$TAR_DIR/dashboard.tar.gz" "$REMOTE_USER@$REMOTE_HOST:$REMOTE_DIR/images/dashboard.tar.gz"
      echo -e "${CYAN}  Loading Dashboard image on server...${NC}"
      remote "gunzip -c $REMOTE_DIR/images/dashboard.tar.gz | docker load"
    fi

    if [ "$SERVICE" = "all" ] || [ "$SERVICE" = "marketing" ]; then
      echo -e "${CYAN}  Uploading Marketing image...${NC}"
      $SCP_CMD "$TAR_DIR/marketing.tar.gz" "$REMOTE_USER@$REMOTE_HOST:$REMOTE_DIR/images/marketing.tar.gz"
      echo -e "${CYAN}  Loading Marketing image on server...${NC}"
      remote "gunzip -c $REMOTE_DIR/images/marketing.tar.gz | docker load"
    fi

    echo -e "${GREEN}All images pushed and loaded.${NC}"
    ;;

  # ── Sync config files (compose, env, monitoring) ──
  sync)
    check_local_env
    echo -e "${GREEN}Syncing config files to $REMOTE_HOST:$REMOTE_DIR ...${NC}"

    remote "mkdir -p $REMOTE_DIR/monitoring"

    # Send compose file
    $SCP_CMD "$COMPOSE_FILE" "$REMOTE_USER@$REMOTE_HOST:$REMOTE_DIR/$COMPOSE_FILE"

    # Send env file
    $SCP_CMD "$ENV_FILE" "$REMOTE_USER@$REMOTE_HOST:$REMOTE_DIR/$ENV_FILE"

    # Send monitoring configs
    $SCP_CMD monitoring/loki-config.yml "$REMOTE_USER@$REMOTE_HOST:$REMOTE_DIR/monitoring/loki-config.yml"
    $SCP_CMD monitoring/promtail-config.yml "$REMOTE_USER@$REMOTE_HOST:$REMOTE_DIR/monitoring/promtail-config.yml"

    echo -e "${GREEN}Sync complete.${NC}"
    ;;

  # ── Deploy (start/restart services on server) ──
  deploy)
    echo -e "${GREEN}Deploying HavenKeep staging...${NC}"

    echo -e "${CYAN}Starting infrastructure...${NC}"
    remote "cd $REMOTE_DIR && docker compose -f $COMPOSE_FILE --env-file $ENV_FILE up -d postgres redis minio"

    echo "Waiting for PostgreSQL..."
    for i in $(seq 1 30); do
      if remote "cd $REMOTE_DIR && docker compose -f $COMPOSE_FILE --env-file $ENV_FILE exec -T postgres pg_isready -U havenkeep" 2>/dev/null; then
        echo -e "${GREEN}PostgreSQL is ready.${NC}"
        break
      fi
      if [ "$i" -eq 30 ]; then
        echo -e "${RED}PostgreSQL failed to start.${NC}"
        exit 1
      fi
      sleep 2
    done

    echo -e "${CYAN}Starting all services...${NC}"
    remote "cd $REMOTE_DIR && docker compose -f $COMPOSE_FILE --env-file $ENV_FILE up -d --no-build"

    echo ""
    echo -e "${GREEN}═══════════════════════════════════════${NC}"
    echo -e "${GREEN}  HavenKeep staging deployed!${NC}"
    echo -e "${GREEN}═══════════════════════════════════════${NC}"
    echo ""
    echo -e "  API:        ${CYAN}https://api.staging.havenkeep.app${NC}"
    echo -e "  Marketing:  ${CYAN}https://staging.havenkeep.app${NC}"
    echo -e "  Dashboard:  ${CYAN}https://partners.staging.havenkeep.app${NC}"
    echo ""
    ;;

  # ── Full pipeline: build + push + sync + deploy ──
  up)
    check_local_env
    echo -e "${GREEN}Full deploy: build → push → sync → deploy${NC}"
    echo ""
    $0 build "${2:-all}"
    echo ""
    $0 push "${2:-all}"
    echo ""
    $0 sync
    echo ""
    $0 deploy
    ;;

  # ── Stop ──
  down)
    echo -e "${YELLOW}Stopping HavenKeep staging...${NC}"
    remote "cd $REMOTE_DIR && docker compose -f $COMPOSE_FILE --env-file $ENV_FILE down"
    echo -e "${GREEN}Stopped.${NC}"
    ;;

  # ── Database migration ──
  migrate)
    echo -e "${GREEN}Running database migrations...${NC}"
    remote "cd $REMOTE_DIR && docker compose -f $COMPOSE_FILE --env-file $ENV_FILE --profile migrate run --rm migrate"
    echo -e "${GREEN}Migration complete.${NC}"
    ;;

  # ── Logs ──
  logs)
    SERVICE=${2:-}
    if [ -n "$SERVICE" ]; then
      remote "cd $REMOTE_DIR && docker compose -f $COMPOSE_FILE logs -f --tail=100 $SERVICE"
    else
      remote "cd $REMOTE_DIR && docker compose -f $COMPOSE_FILE logs -f --tail=100 api partner-dashboard marketing"
    fi
    ;;

  # ── Status ──
  status)
    echo -e "${CYAN}Container status:${NC}"
    remote "cd $REMOTE_DIR && docker compose -f $COMPOSE_FILE ps"
    echo ""
    echo -e "${CYAN}Health checks:${NC}"
    for endpoint in "API:2000/health" "Dashboard:2001" "Marketing:2002"; do
      NAME="${endpoint%%:*}"
      URL="http://$REMOTE_HOST:${endpoint#*:}"
      HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" --max-time 5 "$URL" 2>/dev/null || echo "000")
      if [ "$HTTP_CODE" = "200" ] || [ "$HTTP_CODE" = "301" ] || [ "$HTTP_CODE" = "302" ]; then
        echo -e "  ${GREEN}✓${NC} ${NAME} (HTTP $HTTP_CODE)"
      else
        echo -e "  ${RED}✗${NC} ${NAME} (HTTP $HTTP_CODE)"
      fi
    done
    ;;

  # ── SSH into the droplet ──
  ssh)
    echo -e "${CYAN}Connecting to droplet...${NC}"
    $SSH_CMD
    ;;

  # ── Quick remote shell into a container ──
  exec)
    SERVICE=${2:-api}
    echo -e "${CYAN}Entering $SERVICE container...${NC}"
    remote "cd $REMOTE_DIR && docker compose -f $COMPOSE_FILE exec $SERVICE sh"
    ;;

  # ── Clean up local tar files ──
  clean)
    echo -e "${YELLOW}Removing local image tarballs...${NC}"
    rm -rf "$TAR_DIR"
    echo -e "${GREEN}Cleaned.${NC}"
    ;;

  # ── Help ──
  *)
    echo ""
    echo -e "${CYAN}HavenKeep Staging Deploy${NC}"
    echo -e "${CYAN}========================${NC}"
    echo ""
    echo "Usage: ./scripts/deploy-staging.sh [command] [service]"
    echo ""
    echo "Commands:"
    echo "  up [svc]      Full pipeline: build + push + sync + deploy"
    echo "  build [svc]   Build images locally for AMD64"
    echo "  push [svc]    Push image tarballs to server + docker load"
    echo "  sync          Sync compose, env, and monitoring configs"
    echo "  deploy        Start/restart services on server (no build)"
    echo "  down          Stop all services"
    echo "  migrate       Run database migrations"
    echo "  logs [svc]    Tail logs (e.g. logs api)"
    echo "  status        Show container status + health checks"
    echo "  ssh           SSH into the droplet"
    echo "  exec [svc]    Shell into container (default: api)"
    echo "  clean         Remove local .docker-images/ tarballs"
    echo ""
    echo "Services: all (default), api, dashboard, marketing"
    echo ""
    echo -e "Droplet: ${YELLOW}$REMOTE_HOST${NC}"
    echo -e "Remote:  ${YELLOW}$REMOTE_DIR${NC}"
    echo -e "Ports:   ${YELLOW}2000 (API) / 2001 (Dashboard) / 2002 (Marketing)${NC}"
    echo ""
    exit 1
    ;;
esac
