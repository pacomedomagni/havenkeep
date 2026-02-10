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

# Create placeholders for external secrets
if [ ! -f "$SECRETS_DIR/stripe_secret_key.txt" ]; then
    echo "sk_live_REPLACE_WITH_ACTUAL_STRIPE_KEY" > "$SECRETS_DIR/stripe_secret_key.txt"
    echo "⚠️  Created Stripe secret placeholder - REPLACE WITH ACTUAL KEY"
fi

if [ ! -f "$SECRETS_DIR/do_spaces_secret.txt" ]; then
    echo "REPLACE_WITH_ACTUAL_DO_SPACES_SECRET" > "$SECRETS_DIR/do_spaces_secret.txt"
    echo "⚠️  Created DO Spaces secret placeholder - REPLACE WITH ACTUAL KEY"
fi

# Secure permissions
chmod 600 "$SECRETS_DIR"/*
chmod 700 "$SECRETS_DIR"

echo ""
echo "=================================="
echo "✅ Secret generation complete!"
echo "=================================="
echo ""
echo "⚠️  IMPORTANT:"
echo "  1. Review all files in $SECRETS_DIR/"
echo "  2. Replace placeholder values with actual credentials"
echo "  3. NEVER commit secrets to git"
echo "  4. Backup secrets securely (1Password, AWS Secrets Manager, etc.)"
echo ""
echo "Generated secrets:"
ls -lh "$SECRETS_DIR"
echo ""
