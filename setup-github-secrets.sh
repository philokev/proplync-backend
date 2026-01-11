#!/bin/bash
# Script to help set up GitHub Secrets for the repository
# Uses GitHub CLI if available, otherwise provides manual instructions

set -e

# Color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

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

# Check for GitHub CLI
if command -v gh >/dev/null 2>&1; then
    print_success "GitHub CLI found"
    USE_GH_CLI=true
else
    print_warning "GitHub CLI not found - will provide manual instructions"
    USE_GH_CLI=false
fi

# Load credentials
CREDENTIALS_FILE="${CREDENTIALS_FILE:-credentials}"
if [ -f "$CREDENTIALS_FILE" ]; then
    print_info "Loading credentials from $CREDENTIALS_FILE"
    source "$CREDENTIALS_FILE"
else
    print_warning "Credentials file not found: $CREDENTIALS_FILE"
    print_info "Please provide values manually"
fi

# Get OpenShift token
print_info "Getting OpenShift service account token..."
if oc get serviceaccount github-actions -n proplync-ai >/dev/null 2>&1; then
    # Use newer create token command
    OPENSHIFT_TOKEN=$(oc create token github-actions -n proplync-ai --duration=8760h 2>&1)
    if [ $? -ne 0 ] || [ -z "$OPENSHIFT_TOKEN" ] || echo "$OPENSHIFT_TOKEN" | grep -qi "error"; then
        print_error "Failed to get token. Run ./setup-github-actions.sh first"
        exit 1
    fi
else
    print_error "Service account not found. Run ./setup-github-actions.sh first"
    exit 1
fi

OPENSHIFT_SERVER=$(oc whoami --show-server 2>/dev/null || echo "https://api.crc.testing:6443")

# Get repository info
REPO_URL=$(git config --get remote.origin.url 2>/dev/null || echo "")
if [ -n "$REPO_URL" ]; then
    REPO_NAME=$(echo "$REPO_URL" | sed 's/.*github.com[:/]\([^.]*\).*/\1/')
    print_info "Repository: $REPO_NAME"
else
    print_warning "Could not determine repository name"
    REPO_NAME=""
fi

print_success "Ready to set up GitHub Secrets"
echo ""

if [ "$USE_GH_CLI" = true ]; then
    print_info "Setting secrets via GitHub CLI..."
    
    gh secret set OPENSHIFT_SERVER --body "$OPENSHIFT_SERVER" 2>&1 && print_success "OPENSHIFT_SERVER set" || print_warning "Failed to set OPENSHIFT_SERVER"
    gh secret set OPENSHIFT_TOKEN --body "$OPENSHIFT_TOKEN" 2>&1 && print_success "OPENSHIFT_TOKEN set" || print_warning "Failed to set OPENSHIFT_TOKEN"
    
    if [ -n "$OPENAI_API_KEY" ]; then
        gh secret set OPENAI_API_KEY --body "$OPENAI_API_KEY" 2>&1 && print_success "OPENAI_API_KEY set" || print_warning "Failed to set OPENAI_API_KEY"
    else
        print_warning "OPENAI_API_KEY not found in credentials file"
    fi
    
    if [ -n "$CHATKIT_WORKFLOW_ID" ]; then
        gh secret set CHATKIT_WORKFLOW_ID --body "$CHATKIT_WORKFLOW_ID" 2>&1 && print_success "CHATKIT_WORKFLOW_ID set" || print_warning "Failed to set CHATKIT_WORKFLOW_ID"
    else
        print_warning "CHATKIT_WORKFLOW_ID not found in credentials file"
    fi
    
    if [ -n "$CHATKIT_API_BASE" ]; then
        gh secret set CHATKIT_API_BASE --body "$CHATKIT_API_BASE" 2>&1 && print_success "CHATKIT_API_BASE set" || print_warning "Failed to set CHATKIT_API_BASE"
    fi
    
    print_success "All secrets configured!"
else
    print_info "Manual setup required:"
    echo ""
    echo "Go to: https://github.com/$REPO_NAME/settings/secrets/actions"
    echo ""
    echo "Add these secrets:"
    echo ""
    echo "1. OPENSHIFT_SERVER"
    echo "   Value: $OPENSHIFT_SERVER"
    echo ""
    echo "2. OPENSHIFT_TOKEN"
    echo "   Value: $OPENSHIFT_TOKEN"
    echo ""
    if [ -n "$OPENAI_API_KEY" ]; then
        echo "3. OPENAI_API_KEY"
        echo "   Value: $OPENAI_API_KEY"
        echo ""
    fi
    if [ -n "$CHATKIT_WORKFLOW_ID" ]; then
        echo "4. CHATKIT_WORKFLOW_ID"
        echo "   Value: $CHATKIT_WORKFLOW_ID"
        echo ""
    fi
    if [ -n "$CHATKIT_API_BASE" ]; then
        echo "5. CHATKIT_API_BASE (optional)"
        echo "   Value: $CHATKIT_API_BASE"
        echo ""
    fi
fi

echo ""
print_info "After setting secrets, push to main/develop to trigger deployment"
