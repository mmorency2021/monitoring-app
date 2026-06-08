# Testing Guide: Rootless Monitor Agent

This guide shows how to verify that the rootless monitor can actually monitor processes and logs without root privileges.

## 📋 Prerequisites

```bash
# Make sure you have kubectl access
kubectl version --client

# Make sure you have a Kubernetes cluster
kubectl cluster-info
```

## 🚀 Quick Deployment

```bash
cd rootless-monitor-agent

# Build the image (or use pre-built)
docker build -t rootless-monitor:latest .

# If using minikube/kind, load the image
minikube image load rootless-monitor:latest  # For minikube
kind load docker-image rootless-monitor:latest  # For kind

# Deploy everything
kubectl apply -f kubernetes/namespace.yaml
kubectl apply -f kubernetes/serviceaccount.yaml
kubectl apply -f kubernetes/configmap.yaml
kubectl apply -f kubernetes/daemonset-minimal.yaml

# Wait for pod to be ready
kubectl wait --for=condition=ready pod -l app=rootless-monitor -n rootless-monitor --timeout=60s
```

## ✅ Test 1: Verify Non-Root Operation

### What We're Testing
Confirm the container is running as UID 1000 (non-root), not UID 0 (root).

### Commands

```bash
# Get running pods
POD=$(kubectl get pod -n rootless-monitor -l app=rootless-monitor -o jsonpath='{.items[0].metadata.name}')
echo "Testing pod: $POD"

# Check what user the process is running as
echo "=== User ID Check ==="
kubectl exec -n rootless-monitor $POD -- id

# Expected output:
# uid=1000(monitor) gid=1000(monitor) groups=1000(monitor)
# ✅ PASS if UID=1000
# ❌ FAIL if UID=0 (root)

# Verify from /proc/self/status
kubectl exec -n rootless-monitor $POD -- grep -E "^Uid|^Gid" /proc/self/status

# Expected output:
# Uid:    1000    1000    1000    1000
# Gid:    1000    1000    1000    1000
# All four values should be 1000 (real, effective, saved set, filesystem UID/GID)
```

### Expected Result
✅ **PASS**: Container runs as UID 1000 (monitor user)  
❌ **FAIL**: If UID 0 appears anywhere

---

## ✅ Test 2: Monitor Host Processes

### What We're Testing
Verify the agent can see and monitor processes running on the host node.

### Commands

```bash
POD=$(kubectl get pod -n rootless-monitor -l app=rootless-monitor -o jsonpath='{.items[0].metadata.name}')

# Check that /host/proc is mounted
echo "=== Checking /host/proc mount ==="
kubectl exec -n rootless-monitor $POD -- ls -la /host/proc | head -20

# You should see numbered directories (PIDs) like:
# dr-xr-xr-x    9 root     root             0 Jan  1 00:00 1
# dr-xr-xr-x    9 root     root             0 Jan  1 00:00 2
# ...

# List some process details
echo "=== Reading process info for PID 1 (init) ==="
kubectl exec -n rootless-monitor $POD -- cat /host/proc/1/cmdline
# Expected: /sbin/init or similar

echo "=== Listing all running processes ==="
kubectl exec -n rootless-monitor $POD -- ls -1 /host/proc | grep -E '^[0-9]+$' | wc -l
# Expected: Should show number of processes (typically 100-300+)

# Read process command lines (what we monitor)
echo "=== Sample process command lines ==="
kubectl exec -n rootless-monitor $POD -- sh -c 'for pid in $(ls -1 /host/proc | grep -E "^[0-9]+$" | head -10); do echo "PID $pid:"; cat /host/proc/$pid/cmdline 2>/dev/null | tr "\0" " " || echo "  (unreadable)"; done'

# Check the agent's own monitoring output
echo "=== Agent's process monitoring output ==="
kubectl logs -n rootless-monitor $POD --tail=100 | grep -A 20 "Process Monitoring"
```

### Expected Result
✅ **PASS**: Agent can read process information from `/host/proc`  
✅ **PASS**: Agent logs show "Detected X new processes"  
⚠️ **PARTIAL**: Some processes may be unreadable (permission denied) - this is normal

### What About Permission Denied?

Some processes cannot be read because:
- Processes owned by other users have restricted `/proc/<pid>` files
- Without `CAP_SYS_PTRACE`, we can't read all process memory details

**This is NORMAL and EXPECTED**. The agent can still:
- ✅ Read all processes' command lines
- ✅ Read all processes' status (state, memory, CPU)
- ✅ Detect new processes starting
- ❌ Cannot read detailed memory maps for other users' processes (would need CAP_SYS_PTRACE)

---

## ✅ Test 3: Monitor Container Logs

### What We're Testing
Verify the agent can access logs from other containers/pods via Kubernetes API and container log paths.

### Commands

```bash
POD=$(kubectl get pod -n rootless-monitor -l app=rootless-monitor -o jsonpath='{.items[0].metadata.name}')

# The agent has RBAC permissions to read pod logs via K8s API
# Let's verify it can list pods
echo "=== Can agent list pods via Kubernetes API? ==="
kubectl exec -n rootless-monitor $POD -- sh -c 'curl -s --cacert /var/run/secrets/kubernetes.io/serviceaccount/ca.crt -H "Authorization: Bearer $(cat /var/run/secrets/kubernetes.io/serviceaccount/token)" https://kubernetes.default.svc/api/v1/namespaces/default/pods | grep "\"kind\": \"Pod"'

# Expected: Should see JSON output with pod information
# ✅ PASS if you see pod data
# ❌ FAIL if you see "Forbidden" or error

# Container logs are typically stored at /var/log/containers on the host
# Check if we can read them (requires host path mount of /var/log/containers)
echo "=== Checking for container log access ==="
kubectl exec -n rootless-monitor $POD -- test -d /host/var/log/containers && echo "Container logs accessible" || echo "Container logs not mounted"

# NOTE: By default, we don't mount /var/log/containers for security
# If you need log monitoring, add this volume mount:
# - name: container-logs
#   hostPath:
#     path: /var/log/containers
#     type: DirectoryOrCreate
```

### Expected Result
✅ **PASS**: Agent can query Kubernetes API for pod information  
⚠️ **PARTIAL**: Container logs not accessible by default (requires additional mount)

### To Enable Container Log Monitoring

Add to `daemonset-minimal.yaml`:

```yaml
# In volumeMounts section:
- name: container-logs
  mountPath: /var/log/containers
  readOnly: true

# In volumes section:
- name: container-logs
  hostPath:
    path: /var/log/containers
    type: DirectoryOrCreate
```

Then test:
```bash
kubectl exec -n rootless-monitor $POD -- ls -la /var/log/containers
```

---

## ✅ Test 4: Monitor System Metrics

### What We're Testing
Verify the agent can collect CPU, memory, disk, and network metrics.

### Commands

```bash
POD=$(kubectl get pod -n rootless-monitor -l app=rootless-monitor -o jsonpath='{.items[0].metadata.name}')

# Check the agent's metrics output
echo "=== System Metrics from Agent ==="
kubectl logs -n rootless-monitor $POD --tail=100 | grep -A 10 "System Metrics"

# Expected output:
# === System Metrics ===
# CPU Usage: 12.3%
# Memory Usage: 45.6% (2.3GB / 8.0GB)
# Disk Usage: 34.5% (15.2GB / 50.0GB)
# Network I/O: 123.45MB sent, 456.78MB received

# Read metrics file
echo "=== Metrics JSON file ==="
kubectl exec -n rootless-monitor $POD -- cat /tmp/metrics.json

# Pretty print the metrics
kubectl exec -n rootless-monitor $POD -- cat /tmp/metrics.json | jq .
```

### Expected Result
✅ **PASS**: Agent collects and reports system metrics  
✅ **PASS**: Metrics file `/tmp/metrics.json` exists and contains valid JSON

---

## ✅ Test 5: Network Monitoring

### What We're Testing
Check if network connection monitoring works (requires `CAP_NET_RAW` for full functionality).

### Commands

```bash
POD=$(kubectl get pod -n rootless-monitor -l app=rootless-monitor -o jsonpath='{.items[0].metadata.name}')

# Check network monitoring output
echo "=== Network Monitoring ==="
kubectl logs -n rootless-monitor $POD --tail=100 | grep -A 15 "Network Monitoring"

# With MINIMAL version (no CAP_NET_RAW):
# Expected: May show warning "Network monitoring requires CAP_NET_RAW"
# Can still see SOME connections via psutil

# To get FULL network monitoring, use daemonset-enhanced.yaml instead:
# kubectl apply -f kubernetes/daemonset-enhanced.yaml
```

### Expected Result (Minimal Version)
⚠️ **LIMITED**: Basic network info available, but may see capability warnings  

### Expected Result (Enhanced Version with CAP_NET_RAW)
✅ **FULL**: Complete network connection tracking

---

## ✅ Test 6: Security Event Detection

### What We're Testing
Verify the agent can detect suspicious process patterns.

### Commands

```bash
POD=$(kubectl get pod -n rootless-monitor -l app=rootless-monitor -o jsonpath='{.items[0].metadata.name}')

# Check security monitoring output
echo "=== Security Event Detection ==="
kubectl logs -n rootless-monitor $POD --tail=100 | grep -A 10 "Security Event Detection"

# Expected (if no threats):
# === Security Event Detection ===
# ✅ No suspicious patterns detected

# Let's trigger a suspicious pattern for testing
# Run a netcat listener in a test pod
kubectl run test-threat --image=alpine --rm -it -- nc -l -p 8888 &

# Wait a bit for the monitor to detect it
sleep 35

# Check logs again
kubectl logs -n rootless-monitor $POD --tail=100 | grep -A 20 "SECURITY ALERTS"

# Clean up test pod
kubectl delete pod test-threat --force --grace-period=0 2>/dev/null || true
```

### Expected Result
✅ **PASS**: Agent can detect and log suspicious patterns  
✅ **PASS**: Should see alert for `nc -l` pattern if test-threat pod was detected

---

## ✅ Test 7: Verify Security Restrictions Work

### What We're Testing
Confirm that security restrictions prevent dangerous operations.

### Test 7a: Cannot Escalate Privileges

```bash
POD=$(kubectl get pod -n rootless-monitor -l app=rootless-monitor -o jsonpath='{.items[0].metadata.name}')

echo "=== Test: Attempting to escalate privileges ==="
kubectl exec -n rootless-monitor $POD -- sudo id 2>&1

# Expected: Error - sudo command not found OR permission denied
# ✅ PASS if command fails
# ❌ FAIL if you see "uid=0(root)"
```

### Test 7b: Cannot Write to Root Filesystem

```bash
echo "=== Test: Attempting to write to root filesystem ==="
kubectl exec -n rootless-monitor $POD -- touch /test.txt 2>&1

# Expected: Error - Read-only file system
# ✅ PASS if error about read-only filesystem
# ❌ FAIL if file is created
```

### Test 7c: Cannot Modify Host /proc

```bash
echo "=== Test: Attempting to modify host /proc ==="
kubectl exec -n rootless-monitor $POD -- sh -c 'echo test > /host/proc/sys/kernel/hostname' 2>&1

# Expected: Error - Read-only file system OR Permission denied
# ✅ PASS if modification fails
# ❌ FAIL if hostname changes
```

### Test 7d: Check Capabilities

```bash
echo "=== Test: Checking actual capabilities ==="
kubectl exec -n rootless-monitor $POD -- grep Cap /proc/self/status

# Expected for MINIMAL version:
# CapInh: 0000000000000000
# CapPrm: 0000000000000000
# CapEff: 0000000000000000
# CapBnd: 0000000000000000
# CapAmb: 0000000000000000
# All zeros = NO capabilities
# ✅ PASS if all are 0000000000000000

# For ENHANCED version, you'll see non-zero values for granted capabilities
```

### Expected Results
✅ **PASS**: All dangerous operations are blocked  
✅ **PASS**: Capabilities are minimal (or zero for minimal variant)

---

## ✅ Test 8: Continuous Monitoring

### What We're Testing
Verify the agent continuously monitors and exports metrics.

### Commands

```bash
POD=$(kubectl get pod -n rootless-monitor -l app=rootless-monitor -o jsonpath='{.items[0].metadata.name}')

# Watch logs in real-time
echo "=== Watching real-time monitoring (Ctrl+C to stop) ==="
kubectl logs -n rootless-monitor $POD -f

# In another terminal, watch metrics file update
echo "=== Watching metrics file updates ==="
watch -n 5 "kubectl exec -n rootless-monitor $POD -- cat /tmp/metrics.json | jq '.timestamp'"

# Generate some activity to monitor
# Create a pod that will show up in process monitoring
kubectl run test-workload --image=nginx

# Check if agent detected the new processes
sleep 35  # Wait for next monitoring cycle
kubectl logs -n rootless-monitor $POD --tail=50 | grep -i nginx
```

### Expected Result
✅ **PASS**: Agent runs continuous monitoring cycles  
✅ **PASS**: Metrics timestamp updates every 30 seconds (default interval)  
✅ **PASS**: New processes are detected in subsequent cycles

---

## 🎯 Summary Checklist

After running all tests, verify:

- [ ] Container runs as UID 1000 (non-root)
- [ ] Can read process info from `/host/proc`
- [ ] Can see host processes and their command lines
- [ ] Can collect system metrics (CPU, memory, disk)
- [ ] Network monitoring works (limited without CAP_NET_RAW)
- [ ] Security event detection functions
- [ ] Cannot escalate privileges (sudo fails)
- [ ] Cannot write to root filesystem
- [ ] Cannot modify host `/proc`
- [ ] Capabilities are minimal/zero
- [ ] Continuous monitoring cycles work
- [ ] Metrics export to `/tmp/metrics.json`

## 🐛 Troubleshooting

### Pod Won't Start

```bash
# Check events
kubectl describe pod -n rootless-monitor -l app=rootless-monitor

# Check namespace Pod Security Standards
kubectl get namespace rootless-monitor -o yaml | grep pod-security

# Common fixes:
# - Ensure image was built correctly
# - Check Pod Security Standards aren't blocking deployment
# - Verify securityContext is properly set
```

### No Process Data

```bash
# Verify /proc mount
kubectl exec -n rootless-monitor $POD -- ls /host/proc/1

# Check logs for errors
kubectl logs -n rootless-monitor $POD | grep -i error
```

### Permission Denied Errors

```bash
# Check what user is actually running
kubectl exec -n rootless-monitor $POD -- id

# Check file permissions
kubectl exec -n rootless-monitor $POD -- ls -la /host/proc

# Some permission denied errors are EXPECTED
# We're non-root, so can't access everything
```

## 📊 Performance Testing

```bash
POD=$(kubectl get pod -n rootless-monitor -l app=rootless-monitor -o jsonpath='{.items[0].metadata.name}')

# Check resource usage
kubectl top pod -n rootless-monitor

# Check detailed metrics
kubectl exec -n rootless-monitor $POD -- cat /tmp/metrics.json | jq

# Monitor over time
watch -n 5 kubectl top pod -n rootless-monitor
```

## 🔄 Testing Different Variants

### Test Enhanced Version (with capabilities)

```bash
# Deploy enhanced version
kubectl apply -f kubernetes/daemonset-enhanced.yaml

# Wait for rollout
kubectl rollout status daemonset/rootless-monitor-enhanced -n rootless-monitor

# Run tests again - network monitoring should work better
POD=$(kubectl get pod -n rootless-monitor -l variant=enhanced -o jsonpath='{.items[0].metadata.name}')
kubectl logs -n rootless-monitor $POD --tail=100 | grep "Network Monitoring"
```

### Test eBPF Version (modern approach)

```bash
# Check kernel version first
uname -r  # Should be 5.8+

# Deploy eBPF version
kubectl apply -f kubernetes/daemonset-ebpf.yaml

# Run tests
POD=$(kubectl get pod -n rootless-monitor -l variant=ebpf -o jsonpath='{.items[0].metadata.name}')
kubectl logs -n rootless-monitor $POD -f
```

---

## ✨ Success Criteria

You've successfully demonstrated rootless monitoring if:

1. ✅ Container runs as non-root (UID 1000)
2. ✅ Can monitor host processes
3. ✅ Can collect system metrics
4. ✅ Security restrictions prevent dangerous operations
5. ✅ No root privileges or privileged containers needed

**This proves to vendors (and any vendor) that EDR-like monitoring is possible without root access!**
