#!/bin/bash

# PropLync Backend - OpenShift Cleanup Script
# Removes all resources created by the deployment

set -e

# Color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

OPENSHIFT_PROJECT="${OPENSHIFT_PROJECT:-proplync-ai}"
IMAGE_NAME="${IMAGE_NAME:-proplync-backend}"

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

# Check if oc is available
if ! command -v oc >/dev/null 2>&1; then
    print_error "OpenShift CLI (oc) is not installed."
    exit 1
fi

# Confirm deletion
print_warning "This will delete all resources for $IMAGE_NAME in project $OPENSHIFT_PROJECT"
read -p "Are you sure? [y/N]: " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    print_info "Cleanup cancelled"
    exit 0
fi

# Switch to project
if oc get project "$OPENSHIFT_PROJECT" >/dev/null 2>&1; then
    oc project "$OPENSHIFT_PROJECT"
else
    print_error "Project $OPENSHIFT_PROJECT does not exist"
    exit 1
fi

# Delete resources
print_info "Deleting deployment..."
oc delete deployment "$IMAGE_NAME" --ignore-not-found=true

print_info "Deleting service..."
oc delete service "$IMAGE_NAME" --ignore-not-found=true

print_info "Deleting route..."
oc delete route "$IMAGE_NAME" --ignore-not-found=true

print_info "Deleting secrets..."
oc delete secret proplync-backend-secrets --ignore-not-found=true

print_success "Cleanup completed"
