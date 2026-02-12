#!/bin/bash

# Generate Production Secrets Script
# This script generates secure random secrets for production use

set -e

SECRETS_DIR="./secrets"
mkdir -p "$SECRETS_DIR"

echo "🔐 Generating production secrets..."
echo "=================================="
echo ""

# Function to generate a secure random string
generate_secret() {
    openssl rand -hex 32
}

# Generate JWT secret
if [ ! -f "$SECRETS_DIR/jwt_secret.txt" ]; then
    generate_secret > "$SECRETS_DIR/jwt_secret.txt"
    echo "✅ Generated JWT secret"
else
    echo "⏭️  JWT secret already exists"
fi

# Generate refresh token secret
if [ ! -f "$SECRETS_DIR/refresh_token_secret.txt" ]; then
    generate_secret > "$SECRETS_DIR/refresh_token_secret.txt"
    echo "✅ Generated refresh token secret"
else
    echo "⏭️  Refresh token secret already exists"
fi

# Generate database password
if [ ! -f "$SECRETS_DIR/db_password.txt" ]; then
    generate_secret > "$SECRETS_DIR/db_password.txt"
    echo "✅ Generated database password"
else
    echo "⏭️  Database password already exists"
fi

# Secure permissions
chmod 600 "$SECRETS_DIR"/*
chmod 700 "$SECRETS_DIR"

echo ""
echo "=================================="
echo "✅ Secret generation complete!"
echo "=================================="
echo ""
echo "Generated secrets:"
ls -lh "$SECRETS_DIR"
echo ""
echo "⚠️  IMPORTANT: The following external secrets must be configured manually."
echo "   Obtain these from their respective providers and add them to your"
echo "   environment variables or secrets manager — do NOT store placeholder"
echo "   files that could be mistaken for valid credentials."
echo ""
echo "   External secrets required:"
echo "     - STRIPE_SECRET_KEY         (Stripe Dashboard → API keys)"
echo "     - STRIPE_WEBHOOK_SECRET     (Stripe Dashboard → Webhooks → Signing secret)"
echo "     - SENDGRID_API_KEY          (SendGrid → Settings → API Keys)"
echo "     - OPENAI_API_KEY            (OpenAI Platform → API keys)"
echo "     - GOOGLE_CLIENT_ID          (Google Cloud Console → Credentials)"
echo "     - MINIO_ACCESS_KEY          (MinIO Console or cloud provider)"
echo "     - MINIO_SECRET_KEY          (MinIO Console or cloud provider)"
echo ""
echo "   General guidelines:"
echo "     1. NEVER commit secrets to git"
echo "     2. Backup secrets securely (1Password, AWS Secrets Manager, etc.)"
echo "     3. Rotate secrets periodically in production"
echo ""
