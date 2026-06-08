# Container Registry Setup Guide

## Image Location

After the GitHub Actions workflow completes, your image will be at:
```
ghcr.io/mmorency2021/monitoring-app:latest
```

## Public vs Private Images

### Option 1: Make Image Public (RECOMMENDED - No Cluster Config Needed)

**Advantages:**
- ✅ No authentication needed
- ✅ Anyone can pull and deploy
- ✅ Perfect for open source projects
- ✅ Works on any Kubernetes/OpenShift cluster immediately

**Steps:**

1. **Wait for GitHub Action to complete** (check: https://github.com/mmorency2021/monitoring-app/actions)

2. **Make the package public:**
   - Go to https://github.com/mmorency2021?tab=packages
   - Click on `monitoring-app` package
   - Click "Package settings" (bottom right)
   - Scroll to "Danger Zone"
   - Click "Change visibility" → Select "Public"
   - Type the repository name to confirm

3. **That's it!** Now anyone can pull:
   ```bash
   docker pull ghcr.io/mmorency2021/monitoring-app:latest
   ```

4. **Deploy to any cluster:**
   ```bash
   oc apply -f kubernetes/daemonset-minimal.yaml
   # No imagePullSecrets needed!
   ```

---

### Option 2: Keep Image Private (Requires Authentication)

If you want to keep the image private, clusters need authentication to pull.

#### For Kubernetes

**Step 1: Create GitHub Personal Access Token**

1. Go to https://github.com/settings/tokens/new
2. Note: `ghcr-pull-token`
3. Expiration: Choose duration
4. Scopes: Check ✅ `read:packages`
5. Click "Generate token"
6. **Copy the token** (you won't see it again!)

**Step 2: Create Kubernetes Secret**

```bash
# Create secret in the rootless-monitor namespace
oc create secret docker-registry ghcr-secret \
  --docker-server=ghcr.io \
  --docker-username=mmorency2021 \
  --docker-password=YOUR_GITHUB_TOKEN \
  --docker-email=your-email@example.com \
  -n rootless-monitor

# Verify secret was created
oc get secret ghcr-secret -n rootless-monitor
```

**Step 3: Update DaemonSet to Use Secret**

Edit `kubernetes/daemonset-minimal.yaml` (and other variants):

```yaml
spec:
  template:
    spec:
      # Add this line:
      imagePullSecrets:
      - name: ghcr-secret
      
      serviceAccountName: rootless-monitor
      # ... rest of spec
```

**Step 4: Apply Updated Manifest**

```bash
oc apply -f kubernetes/daemonset-minimal.yaml
```

---

#### For OpenShift

OpenShift has additional options for registry authentication.

**Option A: Using Docker Config Secret (Same as K8s)**

```bash
# Create secret
oc create secret docker-registry ghcr-secret \
  --docker-server=ghcr.io \
  --docker-username=mmorency2021 \
  --docker-password=YOUR_GITHUB_TOKEN \
  --docker-email=your-email@example.com \
  -n rootless-monitor

# Link secret to service account
oc secrets link rootless-monitor ghcr-secret --for=pull -n rootless-monitor
```

**Option B: Using OpenShift Image Stream (Advanced)**

```bash
# Create secret first
oc create secret docker-registry ghcr-secret \
  --docker-server=ghcr.io \
  --docker-username=mmorency2021 \
  --docker-password=YOUR_GITHUB_TOKEN \
  -n rootless-monitor

# Link to builder and default service accounts
oc secrets link builder ghcr-secret -n rootless-monitor
oc secrets link default ghcr-secret -n rootless-monitor

# Create ImageStream
oc create imagestream rootless-monitor -n rootless-monitor

# Import image from GHCR
oc import-image rootless-monitor:latest \
  --from=ghcr.io/mmorency2021/monitoring-app:latest \
  --confirm \
  -n rootless-monitor

# Update DaemonSet to use ImageStream
# Change image to:
#   image: image-registry.openshift-image-registry.svc:5000/rootless-monitor/rootless-monitor:latest
```

---

## Verification

### Test Image Pull

**From your local machine:**
```bash
# Public image (no auth)
docker pull ghcr.io/mmorency2021/monitoring-app:latest

# Private image (login first)
docker login ghcr.io
# Username: mmorency2021
# Password: <your_github_token>
docker pull ghcr.io/mmorency2021/monitoring-app:latest
```

**In Kubernetes:**
```bash
# Create test pod
oc run test-pull \
  --image=ghcr.io/mmorency2021/monitoring-app:latest \
  --restart=Never \
  -n rootless-monitor

# Check if it pulled successfully
oc get pod test-pull -n rootless-monitor

# Expected: STATUS = Completed or Running
# If ImagePullBackOff: image is private and needs secret

# Clean up
oc delete pod test-pull -n rootless-monitor
```

**In OpenShift:**
```bash
# Create test pod
oc run test-pull \
  --image=ghcr.io/mmorency2021/monitoring-app:latest \
  --restart=Never \
  -n rootless-monitor

# Check status
oc get pod test-pull -n rootless-monitor

# Check events if failed
oc describe pod test-pull -n rootless-monitor

# Clean up
oc delete pod test-pull -n rootless-monitor
```

---

## Troubleshooting

### Error: "ImagePullBackOff"

**Check pod events:**
```bash
oc describe pod -n rootless-monitor <pod-name>
```

**Common causes:**

1. **Image doesn't exist yet**
   - Check GitHub Actions completed: https://github.com/mmorency2021/monitoring-app/actions
   - Verify package exists: https://github.com/mmorency2021?tab=packages

2. **Image is private but no imagePullSecrets**
   - Make image public (see Option 1 above)
   - OR add imagePullSecrets (see Option 2 above)

3. **Invalid credentials in secret**
   - Recreate secret with correct GitHub token
   - Ensure token has `read:packages` scope

### Error: "ErrImagePull: unauthorized"

This means the image is private.

**Solutions:**
- Make the package public (recommended)
- OR add imagePullSecrets with valid GitHub token

### Check GitHub Actions Build Status

```bash
# Via GitHub CLI
gh run list --repo mmorency2021/monitoring-app

# Via web browser
# Go to: https://github.com/mmorency2021/monitoring-app/actions
```

---

## Best Practice Recommendation

For this open-source proof-of-concept project:

🏆 **Use Option 1: Public Image**

**Why:**
- ✅ No authentication needed for users
- ✅ Easier for vendors to test
- ✅ Standard for open source projects
- ✅ Zero cluster configuration
- ✅ Works on any K8s/OpenShift cluster immediately

The only reason to keep it private would be if it contained proprietary code or secrets (which it doesn't).

---

## Quick Start (Assuming Public Image)

Once the GitHub Action completes and you've made the package public:

```bash
# Just deploy - no registry config needed!
oc apply -f kubernetes/namespace.yaml
oc apply -f kubernetes/serviceaccount.yaml
oc apply -f kubernetes/configmap.yaml
oc apply -f kubernetes/daemonset-minimal.yaml

# Pods will pull the image automatically
oc get pods -n rootless-monitor -w
```

That's it! ✨
