#!/bin/bash
# Deployment script for Rootless Monitor Agent
set -e

echo "=========================================="
echo "Rootless Monitor Agent - Deployment"
echo "=========================================="
echo ""

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Configuration
NAMESPACE="rootless-monitor"
IMAGE_NAME="rootless-monitor:latest"
VARIANT="${1:-minimal}"  # minimal, enhanced, or ebpf

# Function to print colored output
print_success() { echo -e "${GREEN}✓${NC} $1"; }
print_error() { echo -e "${RED}✗${NC} $1"; }
print_info() { echo -e "${YELLOW}ℹ${NC} $1"; }

# Check prerequisites
echo "Step 1: Checking prerequisites..."
if ! command -v oc &> /dev/null; then
    print_error "oc not found. Please install the OpenShift CLI first."
    exit 1
fi
print_success "oc found"

if ! command -v docker &> /dev/null; then
    print_error "docker not found. Please install Docker first."
    exit 1
fi
print_success "Docker found"

# Check cluster connection
echo ""
echo "Step 2: Checking OpenShift cluster connection..."
if ! oc status &> /dev/null; then
    print_error "Cannot connect to OpenShift cluster"
    exit 1
fi
print_success "Connected to OpenShift cluster"

# Build Docker image
echo ""
echo "Step 3: Building Docker image..."
if docker build -t $IMAGE_NAME . ; then
    print_success "Docker image built: $IMAGE_NAME"
else
    print_error "Failed to build Docker image"
    exit 1
fi

# Load image into cluster (if using minikube or kind)
echo ""
echo "Step 4: Loading image into cluster..."
if command -v minikube &> /dev/null && minikube status &> /dev/null; then
    print_info "Detected minikube, loading image..."
    minikube image load $IMAGE_NAME
    print_success "Image loaded into minikube"
elif command -v kind &> /dev/null; then
    CLUSTERS=$(kind get clusters)
    if [ -n "$CLUSTERS" ]; then
        print_info "Detected kind, loading image..."
        kind load docker-image $IMAGE_NAME
        print_success "Image loaded into kind"
    fi
else
    print_info "Not using minikube or kind, skipping image load"
fi

# Create namespace
echo ""
echo "Step 5: Creating namespace with Pod Security Standards..."
oc apply -f kubernetes/namespace.yaml
print_success "Namespace created: $NAMESPACE"

# Create ServiceAccount and RBAC
echo ""
echo "Step 6: Creating ServiceAccount and RBAC..."
oc apply -f kubernetes/serviceaccount.yaml
print_success "ServiceAccount and RBAC configured"

# Create ConfigMap
echo ""
echo "Step 7: Creating ConfigMap..."
oc apply -f kubernetes/configmap.yaml
print_success "ConfigMap created"

# Deploy the selected variant
echo ""
echo "Step 8: Deploying monitoring agent (variant: $VARIANT)..."
case $VARIANT in
    minimal)
        oc apply -f kubernetes/daemonset-minimal.yaml
        print_success "Deployed minimal variant (no capabilities)"
        ;;
    enhanced)
        oc apply -f kubernetes/daemonset-enhanced.yaml
        print_success "Deployed enhanced variant (CAP_SYS_PTRACE, CAP_NET_RAW)"
        ;;
    ebpf)
        oc apply -f kubernetes/daemonset-ebpf.yaml
        print_success "Deployed eBPF variant (CAP_BPF, CAP_PERFMON)"
        print_info "Note: Requires Linux kernel 5.8+"
        ;;
    *)
        print_error "Unknown variant: $VARIANT"
        print_info "Usage: ./deploy.sh [minimal|enhanced|ebpf]"
        exit 1
        ;;
esac

# Wait for pods to be ready
echo ""
echo "Step 9: Waiting for pods to be ready..."
if oc wait --for=condition=ready pod -l app=rootless-monitor -n $NAMESPACE --timeout=60s; then
    print_success "Pods are ready"
else
    print_error "Pods failed to become ready"
    echo ""
    print_info "Checking pod status..."
    oc get pods -n $NAMESPACE
    echo ""
    print_info "Checking events..."
    oc get events -n $NAMESPACE --sort-by='.lastTimestamp' | tail -10
    exit 1
fi

# Get pod information
echo ""
echo "=========================================="
echo "Deployment Summary"
echo "=========================================="
POD=$(oc get pod -n $NAMESPACE -l app=rootless-monitor -o jsonpath='{.items[0].metadata.name}')
NODE=$(oc get pod -n $NAMESPACE $POD -o jsonpath='{.spec.nodeName}')

print_success "Pod deployed: $POD"
print_success "Running on node: $NODE"

# Verify non-root
echo ""
echo "Verifying security configuration..."
UID=$(oc rsh -n $NAMESPACE $POD id -u)
if [ "$UID" -eq 1000 ]; then
    print_success "Running as non-root user (UID: $UID)"
else
    print_error "WARNING: Not running as expected UID. Got UID: $UID"
fi

# Show initial logs
echo ""
echo "=========================================="
echo "Initial Logs (last 20 lines)"
echo "=========================================="
oc logs -n $NAMESPACE $POD --tail=20

# Print next steps
echo ""
echo "=========================================="
echo "Next Steps"
echo "=========================================="
echo ""
echo "View logs:"
echo "  oc logs -n $NAMESPACE $POD -f"
echo ""
echo "View metrics:"
echo "  oc rsh -n $NAMESPACE $POD cat /tmp/metrics.json | jq"
echo ""
echo "Check security:"
echo "  oc rsh -n $NAMESPACE $POD id"
echo "  oc rsh -n $NAMESPACE $POD grep Cap /proc/self/status"
echo ""
echo "Run full tests:"
echo "  See TESTING.md for comprehensive test suite"
echo ""
echo "Clean up:"
echo "  oc delete namespace $NAMESPACE"
echo ""
print_success "Deployment complete!"
