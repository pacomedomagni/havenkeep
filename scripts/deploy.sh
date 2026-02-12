#!/bin/bash
# HavenKeep Deployment Script

set -e  # Exit on error

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Configuration
ENV=${1:-staging}  # Default to staging
COMPONENT=${2:-all}  # Default to all components

echo -e "${GREEN}🚀 HavenKeep Deployment Script${NC}"
echo -e "${YELLOW}Environment: $ENV${NC}"
echo -e "${YELLOW}Component: $COMPONENT${NC}"
echo ""

# Confirm production deployment
if [ "$ENV" = "production" ]; then
  echo -e "${RED}⚠️  WARNING: Deploying to PRODUCTION${NC}"
  read -p "Are you sure? Type 'yes' to continue: " confirm
  if [ "$confirm" != "yes" ]; then
    echo "Deployment cancelled"
    exit 1
  fi
fi

# Load environment variables
if [ "$ENV" = "production" ]; then
  ENV_FILE=".env.production"
else
  ENV_FILE=".env.staging"
fi

if [ ! -f "$ENV_FILE" ]; then
  echo -e "${RED}❌ Error: $ENV_FILE not found${NC}"
  exit 1
fi

source "$ENV_FILE"

# Deploy Marketing Site
deploy_marketing() {
  echo -e "${GREEN}📱 Deploying Marketing Site...${NC}"
  cd apps/marketing
  npm install
  npm run build

  if [ "$ENV" = "production" ]; then
    npx wrangler pages deploy dist --project-name=havenkeep --branch=main
  else
    npx wrangler pages deploy dist --project-name=havenkeep-staging
  fi

  cd ../..
  echo -e "${GREEN}✅ Marketing site deployed${NC}"
}

# Deploy Admin Dashboard
deploy_admin() {
  echo -e "${GREEN}🔧 Deploying Admin Dashboard...${NC}"
  cd apps/partner-dashboard
  npm install

  if [ "$ENV" = "production" ]; then
    npx vercel deploy --prod
  else
    npx vercel deploy
  fi

  cd ../..
  echo -e "${GREEN}✅ Admin dashboard deployed${NC}"
}

# Run Database Migrations
migrate_database() {
  echo -e "${GREEN}💾 Running Database Migrations...${NC}"

  if [ "$ENV" = "production" ]; then
    echo -e "${RED}⚠️  Running PRODUCTION migration${NC}"
    read -p "Confirm production migration? (yes/no): " confirm
    if [ "$confirm" != "yes" ]; then
      echo "Migration skipped"
      return
    fi
  fi

  # Create backup before migration
  echo "Creating database backup..."
  mkdir -p backups
  pg_dump "$DATABASE_URL" > "backups/backup-$(date +%Y%m%d-%H%M%S).sql"

  # Run migrations via Express API migration runner
  cd apps/api
  npx ts-node src/db/migrations/run-migration.ts
  cd ../..

  echo -e "${GREEN}✅ Migrations complete${NC}"
}

# Health Check
health_check() {
  echo -e "${GREEN}🏥 Running Health Checks...${NC}"

  # Check marketing site
  if curl -f -s "https://havenkeep.com" > /dev/null; then
    echo -e "${GREEN}✅ Marketing site is up${NC}"
  else
    echo -e "${RED}❌ Marketing site is down${NC}"
  fi

  # Check admin dashboard
  if curl -f -s "https://admin.havenkeep.com" > /dev/null; then
    echo -e "${GREEN}✅ Admin dashboard is up${NC}"
  else
    echo -e "${RED}❌ Admin dashboard is down${NC}"
  fi

  # Check Express API
  if curl -f -s "$API_URL/api/v1/health" > /dev/null 2>&1; then
    echo -e "${GREEN}✅ Express API is up${NC}"
  else
    echo -e "${RED}❌ Express API is down${NC}"
  fi
}

# Main deployment logic
case "$COMPONENT" in
  marketing)
    deploy_marketing
    ;;
  admin)
    deploy_admin
    ;;
  database)
    migrate_database
    ;;
  all)
    deploy_marketing
    deploy_admin
    migrate_database
    health_check
    ;;
  *)
    echo -e "${RED}❌ Unknown component: $COMPONENT${NC}"
    echo "Usage: ./deploy.sh [staging|production] [marketing|admin|database|all]"
    exit 1
    ;;
esac

echo ""
echo -e "${GREEN}🎉 Deployment Complete!${NC}"
echo -e "${YELLOW}Environment: $ENV${NC}"
echo ""
echo "URLs:"
echo "  Marketing: https://havenkeep.com"
echo "  Admin:     https://admin.havenkeep.com"
echo ""
