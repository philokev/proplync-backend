#!/bin/bash

# PropLync Backend - OpenShift Deployment Script
# This script deploys the backend application to OpenShift

set -e  # Exit on error

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration variables
OPENSHIFT_SERVER="${OPENSHIFT_SERVER:-}"
OPENSHIFT_USERNAME="${OPENSHIFT_USERNAME:-}"
OPENSHIFT_PASSWORD="${OPENSHIFT_PASSWORD:-}"
OPENSHIFT_PROJECT="${OPENSHIFT_PROJECT:-proplync-ai}"
IMAGE_NAME="${IMAGE_NAME:-proplync-backend}"
IMAGE_TAG="${IMAGE_TAG:-latest}"
OPENAI_API_KEY="${OPENAI_API_KEY:-}"
IS_LOCAL="${IS_LOCAL:-false}"
INSECURE_SKIP_TLS="${INSECURE_SKIP_TLS:-false}"

# Function to print colored output
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

# Function to check if a command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Check prerequisites
check_prerequisites() {
    print_info "Checking prerequisites..."
    
    if ! command_exists oc; then
        print_error "OpenShift CLI (oc) is not installed."
        exit 1
    fi
    
    if ! command_exists podman && ! command_exists docker; then
        print_error "Neither podman nor docker is installed."
        exit 1
    fi
    
    if ! command_exists mvn; then
        print_error "Maven (mvn) is not installed."
        exit 1
    fi
    
    if [ -z "$OPENAI_API_KEY" ]; then
        print_error "OPENAI_API_KEY environment variable is required."
        exit 1
    fi
    
    print_success "Prerequisites check passed"
}

# Function to login to OpenShift
login_openshift() {
    print_info "Logging in to OpenShift..."
    
    if [ -z "$OPENSHIFT_SERVER" ]; then
        read -p "Enter OpenShift server URL: " OPENSHIFT_SERVER
    fi
    
    if [ -z "$OPENSHIFT_USERNAME" ]; then
        read -p "Enter OpenShift username: " OPENSHIFT_USERNAME
    fi
    
    if [ -z "$OPENSHIFT_PASSWORD" ]; then
        read -s -p "Enter OpenShift password: " OPENSHIFT_PASSWORD
        echo
    fi
    
    if [[ "$OPENSHIFT_SERVER" == *"crc.testing"* ]] || [[ "$OPENSHIFT_SERVER" == *"localhost"* ]] || [[ "$IS_LOCAL" == "true" ]]; then
        IS_LOCAL="true"
        INSECURE_SKIP_TLS="true"
    fi
    
    LOGIN_OPTS="-u $OPENSHIFT_USERNAME -p $OPENSHIFT_PASSWORD"
    if [ "$INSECURE_SKIP_TLS" = "true" ]; then
        LOGIN_OPTS="$LOGIN_OPTS --insecure-skip-tls-verify=true"
    fi
    
    if oc login "$OPENSHIFT_SERVER" $LOGIN_OPTS 2>/dev/null; then
        print_success "Successfully logged in to OpenShift"
    else
        print_error "Failed to login to OpenShift"
        exit 1
    fi
}

# Function to create or select project
setup_project() {
    print_info "Setting up OpenShift project: $OPENSHIFT_PROJECT"
    
    if oc get project "$OPENSHIFT_PROJECT" >/dev/null 2>&1; then
        print_warning "Project $OPENSHIFT_PROJECT already exists. Using existing project."
        oc project "$OPENSHIFT_PROJECT"
    else
        print_info "Creating new project: $OPENSHIFT_PROJECT"
        oc new-project "$OPENSHIFT_PROJECT" --display-name="PropLync.ai" --description="PropLync.ai Application"
    fi
    
    print_success "Project $OPENSHIFT_PROJECT is ready"
}

# Function to deploy using Dockerfile approach
deploy_dockerfile() {
    print_info "Deploying using Dockerfile approach..."
    
    oc patch configs.imageregistry.operator.openshift.io/cluster --type merge -p '{"spec":{"defaultRoute":true}}' 2>/dev/null || true
    
    REGISTRY=$(oc get route default-route -n openshift-image-registry --template='{{ .spec.host }}' 2>/dev/null || echo "")
    
    if [ -z "$REGISTRY" ]; then
        CLUSTER_DOMAIN=$(oc get ingresses.config/cluster -o jsonpath='{.spec.domain}' 2>/dev/null || echo "")
        if [ -n "$CLUSTER_DOMAIN" ]; then
            REGISTRY="default-route-openshift-image-registry.apps.${CLUSTER_DOMAIN#*.}"
        fi
    fi
    
    if [ -z "$REGISTRY" ]; then
        print_error "Could not determine OpenShift registry."
        exit 1
    fi
    
    FULL_IMAGE_NAME="$REGISTRY/$OPENSHIFT_PROJECT/$IMAGE_NAME:$IMAGE_TAG"
    print_info "Using registry: $REGISTRY"
    print_info "Full image name: $FULL_IMAGE_NAME"
    
    if command_exists podman; then
        BUILD_CMD="podman"
    else
        BUILD_CMD="docker"
    fi
    
    print_info "Building image with $BUILD_CMD..."
    $BUILD_CMD build -t "$FULL_IMAGE_NAME" -f Dockerfile .
    
    print_info "Logging in to OpenShift registry..."
    if [ "$BUILD_CMD" = "podman" ]; then
        REGISTRY_USER=$(oc whoami)
        REGISTRY_TOKEN=$(oc whoami -t)
        echo "$REGISTRY_TOKEN" | $BUILD_CMD login -u "$REGISTRY_USER" --password-stdin "$REGISTRY" 2>/dev/null || oc registry login
    else
        oc registry login
    fi
    
    print_info "Pushing image to OpenShift registry..."
    if [ "$IS_LOCAL" = "true" ] || [ "$INSECURE_SKIP_TLS" = "true" ]; then
        $BUILD_CMD push "$FULL_IMAGE_NAME" --tls-verify=false
    else
        $BUILD_CMD push "$FULL_IMAGE_NAME"
    fi
    
    INTERNAL_IMAGE_REF="image-registry.openshift-image-registry.svc:5000/$OPENSHIFT_PROJECT/$IMAGE_NAME:$IMAGE_TAG"
    
    print_info "Creating secret for OpenAI API key..."
    oc create secret generic proplync-backend-secrets \
        --from-literal=OPENAI_API_KEY="$OPENAI_API_KEY" \
        --dry-run=client -o yaml | oc apply -f -
    
    print_info "Creating deployment from template..."
    oc process -f openshift-deployment.yaml \
        -p IMAGE_NAME="$IMAGE_NAME" \
        -p IMAGE_TAG="$IMAGE_TAG" \
        -p OPENAI_API_KEY="$OPENAI_API_KEY" \
        | sed "s|image: ${IMAGE_NAME}:${IMAGE_TAG}|image: ${INTERNAL_IMAGE_REF}|g" \
        | oc apply -f -
    
    print_success "Dockerfile deployment completed"
}

# Function to wait for deployment
wait_for_deployment() {
    print_info "Waiting for deployment to be ready..."
    
    if oc wait --for=condition=available --timeout=300s deployment/"$IMAGE_NAME" 2>/dev/null; then
        print_success "Deployment is ready"
    else
        print_error "Deployment did not become available in time"
        oc get pods -l app="$IMAGE_NAME"
        exit 1
    fi
}

# Function to display deployment information
show_deployment_info() {
    print_info "Deployment Information:"
    echo
    
    print_info "Pods:"
    oc get pods -l app="$IMAGE_NAME"
    echo
    
    print_info "Services:"
    oc get svc -l app="$IMAGE_NAME"
    echo
    
    print_info "Routes:"
    oc get route -l app="$IMAGE_NAME"
    echo
    
    ROUTE_URL=$(oc get route "$IMAGE_NAME" -o jsonpath='{.spec.host}' 2>/dev/null || echo "")
    if [ -n "$ROUTE_URL" ]; then
        print_success "Backend API is available at: https://$ROUTE_URL"
        print_info "Health check: https://$ROUTE_URL/q/health"
    fi
}

# Main deployment function
main() {
    echo "=========================================="
    echo "  PropLync Backend - OpenShift Deployment"
    echo "=========================================="
    echo
    
    check_prerequisites
    login_openshift
    setup_project
    deploy_dockerfile
    wait_for_deployment
    show_deployment_info
    
    echo
    print_success "Deployment completed successfully!"
    print_info "To view logs: oc logs -f deployment/$IMAGE_NAME"
    print_info "To scale: oc scale deployment/$IMAGE_NAME --replicas=N"
}

# Run main function
main "$@"
