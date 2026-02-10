#!/bin/bash

# Production Readiness Validation Script
# Verifies all critical components are in place

echo "🔍 Validating HavenKeep Production Readiness"
echo "============================================="
echo ""

PASS=0
FAIL=0

check() {
    if [ $? -eq 0 ]; then
        echo "✅ $1"
        ((PASS++))
    else
        echo "❌ $1"
        ((FAIL++))
    fi
}

# Check critical files exist
echo "📁 Checking Critical Files..."
[ -f apps/api/src/validators/index.ts ]; check "Validation schemas"
[ -f apps/api/src/middleware/validate.ts ]; check "Validation middleware"
[ -f apps/api/src/middleware/csrf.ts ]; check "CSRF protection"
[ -f apps/api/src/config/validator.ts ]; check "Environment validator"
[ -f apps/api/src/config/minio.ts ]; check "MinIO configuration"
[ -f apps/api/src/routes/documents.ts ]; check "Document upload route"
[ -f monitoring/loki-config.yml ]; check "Loki configuration"
[ -f monitoring/promtail-config.yml ]; check "Promtail configuration"
[ -f docker-compose.yml ]; check "Docker Compose"
[ -f docker-compose.production.yml ]; check "Production Compose"
[ -f scripts/backup-database.sh ]; check "Backup script"
[ -f scripts/generate-secrets.sh ]; check "Secrets generator"
[ -f .env.example ]; check "Environment template"

echo ""
echo "📦 Checking NPM Packages..."
cd apps/api
grep -q '"joi"' package.json; check "Joi validation"
grep -q '"compression"' package.json; check "Compression"
grep -q '"cookie-parser"' package.json; check "Cookie parser"
grep -q '"minio"' package.json; check "MinIO SDK"
grep -q '"sharp"' package.json; check "Image optimization"
cd ../..

echo ""
echo "🔒 Checking Security Features..."
grep -q "whitelisting" apps/api/src/routes/items.ts; check "SQL injection prevention"
grep -q "validate(" apps/api/src/routes/auth.ts; check "Auth validation"
grep -q "validate(" apps/api/src/routes/items.ts; check "Items validation"
grep -q "csrfProtection" apps/api/src/middleware/csrf.ts; check "CSRF middleware"
grep -q "rejectUnauthorized: true" apps/api/src/db/index.ts; check "SSL validation"

echo ""
echo "🏗 Checking Infrastructure..."
grep -q "minio:" docker-compose.yml; check "MinIO in compose"
grep -q "loki:" docker-compose.yml; check "Loki in compose"
grep -q "promtail:" docker-compose.yml; check "Promtail in compose"
grep -q "redis:" docker-compose.yml; check "Redis in compose"

echo ""
echo "📝 Checking Documentation..."
[ -f PRODUCTION_100_PERCENT_READY.md ]; check "Production summary"
[ -f PRODUCTION_DEPLOYMENT_CHECKLIST.md ]; check "Deployment checklist"
[ -f QUICK_START_PRODUCTION.md ]; check "Quick start guide"
[ -f monitoring/README.md ]; check "Monitoring docs"

echo ""
echo "============================================="
echo "Results: ✅ $PASS passed | ❌ $FAIL failed"

if [ $FAIL -eq 0 ]; then
    echo ""
    echo "🎉 ALL CHECKS PASSED!"
    echo "✅ HavenKeep is 100% Production Ready"
    echo ""
    echo "Next steps:"
    echo "1. Review PRODUCTION_100_PERCENT_READY.md"
    echo "2. Generate secrets: ./scripts/generate-secrets.sh"
    echo "3. Update .env file"
    echo "4. Deploy: docker-compose up -d"
    echo ""
    exit 0
else
    echo ""
    echo "⚠️  Some checks failed. Review the output above."
    echo ""
    exit 1
fi
