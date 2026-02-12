#!/bin/bash
# HavenKeep Staging Deployment — DO Droplet
# Usage: ./scripts/deploy-staging.sh [command]
# Commands: up, down, migrate, logs, status, rebuild

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

COMPOSE_FILE="docker-compose.staging.yml"
ENV_FILE=".env.staging"

if [ ! -f "$ENV_FILE" ]; then
  echo -e "${RED}Error: $ENV_FILE not found${NC}"
  echo "Copy .env.staging.example and fill in your values"
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
  up)
    echo -e "${GREEN}Starting HavenKeep staging...${NC}"
    docker compose -f "$COMPOSE_FILE" --env-file "$ENV_FILE" up -d --build
    echo ""
    echo -e "${GREEN}Services:${NC}"
    echo "  Marketing:  http://localhost:8000"
    echo "  API:        http://localhost:8001"
    echo "  Dashboard:  http://localhost:8002"
    echo "  MinIO:      http://localhost:8003 (API) / http://localhost:8004 (Console)"
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
      docker compose -f "$COMPOSE_FILE" logs -f api partner-dashboard marketing
    fi
    ;;

  status)
    docker compose -f "$COMPOSE_FILE" ps
    echo ""
    echo -e "${GREEN}Health checks:${NC}"
    for svc in api partner-dashboard marketing; do
      case $svc in
        api)              URL="http://localhost:8001/api/v1/health" ;;
        partner-dashboard) URL="http://localhost:8002" ;;
        marketing)        URL="http://localhost:8000" ;;
      esac
      if curl -f -s --max-time 3 "$URL" > /dev/null 2>&1; then
        echo -e "  ${GREEN}✓${NC} $svc"
      else
        echo -e "  ${RED}✗${NC} $svc"
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
    echo "Usage: ./scripts/deploy-staging.sh [up|down|migrate|logs|status|rebuild]"
    echo ""
    echo "Commands:"
    echo "  up        Build and start all services"
    echo "  down      Stop all services"
    echo "  migrate   Run database migrations"
    echo "  logs      Tail logs (optionally: logs api)"
    echo "  status    Show service status + health checks"
    echo "  rebuild   Rebuild (optionally: rebuild api)"
    exit 1
    ;;
esac
