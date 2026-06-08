#!/bin/bash
# Push to GitHub Container Registry (ghcr.io)
set -e

REGISTRY="ghcr.io"
USERNAME="mmorency2021"
IMAGE_NAME="monitoring-app"
TAG="latest"

FULL_IMAGE="${REGISTRY}/${USERNAME}/${IMAGE_NAME}:${TAG}"

echo "=========================================="
echo "Pushing to GitHub Container Registry"
echo "=========================================="
echo ""
echo "Image: ${FULL_IMAGE}"
echo ""

# Check if logged in to ghcr.io
echo "Step 1: Login to GitHub Container Registry..."
echo "You'll need a GitHub Personal Access Token with 'write:packages' scope"
echo "Create one at: https://github.com/settings/tokens/new"
echo ""

# Login (will prompt for token)
echo "Enter your GitHub username when prompted for 'Username'"
echo "Enter your Personal Access Token when prompted for 'Password'"
docker login ghcr.io

echo ""
echo "Step 2: Building image..."
docker build -t rootless-monitor:latest .
echo "✓ Image built"

echo ""
echo "Step 3: Tagging image for GHCR..."
docker tag rootless-monitor:latest ${FULL_IMAGE}
echo "✓ Image tagged as ${FULL_IMAGE}"

echo ""
echo "Step 4: Pushing to GitHub Container Registry..."
docker push ${FULL_IMAGE}
echo "✓ Image pushed!"

echo ""
echo "=========================================="
echo "Success!"
echo "=========================================="
echo ""
echo "Image is now available at:"
echo "  ${FULL_IMAGE}"
echo ""
echo "Update your Kubernetes manifests to use:"
echo "  image: ${FULL_IMAGE}"
echo ""
echo "Make the package public (recommended for open source):"
echo "  1. Go to https://github.com/${USERNAME}?tab=packages"
echo "  2. Click on '${IMAGE_NAME}'"
echo "  3. Package settings -> Change visibility -> Public"
echo ""
