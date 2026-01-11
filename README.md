# PropLync Backend

A minimal Quarkus backend for handling chatbot requests for the PropLync.ai platform.

## Overview

This backend service handles communication with OpenAI's ChatKit API, providing a RESTful interface for the PropLync frontend. It replaces the previous Supabase Edge Functions implementation.

## Features

- RESTful API endpoint for chatbot messages
- Integration with OpenAI ChatKit API
- Fallback to Chat Completions API if ChatKit fails
- CORS support for frontend communication
- Session management for chat conversations

## Prerequisites

- Java 17 or higher
- Maven 3.8+
- OpenAI API key

## Configuration

Set the OpenAI API key as an environment variable:

```bash
export OPENAI_API_KEY=your-api-key-here
```

Or create a `.env` file in the project root:

```
OPENAI_API_KEY=your-api-key-here
```

## Running the Application

### Development Mode

```bash
mvn quarkus:dev
```

The application will be available at `http://localhost:8080`

### Production Build

```bash
mvn clean package
java -jar target/quarkus-app/quarkus-run.jar
```

## API Endpoints

### POST /api/chatbot/message

Send a message to the chatbot.

**Request Body:**
```json
{
  "messages": [
    {
      "role": "user",
      "content": "What can you help me with?"
    }
  ],
  "sessionId": "optional-session-id"
}
```

**Response:**
```json
{
  "content": "I'm your AI Financial Copilot...",
  "workflowId": "wf_6907b12d71208190aebedcd7523c1d8d0a79856e2c61f448",
  "fallback": false
}
```

## Architecture

The backend uses:
- **Quarkus** - Supersonic Subatomic Java framework
- **RESTEasy Reactive** - JAX-RS implementation
- **Java HTTP Client** - For OpenAI API communication

## Development

### Project Structure

```
proplync-backend/
├── src/
│   ├── main/
│   │   ├── java/ai/proplync/backend/
│   │   │   └── ChatbotResource.java
│   │   └── resources/
│   │       └── application.properties
│   └── test/
├── pom.xml
└── README.md
```

## Environment Variables

- `OPENAI_API_KEY` - Required. Your OpenAI API key for ChatKit access.

## CORS Configuration

The backend is configured to accept requests from:
- `http://localhost:5173` (Vite default)
- `http://localhost:3000` (Common React port)
- `http://localhost:5174` (Alternative Vite port)

To add more origins, update `quarkus.http.cors.origins` in `application.properties`.

## OpenShift Deployment

The backend is fully configured for deployment on Red Hat OpenShift, following the same patterns as the frontend.

### Prerequisites

- OpenShift CLI (`oc`) installed
- Access to an OpenShift cluster
- Maven installed locally (for building)
- Podman or Docker installed
- OpenAI API key

### Local OpenShift Deployment (CRC)

For local development with CodeReady Containers:

```bash
# Set your OpenAI API key
export OPENAI_API_KEY=your-api-key-here

# Deploy to local OpenShift
./deploy-openshift-local.sh
```

The script will:
1. Auto-detect CRC if running
2. Build the Quarkus application
3. Create a container image
4. Push to OpenShift registry
5. Deploy with health checks and secrets

### Production OpenShift Deployment

For production deployments:

```bash
# Set required environment variables
export OPENSHIFT_SERVER=https://your-openshift-cluster.com
export OPENSHIFT_USERNAME=your-username
export OPENSHIFT_PASSWORD=your-password
export OPENAI_API_KEY=your-api-key-here

# Deploy
./deploy-openshift.sh
```

### Using the Deployment Template

You can also use the OpenShift template directly:

```bash
# Login to OpenShift
oc login <your-cluster>

# Create project
oc new-project proplync-ai

# Process and apply template
oc process -f openshift-deployment.yaml \
  -p IMAGE_NAME=proplync-backend \
  -p IMAGE_TAG=latest \
  -p OPENAI_API_KEY=your-api-key-here \
  | oc create -f -
```

### Health Checks

The backend includes health check endpoints:
- **Liveness**: `/q/health/live` - Container is running
- **Readiness**: `/q/health/ready` - Application is ready to serve traffic
- **Health**: `/q/health` - Overall health status

### Secrets Management

The OpenAI API key is stored in an OpenShift Secret:
- Secret name: `proplync-backend-secrets`
- Key: `OPENAI_API_KEY`

To update the secret:
```bash
oc create secret generic proplync-backend-secrets \
  --from-literal=OPENAI_API_KEY=new-key-here \
  --dry-run=client -o yaml | oc apply -f -
```

### Scaling

Scale the deployment:
```bash
oc scale deployment/proplync-backend --replicas=3
```

### Monitoring

View logs:
```bash
oc logs -f deployment/proplync-backend
```

Check pod status:
```bash
oc get pods -l app=proplync-backend
```

Get route URL:
```bash
oc get route proplync-backend
```

### Cleanup

Remove all resources:
```bash
./cleanup-openshift-local.sh
```

Or manually:
```bash
oc delete deployment proplync-backend
oc delete service proplync-backend
oc delete route proplync-backend
oc delete secret proplync-backend-secrets
```

## Container Build

### Build Locally

```bash
# Build the application
mvn clean package -DskipTests

# Build container image
podman build -t proplync-backend:latest .
```

### Using Dockerfile

The Dockerfile supports multi-stage builds:
1. Builds the Quarkus application using Maven
2. Creates a runtime image with only the necessary files
3. Uses Red Hat UBI (Universal Base Image) for compatibility

## Red Hat Compatibility

This application follows Red Hat best practices:
- Uses Red Hat UBI containers
- Compatible with Red Hat OpenShift
- Implements health checks and readiness probes
- Uses OpenShift Secrets for sensitive data
- Follows security best practices (non-root user)

## License

Proprietary - PropLync.ai
