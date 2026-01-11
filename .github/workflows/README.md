# GitHub Actions Workflows

## Deploy to OpenShift

This workflow automatically builds and deploys the Quarkus backend to OpenShift when code is pushed to `main` or `develop` branches.

### Architecture

Following the slingshot pattern, this workflow:
1. **Builds** the Quarkus application using Maven
2. **Pushes** the container image to GitHub Container Registry (ghcr.io)
3. **Deploys** to OpenShift, pulling the image from ghcr.io

This approach avoids local podman/CRC registry issues and provides better reliability.

### Setup

1. **Add GitHub Secrets**:
   - `OPENSHIFT_SERVER`: Your OpenShift API server URL (e.g., `https://api.openshift.example.com:6443`)
   - `OPENSHIFT_TOKEN`: OpenShift service account token with deployment permissions
   - `OPENAI_API_KEY`: OpenAI API key
   - `CHATKIT_WORKFLOW_ID`: ChatKit workflow ID
   - `CHATKIT_API_BASE`: (Optional) ChatKit API base URL (defaults to `https://api.openai.com`)

   **Note**: `GITHUB_TOKEN` is automatically provided by GitHub Actions for pushing to ghcr.io.

2. **Get OpenShift Token**:
   ```bash
   # Create a service account
   oc create serviceaccount github-actions -n proplync-ai
   
   # Grant necessary permissions
   oc adm policy add-role-to-user edit -z github-actions -n proplync-ai
   
   # Get the token
   oc serviceaccounts get-token github-actions -n proplync-ai
   ```

3. **Add Secrets to GitHub**:
   - Go to your repository → Settings → Secrets and variables → Actions
   - Add each secret listed above

### How It Works

1. **Build Job**:
   - Compiles the Quarkus application using Maven
   - Builds a multi-arch Docker image (amd64 + arm64) using Docker Buildx
   - Pushes the image to GitHub Container Registry (ghcr.io)
   - Tags images with branch name, SHA, and semantic versioning

2. **Deploy Job** (runs after build):
   - Logs in to OpenShift
   - Creates image pull secret for ghcr.io access
   - Creates/updates application secrets
   - Deploys the application using the image from ghcr.io
   - Waits for deployment to be ready

### Image Tags

Images are tagged with:
- `main-<sha>` or `develop-<sha>` for branch pushes
- `latest` for main branch
- Semantic version tags for version tags (e.g., `v1.0.0`)

### Manual Trigger

You can also trigger the workflow manually:
- Go to Actions → Build and Deploy to OpenShift → Run workflow

### Benefits Over Local Deployment

- ✅ No local podman/CRC HTTP/HTTPS issues
- ✅ Uses GitHub Container Registry (more reliable than OpenShift internal registry)
- ✅ Multi-architecture builds (amd64 + arm64)
- ✅ Consistent build environment
- ✅ Automatic deployments on code changes
- ✅ Build artifacts are versioned with Git SHA
- ✅ Works with any OpenShift cluster (not just local)
- ✅ Better caching with GitHub Actions cache

### Viewing Images

Images are available at:
- `ghcr.io/<your-org>/proplync-backend:<tag>`

You can view them in GitHub under Packages in your repository.
