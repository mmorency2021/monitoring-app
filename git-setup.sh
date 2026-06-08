#!/bin/bash
# Simple script to initialize Git and push to GitHub
set -e

GITHUB_REPO="https://github.com/mmorency2021/monitoring-app.git"

echo "Setting up Git repository..."

# Initialize if needed
if [ ! -d .git ]; then
    git init
    echo "✓ Git initialized"
fi

# Add all files
git add .

# Create initial commit
git commit -m "Initial commit: Rootless monitoring agent for Kubernetes" || echo "✓ Already committed"

# Rename to main branch
git branch -M main

# Add remote
git remote remove origin 2>/dev/null || true
git remote add origin $GITHUB_REPO

echo ""
echo "Repository ready!"
echo ""
echo "To push to GitHub, run:"
echo "  git push -u origin main"
echo ""
echo "If repository doesn't exist, create it first at:"
echo "  https://github.com/mmorency2021/monitoring-app"
