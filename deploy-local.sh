#!/bin/bash
# Quick local deployment wrapper for backend
# Delegates to proplync-deployments for actual deployment
# Supports credentials file from backend directory

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEPLOYMENTS_DIR="$(cd "$SCRIPT_DIR/../../proplync-deployments" 2>/dev/null && pwd)"

if [ ! -d "$DEPLOYMENTS_DIR" ]; then
    echo "❌ proplync-deployments directory not found"
    echo "   Expected at: $(dirname "$SCRIPT_DIR")/../proplync-deployments"
    echo ""
    echo "Please ensure proplync-deployments is cloned in the parent directory."
    exit 1
fi

# Check for credentials file in backend directory
CREDENTIALS_FILE="$SCRIPT_DIR/credentials"
if [ -f "$CREDENTIALS_FILE" ]; then
    export CREDENTIALS_FILE="$CREDENTIALS_FILE"
    echo "📋 Using credentials file: $CREDENTIALS_FILE"
else
    echo "⚠️  No credentials file found at $CREDENTIALS_FILE"
    echo "   Using environment variables or defaults"
    echo "   See credentials.example for format"
fi

cd "$DEPLOYMENTS_DIR"
exec ./scripts/deploy-local.sh backend "$@"
