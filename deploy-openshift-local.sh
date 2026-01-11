#!/bin/bash

# PropLync Backend - Local OpenShift Deployment Script
# Optimized for local OpenShift instances (CRC, Minishift, etc.)

set -e  # Exit on error

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration with local OpenShift defaults
OPENSHIFT_SERVER="${OPENSHIFT_SERVER:-}"
OPENSHIFT_USERNAME="${OPENSHIFT_USERNAME:-developer}"
OPENSHIFT_PASSWORD="${OPENSHIFT_PASSWORD:-}"
OPENSHIFT_PROJECT="${OPENSHIFT_PROJECT:-proplync-ai}"
IMAGE_NAME="${IMAGE_NAME:-proplync-backend}"
IMAGE_TAG="${IMAGE_TAG:-latest}"
OPENAI_API_KEY="${OPENAI_API_KEY:-}"
CHATKIT_WORKFLOW_ID="${CHATKIT_WORKFLOW_ID:-wf_6907b12d71208190aebedcd7523c1d8d0a79856e2c61f448}"
CHATKIT_API_BASE="${CHATKIT_API_BASE:-https://api.openai.com}"

# Background mode and progress options
BACKGROUND_MODE="${BACKGROUND_MODE:-false}"
SHOW_PROGRESS="${SHOW_PROGRESS:-true}"
LOG_FILE="${LOG_FILE:-deploy-openshift-local.log}"

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -b|--background)
            BACKGROUND_MODE="true"
            shift
            ;;
        --no-progress)
            SHOW_PROGRESS="false"
            shift
            ;;
        --log-file)
            LOG_FILE="$2"
            shift 2
            ;;
        -h|--help)
            echo "Usage: $0 [OPTIONS]"
            echo ""
            echo "Options:"
            echo "  -b, --background      Run deployment in background mode"
            echo "  --no-progress         Disable progress indicators"
            echo "  --log-file FILE      Specify log file for background mode"
            echo "  -h, --help           Show this help message"
            echo ""
            echo "Environment variables:"
            echo "  OPENSHIFT_SERVER     OpenShift server URL"
            echo "  OPENSHIFT_USERNAME   OpenShift username (default: developer)"
            echo "  OPENSHIFT_PASSWORD   OpenShift password"
            echo "  OPENSHIFT_PROJECT   Project name (default: proplync-ai)"
            echo "  IMAGE_NAME          Image name (default: proplync-backend)"
            echo "  OPENAI_API_KEY      OpenAI API Key (required)"
            echo "  CHATKIT_WORKFLOW_ID ChatKit Workflow ID (optional, has default)"
            echo "  CHATKIT_API_BASE    ChatKit API Base URL (optional, has default)"
            exit 0
            ;;
        *)
            print_error "Unknown option: $1"
            echo "Use -h or --help for usage information"
            exit 1
            ;;
    esac
done

# Function to print colored output
print_info() {
    if [ "$BACKGROUND_MODE" = "true" ]; then
        echo "[$(date '+%Y-%m-%d %H:%M:%S')] [INFO] $1" >> "$LOG_FILE"
    else
        echo -e "${BLUE}[INFO]${NC} $1"
    fi
}

print_success() {
    if [ "$BACKGROUND_MODE" = "true" ]; then
        echo "[$(date '+%Y-%m-%d %H:%M:%S')] [SUCCESS] $1" >> "$LOG_FILE"
    else
        echo -e "${GREEN}[SUCCESS]${NC} $1"
    fi
}

print_warning() {
    if [ "$BACKGROUND_MODE" = "true" ]; then
        echo "[$(date '+%Y-%m-%d %H:%M:%S')] [WARNING] $1" >> "$LOG_FILE"
    else
        echo -e "${YELLOW}[WARNING]${NC} $1"
    fi
}

print_error() {
    if [ "$BACKGROUND_MODE" = "true" ]; then
        echo "[$(date '+%Y-%m-%d %H:%M:%S')] [ERROR] $1" >> "$LOG_FILE"
    else
        echo -e "${RED}[ERROR]${NC} $1"
    fi
}

# Function to check if a command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Auto-detect CRC if running
detect_crc() {
    if command_exists crc; then
        if crc status >/dev/null 2>&1; then
            print_info "Detected CodeReady Containers (CRC)"
            if [ -z "$OPENSHIFT_SERVER" ]; then
                OPENSHIFT_SERVER="https://api.crc.testing:6443"
                print_info "Using CRC server: $OPENSHIFT_SERVER"
            fi
            if [ -z "$OPENSHIFT_PASSWORD" ]; then
                OPENSHIFT_PASSWORD=$(crc console --credentials 2>/dev/null | grep -i password | head -1 | awk '{print $NF}' || echo "developer")
                print_info "Using CRC default password"
            fi
            return 0
        fi
    fi
    return 1
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
        print_info "Set it with: export OPENAI_API_KEY=your-key-here"
        exit 1
    fi
    
    if [ -z "$CHATKIT_WORKFLOW_ID" ]; then
        print_warning "CHATKIT_WORKFLOW_ID not set, using default"
        CHATKIT_WORKFLOW_ID="wf_6907b12d71208190aebedcd7523c1d8d0a79856e2c61f448"
    fi
    
    print_success "Prerequisites check passed"
}

# Function to login to OpenShift
login_openshift() {
    print_info "Logging in to local OpenShift..."
    
    if ! detect_crc; then
        if [ -z "$OPENSHIFT_SERVER" ]; then
            read -p "Enter OpenShift server URL (e.g., https://api.crc.testing:6443): " OPENSHIFT_SERVER
        fi
        
        if [ -z "$OPENSHIFT_PASSWORD" ]; then
            read -s -p "Enter OpenShift password (default: developer): " OPENSHIFT_PASSWORD
            echo
            OPENSHIFT_PASSWORD="${OPENSHIFT_PASSWORD:-developer}"
        fi
    fi
    
    print_info "Logging in to $OPENSHIFT_SERVER as $OPENSHIFT_USERNAME..."
    if oc login "$OPENSHIFT_SERVER" -u "$OPENSHIFT_USERNAME" -p "$OPENSHIFT_PASSWORD" --insecure-skip-tls-verify=true 2>/dev/null; then
        print_success "Successfully logged in to local OpenShift"
    else
        print_error "Failed to login to OpenShift"
        exit 1
    fi
}

# Function to create or select project
setup_project() {
    print_info "Setting up OpenShift project: $OPENSHIFT_PROJECT"
    
    if oc get project "$OPENSHIFT_PROJECT" >/dev/null 2>&1; then
        print_info "Project $OPENSHIFT_PROJECT already exists. Using existing project."
        oc project "$OPENSHIFT_PROJECT"
    else
        print_info "Creating new project: $OPENSHIFT_PROJECT"
        oc new-project "$OPENSHIFT_PROJECT" --display-name="PropLync.ai" --description="PropLync.ai Application"
    fi
    
    print_success "Project $OPENSHIFT_PROJECT is ready"
}

# Function to setup registry
setup_registry() {
    print_info "Setting up image registry..."
    
    oc patch configs.imageregistry.operator.openshift.io/cluster --type merge -p '{"spec":{"defaultRoute":true}}' 2>/dev/null || true
    
    REGISTRY=$(oc get route default-route -n openshift-image-registry --template='{{ .spec.host }}' 2>/dev/null || echo "")
    
    if [ -z "$REGISTRY" ]; then
        if [[ "$OPENSHIFT_SERVER" == *"crc.testing"* ]]; then
            REGISTRY="default-route-openshift-image-registry.apps-crc.testing"
        fi
    fi
    
    if [ -z "$REGISTRY" ]; then
        print_error "Could not determine registry URL"
        exit 1
    fi
    
    REGISTRY_HOST=$(echo "$REGISTRY" | cut -d: -f1)
    if ! grep -q "$REGISTRY_HOST" /etc/hosts 2>/dev/null; then
        print_warning "Registry hostname not in /etc/hosts"
        if echo "127.0.0.1 $REGISTRY_HOST" | sudo tee -a /etc/hosts >/dev/null 2>&1; then
            print_success "Added registry to /etc/hosts"
        else
            print_warning "Could not add to /etc/hosts automatically"
        fi
    fi
    
    echo "$REGISTRY"
}

# Function to build and push image
build_and_push() {
    REGISTRY=$1
    FULL_IMAGE_NAME="$REGISTRY/$OPENSHIFT_PROJECT/$IMAGE_NAME:$IMAGE_TAG"
    
    if command_exists podman; then
        BUILD_CMD="podman"
    else
        BUILD_CMD="docker"
    fi
    
    print_info "Building image with $BUILD_CMD..."
    
    if [ "$SHOW_PROGRESS" = "true" ] && [ "$BACKGROUND_MODE" = "false" ]; then
        $BUILD_CMD build -t "$FULL_IMAGE_NAME" -f Dockerfile . 2>&1 | while IFS= read -r line; do
            if echo "$line" | grep -qE "(STEP|Pulling|Extracting|Building|Copying|RUN|Successfully)"; then
                echo "  $line"
            fi
        done
    else
        $BUILD_CMD build -t "$FULL_IMAGE_NAME" -f Dockerfile . >/dev/null 2>&1
    fi
    
    print_success "Image built successfully"
    
    print_info "Logging in to OpenShift registry..."
    if [ "$BUILD_CMD" = "podman" ]; then
        REGISTRY_USER=$(oc whoami)
        REGISTRY_TOKEN=$(oc whoami -t)
        echo "$REGISTRY_TOKEN" | $BUILD_CMD login -u "$REGISTRY_USER" --password-stdin "$REGISTRY" --tls-verify=false 2>/dev/null || oc registry login
    else
        oc registry login
    fi
    
    print_info "Pushing image to registry..."
    if [ "$SHOW_PROGRESS" = "true" ] && [ "$BACKGROUND_MODE" = "false" ]; then
        $BUILD_CMD push "$FULL_IMAGE_NAME" --tls-verify=false 2>&1 | while IFS= read -r line; do
            if echo "$line" | grep -qE "(Copying|Writing|Pushing|Storing|Done)"; then
                echo "  $line"
            fi
        done
    else
        $BUILD_CMD push "$FULL_IMAGE_NAME" --tls-verify=false >/dev/null 2>&1
    fi
    
    print_success "Image pushed successfully"
    
    echo "image-registry.openshift-image-registry.svc:5000/$OPENSHIFT_PROJECT/$IMAGE_NAME:$IMAGE_TAG"
}

# Function to deploy application
deploy_application() {
    INTERNAL_IMAGE_REF=$1
    
    print_info "Creating secret for API credentials..."
    oc create secret generic proplync-backend-secrets \
        --from-literal=OPENAI_API_KEY="$OPENAI_API_KEY" \
        --from-literal=CHATKIT_WORKFLOW_ID="$CHATKIT_WORKFLOW_ID" \
        --dry-run=client -o yaml | oc apply -f -
    
    print_info "Creating deployment..."
    
    cat <<EOF | oc apply -f -
apiVersion: apps/v1
kind: Deployment
metadata:
  name: $IMAGE_NAME
  labels:
    app: $IMAGE_NAME
spec:
  replicas: 1
  selector:
    matchLabels:
      app: $IMAGE_NAME
  template:
    metadata:
      labels:
        app: $IMAGE_NAME
    spec:
      containers:
        - name: backend
          image: ${INTERNAL_IMAGE_REF}
          ports:
            - containerPort: 8080
              protocol: TCP
          env:
            - name: OPENAI_API_KEY
              valueFrom:
                secretKeyRef:
                  name: proplync-backend-secrets
                  key: OPENAI_API_KEY
            - name: CHATKIT_WORKFLOW_ID
              valueFrom:
                secretKeyRef:
                  name: proplync-backend-secrets
                  key: CHATKIT_WORKFLOW_ID
            - name: CHATKIT_API_BASE
              value: "${CHATKIT_API_BASE:-https://api.openai.com}"
          resources:
            limits:
              cpu: 1000m
              memory: 1Gi
            requests:
              cpu: 200m
              memory: 512Mi
          livenessProbe:
            httpGet:
              path: /q/health/live
              port: 8080
            initialDelaySeconds: 60
            periodSeconds: 10
          readinessProbe:
            httpGet:
              path: /q/health/ready
              port: 8080
            initialDelaySeconds: 30
            periodSeconds: 5
---
apiVersion: v1
kind: Service
metadata:
  name: $IMAGE_NAME
  labels:
    app: $IMAGE_NAME
spec:
  selector:
    app: $IMAGE_NAME
  ports:
    - name: http
      port: 8080
      targetPort: 8080
      protocol: TCP
  type: ClusterIP
---
apiVersion: route.openshift.io/v1
kind: Route
metadata:
  name: $IMAGE_NAME
  labels:
    app: $IMAGE_NAME
spec:
  to:
    kind: Service
    name: $IMAGE_NAME
  port:
    targetPort: http
  tls:
    termination: edge
    insecureEdgeTerminationPolicy: Redirect
EOF
    
    print_success "Deployment created"
}

# Function to wait for deployment
wait_for_deployment() {
    print_info "Waiting for deployment to be ready..."
    
    if oc wait --for=condition=available --timeout=300s deployment/"$IMAGE_NAME" 2>/dev/null; then
        print_success "Deployment is ready"
    else
        print_warning "Deployment may still be starting..."
        oc get pods -l app="$IMAGE_NAME"
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
    if [ "$BACKGROUND_MODE" = "true" ]; then
        {
            echo "=========================================="
            echo "  PropLync Backend - Local OpenShift"
            echo "  Started: $(date)"
            echo "=========================================="
            echo ""
        } >> "$LOG_FILE" 2>&1
        exec >> "$LOG_FILE" 2>&1
    else
        echo "=========================================="
        echo "  PropLync Backend - Local OpenShift"
        echo "=========================================="
        echo
    fi
    
    check_prerequisites
    login_openshift
    setup_project
    
    REGISTRY=$(setup_registry)
    INTERNAL_IMAGE_REF=$(build_and_push "$REGISTRY")
    deploy_application "$INTERNAL_IMAGE_REF"
    wait_for_deployment
    show_deployment_info
    
    if [ "$BACKGROUND_MODE" = "false" ]; then
        echo
        print_success "Deployment completed successfully!"
        echo
        print_info "Useful commands:"
        print_info "  View logs:    oc logs -f deployment/$IMAGE_NAME"
        print_info "  Check pods:   oc get pods -l app=$IMAGE_NAME"
        print_info "  Get route:    oc get route $IMAGE_NAME"
    fi
}

# Run main function
if [ "$BACKGROUND_MODE" = "true" ]; then
    echo "Starting deployment in background mode..."
    echo "Log file: $LOG_FILE"
    echo ""
    main "$@" &
    DEPLOY_PID=$!
    echo "Deployment started in background (PID: $DEPLOY_PID)"
    echo "Monitor with: tail -f $LOG_FILE"
else
    main "$@"
fi
