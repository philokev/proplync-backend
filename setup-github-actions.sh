#!/bin/bash
# Script to set up GitHub Actions for OpenShift deployment
# Creates service account and outputs token for GitHub Secrets

set -e

# Color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

print_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Configuration
OPENSHIFT_PROJECT="${OPENSHIFT_PROJECT:-proplync-ai}"
SERVICE_ACCOUNT_NAME="github-actions"

print_info "Setting up GitHub Actions for OpenShift deployment..."
print_info "Project: $OPENSHIFT_PROJECT"

# Check if logged in
if ! oc whoami >/dev/null 2>&1; then
    print_error "Not logged in to OpenShift. Please run: oc login"
    exit 1
fi

# Set project
print_info "Switching to project: $OPENSHIFT_PROJECT"
oc project "$OPENSHIFT_PROJECT" >/dev/null 2>&1 || {
    print_error "Project $OPENSHIFT_PROJECT not found or not accessible"
    exit 1
}

# Create service account
print_info "Creating service account: $SERVICE_ACCOUNT_NAME"
if oc get serviceaccount "$SERVICE_ACCOUNT_NAME" -n "$OPENSHIFT_PROJECT" >/dev/null 2>&1; then
    print_warning "Service account $SERVICE_ACCOUNT_NAME already exists"
else
    oc create serviceaccount "$SERVICE_ACCOUNT_NAME" -n "$OPENSHIFT_PROJECT"
    print_success "Service account created"
fi

# Grant permissions
print_info "Granting edit role to service account..."
oc adm policy add-role-to-user edit -z "$SERVICE_ACCOUNT_NAME" -n "$OPENSHIFT_PROJECT" 2>/dev/null || {
    print_warning "Role may already be assigned (this is OK)"
}

# Get token (use newer create token command)
print_info "Creating service account token..."
TOKEN=$(oc create token "$SERVICE_ACCOUNT_NAME" -n "$OPENSHIFT_PROJECT" --duration=8760h 2>&1)

if [ $? -ne 0 ] || [ -z "$TOKEN" ] || echo "$TOKEN" | grep -qi "error"; then
    print_warning "Token creation may have failed, trying alternative method..."
    # Fallback to deprecated method
    TOKEN=$(oc serviceaccounts get-token "$SERVICE_ACCOUNT_NAME" -n "$OPENSHIFT_PROJECT" 2>&1 | head -1)
fi

if [ -z "$TOKEN" ] || echo "$TOKEN" | grep -qi "error\|deprecated"; then
    print_error "Could not retrieve token automatically"
    print_info "Please create token manually:"
    print_info "  oc create token $SERVICE_ACCOUNT_NAME -n $OPENSHIFT_PROJECT --duration=8760h"
    print_info "Then copy the token and add it as OPENSHIFT_TOKEN secret in GitHub"
    exit 1
fi

# Get OpenShift server
OPENSHIFT_SERVER=$(oc whoami --show-server 2>/dev/null || echo "")

if [ -z "$OPENSHIFT_SERVER" ]; then
    print_warning "Could not determine OpenShift server URL"
    OPENSHIFT_SERVER="https://api.crc.testing:6443"
    print_info "Using default: $OPENSHIFT_SERVER"
fi

print_success "Setup complete!"
echo ""
echo "=========================================="
echo "  GitHub Secrets Configuration"
echo "=========================================="
echo ""
echo "Add these secrets to your GitHub repository:"
echo "  Repository → Settings → Secrets and variables → Actions"
echo ""
echo "Required Secrets:"
echo ""
echo "1. OPENSHIFT_SERVER"
echo "   Value: $OPENSHIFT_SERVER"
echo ""
echo "2. OPENSHIFT_TOKEN"
echo "   Value: $TOKEN"
echo ""
echo "3. OPENAI_API_KEY"
echo "   Value: (from your credentials file)"
echo ""
echo "4. CHATKIT_WORKFLOW_ID"
echo "   Value: (from your credentials file)"
echo ""
echo "5. CHATKIT_API_BASE (optional)"
echo "   Value: https://api.openai.com"
echo ""
echo "=========================================="
echo ""
print_info "To add secrets via GitHub CLI (if installed):"
echo "  gh secret set OPENSHIFT_SERVER --body \"$OPENSHIFT_SERVER\""
echo "  gh secret set OPENSHIFT_TOKEN --body \"$TOKEN\""
echo ""
print_info "Or add them manually in GitHub UI:"
echo "  https://github.com/$(git config --get remote.origin.url | sed 's/.*github.com[:/]\([^.]*\).*/\1/')/settings/secrets/actions"
echo ""
