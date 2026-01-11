# GitHub Actions Workflows

## Deploy to OpenShift

This workflow automatically builds and deploys the Quarkus backend to OpenShift when code is pushed to `main` or `develop` branches.

### Setup

1. **Add GitHub Secrets**:
   - `OPENSHIFT_SERVER`: Your OpenShift API server URL (e.g., `https://api.openshift.example.com:6443`)
   - `OPENSHIFT_TOKEN`: OpenShift service account token with deployment permissions
   - `OPENAI_API_KEY`: OpenAI API key
   - `CHATKIT_WORKFLOW_ID`: ChatKit workflow ID
   - `CHATKIT_API_BASE`: (Optional) ChatKit API base URL (defaults to `https://api.openai.com`)

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

1. **Build**: Compiles the Quarkus application using Maven
2. **Containerize**: Builds a Docker image using Podman
3. **Push**: Pushes the image to OpenShift's internal registry
4. **Deploy**: Creates/updates the Deployment, Service, and Route
5. **Verify**: Waits for the deployment to be ready

### Manual Trigger

You can also trigger the workflow manually:
- Go to Actions → Build and Deploy to OpenShift → Run workflow

### Benefits Over Local Deployment

- ✅ No local podman/CRC HTTP/HTTPS issues
- ✅ Consistent build environment
- ✅ Automatic deployments on code changes
- ✅ Build artifacts are versioned with Git SHA
- ✅ Works with any OpenShift cluster (not just local)
