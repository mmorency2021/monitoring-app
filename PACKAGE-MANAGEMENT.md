# GitHub Container Registry (GHCR) - Complete Package Management Guide

## Table of Contents
- [How Packages Are Created](#how-packages-are-created)
- [Manual Package Creation](#manual-package-creation)
- [Automatic Package Creation (GitHub Actions)](#automatic-package-creation-github-actions)
- [Making Packages Public](#making-packages-public)
- [Managing Private Packages](#managing-private-packages)
- [Connecting Clusters to Private Packages](#connecting-clusters-to-private-packages)

---

## How Packages Are Created

GitHub Container Registry (GHCR) packages are created when you **push a container image** to `ghcr.io`. There are two ways:

1. **Manual Push** - Build locally and push with Docker
2. **Automatic (GitHub Actions)** - Auto-build and push on every commit

---

## Manual Package Creation

### Step 1: Create GitHub Personal Access Token

You need a token with package write permissions.

1. Go to https://github.com/settings/tokens/new
2. Fill in:
   - **Note**: `ghcr-push-token`
   - **Expiration**: Choose duration (30 days, 60 days, or no expiration)
   - **Scopes**: Check these boxes:
     - ✅ `write:packages` (allows pushing images)
     - ✅ `read:packages` (allows pulling images)
     - ✅ `delete:packages` (allows deleting images - optional)
3. Click **Generate token**
4. **CRITICAL**: Copy the token immediately (starts with `ghp_...`) - you won't see it again!

### Step 2: Login to GHCR

```bash
# Export your token (replace with actual token)
export GITHUB_TOKEN="ghp_xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx"

# Login to ghcr.io
echo $GITHUB_TOKEN | docker login ghcr.io -u mmorency2021 --password-stdin

# You should see: Login Succeeded
```

**Alternative (interactive):**
```bash
docker login ghcr.io
# Username: mmorency2021
# Password: <paste your ghp_... token>
```

### Step 3: Build the Image

```bash
cd rootless-monitor-agent

# Build for your platform
docker build -t rootless-monitor:latest .

# Or build for multiple platforms (recommended)
docker buildx create --use
docker buildx build \
  --platform linux/amd64,linux/arm64 \
  -t ghcr.io/mmorency2021/monitoring-app:latest \
  --push \
  .
```

### Step 4: Tag for GHCR

```bash
# Tag with GHCR registry path
docker tag rootless-monitor:latest ghcr.io/mmorency2021/monitoring-app:latest

# Optional: Add version tags
docker tag rootless-monitor:latest ghcr.io/mmorency2021/monitoring-app:v1.0.0
docker tag rootless-monitor:latest ghcr.io/mmorency2021/monitoring-app:v1.0
docker tag rootless-monitor:latest ghcr.io/mmorency2021/monitoring-app:v1
```

### Step 5: Push to GHCR

```bash
# Push latest
docker push ghcr.io/mmorency2021/monitoring-app:latest

# Push version tags (if created)
docker push ghcr.io/mmorency2021/monitoring-app:v1.0.0
docker push ghcr.io/mmorency2021/monitoring-app:v1.0
docker push ghcr.io/mmorency2021/monitoring-app:v1
```

### Step 6: Verify Package Was Created

```bash
# Via Docker
docker pull ghcr.io/mmorency2021/monitoring-app:latest

# Via browser
# Go to: https://github.com/mmorency2021?tab=packages
# You should see "monitoring-app" listed
```

### All-in-One Script

We've provided a script that does all this:

```bash
./push-to-ghcr.sh
```

---

## Automatic Package Creation (GitHub Actions)

The repository includes a GitHub Actions workflow that automatically builds and pushes images.

### How It Works

The workflow (`.github/workflows/build-and-push.yml`) triggers on:
- Every push to `main` branch
- Every pull request
- Every tag push (e.g., `v1.0.0`)

### Workflow Actions

```yaml
on:
  push:
    branches: [ main ]      # Auto-build on main branch commits
    tags:
      - 'v*'                # Auto-build on version tags
  pull_request:
    branches: [ main ]      # Build (but don't push) on PRs
```

### Check Build Status

**Via GitHub Web UI:**
1. Go to https://github.com/mmorency2021/monitoring-app/actions
2. See the latest "Build and Push Container Image" workflow
3. Green checkmark ✅ = success
4. Red X ❌ = failed (click to see logs)

**Via GitHub CLI:**
```bash
# Install gh CLI if needed: https://cli.github.com/

# List recent workflow runs
gh run list --repo mmorency2021/monitoring-app

# Watch live workflow
gh run watch --repo mmorency2021/monitoring-app

# View details of latest run
gh run view --repo mmorency2021/monitoring-app
```

### Trigger Manual Build

```bash
# Make any change and push
git commit --allow-empty -m "Trigger rebuild"
git push origin main

# Or create a version tag
git tag v1.0.0
git push origin v1.0.0
```

### What Gets Built

The workflow creates these tags:
- `latest` - Always the newest main branch build
- `main` - Same as latest
- `sha-<git-commit-hash>` - Specific commit
- `v1.0.0` - If you pushed a version tag
- `v1.0`, `v1` - Semantic version variants

Example:
```
ghcr.io/mmorency2021/monitoring-app:latest
ghcr.io/mmorency2021/monitoring-app:main
ghcr.io/mmorency2021/monitoring-app:sha-13edcce
ghcr.io/mmorency2021/monitoring-app:v1.0.0
ghcr.io/mmorency2021/monitoring-app:v1.0
ghcr.io/mmorency2021/monitoring-app:v1
```

---

## Making Packages Public

By default, GHCR packages are **PRIVATE**. To make them public:

### Via GitHub Web UI

1. **Go to your packages page:**
   https://github.com/mmorency2021?tab=packages

2. **Click on the package** (`monitoring-app`)

3. **Click "Package settings"** (right sidebar, near bottom)

4. **Scroll to "Danger Zone"**

5. **Click "Change visibility"**

6. **Select "Public"**

7. **Type the repository name to confirm:**
   ```
   mmorency2021/monitoring-app
   ```

8. **Click "I understand, change package visibility"**

### Verify It's Public

```bash
# Should work without login
docker logout ghcr.io
docker pull ghcr.io/mmorency2021/monitoring-app:latest

# If it pulls successfully, it's public!
```

### Benefits of Public Packages

✅ **No authentication needed** - Anyone can pull  
✅ **Open source standard** - Transparent and accessible  
✅ **Easier for users** - Zero cluster configuration  
✅ **Better for demos** - Vendors can test immediately  
✅ **No secrets to manage** - No imagePullSecrets needed  

### When to Keep Private

❌ Proprietary code  
❌ Contains secrets or credentials  
❌ Internal company tools only  
❌ Work-in-progress not ready for public  

For this open-source proof-of-concept: **Public is recommended!**

---

## Managing Private Packages

If you keep the package private, here's how to manage access.

### Grant Access to Other Users

**Via GitHub Web UI:**

1. Go to package page: https://github.com/users/mmorency2021/packages/container/monitoring-app
2. Click "Package settings"
3. Under "Manage Access" → "Invite teams or people"
4. Enter GitHub username or team name
5. Choose role:
   - **Read** - Can pull images only
   - **Write** - Can pull and push images
   - **Admin** - Full package management
6. Click "Add"

**Via GitHub CLI:**
```bash
# Grant read access (pull only)
gh api \
  --method PUT \
  -H "Accept: application/vnd.github+json" \
  /user/packages/container/monitoring-app/access \
  -f username='other-github-user' \
  -f role='read'
```

### Create Team Access (Organizations)

If this is an organization repository:

```bash
# Grant team access
gh api \
  --method PUT \
  -H "Accept: application/vnd.github+json" \
  /orgs/YOUR_ORG/packages/container/monitoring-app/access \
  -f team='developers' \
  -f role='read'
```

### Revoke Access

1. Go to package settings
2. Under "Manage Access"
3. Find the user/team
4. Click "Remove"

### Audit Who Has Access

```bash
# Via GitHub CLI (requires admin access)
gh api \
  -H "Accept: application/vnd.github+json" \
  /user/packages/container/monitoring-app/access

# Via web UI
# Package settings → Manage Access → See list
```

---

## Connecting Clusters to Private Packages

If your package is private, clusters need credentials to pull images.

### For Kubernetes

#### Step 1: Create Pull Token

Create a GitHub token with **only** `read:packages` scope:

1. Go to https://github.com/settings/tokens/new
2. Note: `ghcr-pull-readonly`
3. Expiration: Choose duration
4. Scopes: ✅ `read:packages` **ONLY** (not write!)
5. Generate token

**Why read-only?** If the token leaks, attackers can only pull (not push malicious images).

#### Step 2: Create Kubernetes Secret

```bash
# Replace YOUR_TOKEN with the actual token
oc create secret docker-registry ghcr-pull-secret \
  --docker-server=ghcr.io \
  --docker-username=mmorency2021 \
  --docker-password=YOUR_TOKEN \
  --docker-email=your-email@example.com \
  -n rootless-monitor

# Verify secret
oc get secret ghcr-pull-secret -n rootless-monitor

# View secret details (base64 encoded)
oc get secret ghcr-pull-secret -n rootless-monitor -o yaml
```

#### Step 3: Update DaemonSet Manifests

Edit `kubernetes/daemonset-minimal.yaml`:

```yaml
apiVersion: apps/v1
kind: DaemonSet
metadata:
  name: rootless-monitor-minimal
  namespace: rootless-monitor
spec:
  template:
    spec:
      # ADD THIS SECTION:
      imagePullSecrets:
      - name: ghcr-pull-secret
      
      # Rest of spec...
      serviceAccountName: rootless-monitor
      securityContext:
        # ...
```

Repeat for `daemonset-enhanced.yaml` and `daemonset-ebpf.yaml`.

#### Step 4: Deploy

```bash
oc apply -f kubernetes/daemonset-minimal.yaml

# Verify pods pull successfully
oc get pods -n rootless-monitor -w
```

### For OpenShift

OpenShift provides additional options.

#### Option A: Docker Registry Secret (Same as K8s)

```bash
# Create secret
oc create secret docker-registry ghcr-pull-secret \
  --docker-server=ghcr.io \
  --docker-username=mmorency2021 \
  --docker-password=YOUR_TOKEN \
  --docker-email=your-email@example.com \
  -n rootless-monitor

# Link secret to service account (IMPORTANT for OpenShift!)
oc secrets link rootless-monitor ghcr-pull-secret --for=pull -n rootless-monitor

# Verify link
oc describe sa rootless-monitor -n rootless-monitor
# Should show ghcr-pull-secret under "Image pull secrets"
```

Now deploy without modifying manifests:
```bash
oc apply -f kubernetes/daemonset-minimal.yaml
# Secret is automatically used via service account link
```

#### Option B: Global Pull Secret (OpenShift 4.x)

For cluster-wide access to GHCR:

```bash
# Extract current global pull secret
oc get secret pull-secret -n openshift-config -o jsonpath='{.data.\.dockerconfigjson}' | base64 -d > /tmp/pull-secret.json

# Create GHCR auth entry
cat <<EOF > /tmp/ghcr-auth.json
{
  "auths": {
    "ghcr.io": {
      "auth": "$(echo -n 'mmorency2021:YOUR_TOKEN' | base64)"
    }
  }
}
EOF

# Merge with existing pull secret
jq -s '.[0] * .[1]' /tmp/pull-secret.json /tmp/ghcr-auth.json > /tmp/merged-pull-secret.json

# Update cluster pull secret
oc set data secret/pull-secret \
  -n openshift-config \
  --from-file=.dockerconfigjson=/tmp/merged-pull-secret.json

# Wait for nodes to roll (this takes 10-30 minutes!)
oc get nodes -w

# Clean up temp files
rm /tmp/pull-secret.json /tmp/ghcr-auth.json /tmp/merged-pull-secret.json
```

**Warning**: This adds GHCR credentials to ALL nodes. Use for production clusters where GHCR is standard.

#### Option C: ImageStream with Secret

```bash
# Create secret
oc create secret docker-registry ghcr-pull-secret \
  --docker-server=ghcr.io \
  --docker-username=mmorency2021 \
  --docker-password=YOUR_TOKEN \
  -n rootless-monitor

# Link to builder and default service accounts
oc secrets link builder ghcr-pull-secret -n rootless-monitor
oc secrets link default ghcr-pull-secret -n rootless-monitor

# Create ImageStream
oc create imagestream rootless-monitor -n rootless-monitor

# Import from GHCR (uses linked secret)
oc import-image rootless-monitor:latest \
  --from=ghcr.io/mmorency2021/monitoring-app:latest \
  --reference-policy=local \
  --confirm \
  -n rootless-monitor

# Update DaemonSet to use ImageStream
# Change image to:
#   image: image-registry.openshift-image-registry.svc:5000/rootless-monitor/rootless-monitor:latest
```

### Rotating Credentials

Tokens should be rotated periodically.

```bash
# 1. Create new GitHub token

# 2. Delete old secret
oc delete secret ghcr-pull-secret -n rootless-monitor

# 3. Create new secret with new token
oc create secret docker-registry ghcr-pull-secret \
  --docker-server=ghcr.io \
  --docker-username=mmorency2021 \
  --docker-password=NEW_TOKEN \
  --docker-email=your-email@example.com \
  -n rootless-monitor

# 4. For OpenShift, re-link if needed
oc secrets link rootless-monitor ghcr-pull-secret --for=pull -n rootless-monitor

# 5. Restart pods to use new secret
oc rollout restart daemonset/rootless-monitor-minimal -n rootless-monitor
```

---

## Troubleshooting

### Package Not Created After Push

**Check:**
1. GitHub Actions workflow status (https://github.com/mmorency2021/monitoring-app/actions)
2. Workflow logs for errors
3. Token permissions (must have `write:packages`)

**Common fixes:**
- Re-run failed workflow
- Check token hasn't expired
- Verify repository has Actions enabled

### Cannot Pull Private Package from Cluster

**Error:** `ImagePullBackOff` or `ErrImagePull: unauthorized`

**Debug:**
```bash
# Check pod events
oc describe pod <pod-name> -n rootless-monitor

# Verify secret exists
oc get secret ghcr-pull-secret -n rootless-monitor

# Test secret is valid
oc run test-pull \
  --image=ghcr.io/mmorency2021/monitoring-app:latest \
  --restart=Never \
  --overrides='{"spec":{"imagePullSecrets":[{"name":"ghcr-pull-secret"}]}}' \
  -n rootless-monitor
```

**Fixes:**
- Verify token has `read:packages` scope
- Check token hasn't expired
- Ensure secret is in correct namespace
- For OpenShift: Verify service account is linked to secret

### Package Visibility Change Not Taking Effect

**Issue:** Changed to public but still getting auth errors

**Fix:**
```bash
# Logout and test
docker logout ghcr.io
docker pull ghcr.io/mmorency2021/monitoring-app:latest

# Wait 1-2 minutes for GitHub CDN to propagate
```

---

## Best Practices

### For Open Source Projects (Like This One)

✅ **Make package public**  
✅ **Use GitHub Actions for auto-builds**  
✅ **Tag releases with semantic versions**  
✅ **Document image locations in README**  
✅ **No cluster secrets needed**  

### For Private/Enterprise Projects

✅ **Keep package private**  
✅ **Use read-only tokens for clusters**  
✅ **Rotate tokens quarterly**  
✅ **Use OpenShift global pull secret for production**  
✅ **Audit access regularly**  
✅ **Never commit tokens to git**  

---

## Quick Reference

### Package URLs
```
Public package page: https://github.com/mmorency2021?tab=packages
Package settings: https://github.com/users/mmorency2021/packages/container/monitoring-app/settings
Actions status: https://github.com/mmorency2021/monitoring-app/actions
Token creation: https://github.com/settings/tokens/new
```

### Common Commands
```bash
# Login
echo $GITHUB_TOKEN | docker login ghcr.io -u mmorency2021 --password-stdin

# Push
docker push ghcr.io/mmorency2021/monitoring-app:latest

# Pull (public)
docker pull ghcr.io/mmorency2021/monitoring-app:latest

# Create K8s secret
oc create secret docker-registry ghcr-pull-secret \
  --docker-server=ghcr.io \
  --docker-username=mmorency2021 \
  --docker-password=$GITHUB_TOKEN \
  -n rootless-monitor

# Link in OpenShift
oc secrets link rootless-monitor ghcr-pull-secret --for=pull
```

---

## Summary

| Scenario | Solution |
|----------|----------|
| Open source project | Make package PUBLIC → no cluster config needed |
| Private development | Keep PRIVATE → use imagePullSecrets |
| Auto-build on commit | GitHub Actions (already configured) |
| Manual push | Use `./push-to-ghcr.sh` script |
| Kubernetes cluster | Create docker-registry secret |
| OpenShift cluster | Link secret to service account |
| Token rotation | Delete/recreate secret, restart pods |

**For this project**: Making the package **PUBLIC** is recommended since it's an open-source proof-of-concept!
