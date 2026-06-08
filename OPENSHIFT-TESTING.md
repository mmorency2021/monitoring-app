# OpenShift Testing Guide

This guide shows how to deploy and test the rootless monitoring agent on **OpenShift** and verify process/host monitoring works.

## OpenShift-Specific Considerations

OpenShift has **stricter** default security than vanilla Kubernetes:
- Security Context Constraints (SCCs) instead of PSPs
- Enforced non-root by default (good for us!)
- Random UIDs assigned in some cases
- Pod Security admission enabled

Our agent should work **out of the box** on OpenShift because we're already compliant with strict security.

---

## 🚀 Deployment on OpenShift

### Prerequisites

```bash
# Verify oc CLI is installed and logged in
oc version
oc whoami

# Check cluster access
oc cluster-info
```

### Option 1: Deploy Using kubectl (Compatible)

```bash
cd rootless-monitor-agent

# OpenShift accepts kubectl commands
kubectl apply -f kubernetes/namespace.yaml
kubectl apply -f kubernetes/serviceaccount.yaml
kubectl apply -f kubernetes/configmap.yaml
kubectl apply -f kubernetes/daemonset-minimal.yaml

# Wait for ready
kubectl wait --for=condition=ready pod -l app=rootless-monitor -n rootless-monitor --timeout=60s
```

### Option 2: Deploy Using oc

```bash
# Create project (OpenShift's namespace)
oc new-project rootless-monitor

# Apply manifests
oc apply -f kubernetes/serviceaccount.yaml
oc apply -f kubernetes/configmap.yaml
oc apply -f kubernetes/daemonset-minimal.yaml

# Check status
oc get pods -n rootless-monitor
oc get daemonset -n rootless-monitor
```

### Build Image on OpenShift

If you want to build the image directly on OpenShift:

```bash
# Create BuildConfig
oc new-build --name=rootless-monitor \
  --binary \
  --strategy=docker \
  -n rootless-monitor

# Start build from local Dockerfile
oc start-build rootless-monitor \
  --from-dir=. \
  --follow \
  -n rootless-monitor

# Update DaemonSet to use the built image
oc patch daemonset rootless-monitor-minimal \
  -n rootless-monitor \
  --type=json \
  -p='[{"op":"replace","path":"/spec/template/spec/containers/0/image","value":"image-registry.openshift-image-registry.svc:5000/rootless-monitor/rootless-monitor:latest"}]'
```

---

## ✅ Test 1: Verify Pod is Running as Non-Root

### Get Pod Name

```bash
# Using oc
POD=$(oc get pod -n rootless-monitor -l app=rootless-monitor -o jsonpath='{.items[0].metadata.name}')
echo "Testing pod: $POD"

# Or using kubectl
POD=$(kubectl get pod -n rootless-monitor -l app=rootless-monitor -o jsonpath='{.items[0].metadata.name}')
```

### Check User ID

```bash
# Verify running as UID 1000
oc exec -n rootless-monitor $POD -- id

# Expected output:
# uid=1000(monitor) gid=1000(monitor) groups=1000(monitor)
```

✅ **PASS** if UID = 1000  
❌ **FAIL** if UID = 0 (root)

### Check OpenShift SCC

```bash
# See which Security Context Constraint is being used
oc get pod -n rootless-monitor $POD -o yaml | grep "openshift.io/scc"

# Should show: restricted or restricted-v2 (both are good)
# Our agent is compatible with the most restrictive SCC
```

---

## ✅ Test 2: Monitor Host Processes

### What We're Testing
Verify the agent can see and read process information from the **OpenShift host node**.

### Test Process Visibility

```bash
POD=$(oc get pod -n rootless-monitor -l app=rootless-monitor -o jsonpath='{.items[0].metadata.name}')

# Check that /host/proc is mounted
echo "=== Checking /host/proc mount ==="
oc exec -n rootless-monitor $POD -- ls -la /host/proc | head -20

# You should see numbered directories (process PIDs):
# dr-xr-xr-x    9 root     root             0 Jun  8 00:00 1
# dr-xr-xr-x    9 root     root             0 Jun  8 00:00 2
# dr-xr-xr-x    9 root     root             0 Jun  8 00:00 100
# ...

echo ""
echo "=== Count of processes visible ==="
oc exec -n rootless-monitor $POD -- sh -c 'ls -1 /host/proc | grep -E "^[0-9]+$" | wc -l'

# Expected: Should show 100-500+ processes depending on node size
```

### Read Specific Process Info

```bash
# Read init process (PID 1)
echo "=== PID 1 (init) command line ==="
oc exec -n rootless-monitor $POD -- cat /host/proc/1/cmdline | tr '\0' ' '
echo ""

# Expected: /usr/lib/systemd/systemd or similar

# Read a container process
echo "=== Finding container processes ==="
oc exec -n rootless-monitor $POD -- sh -c '
for pid in $(ls -1 /host/proc | grep -E "^[0-9]+$" | head -20); do
    cmdline=$(cat /host/proc/$pid/cmdline 2>/dev/null | tr "\0" " " || echo "")
    if echo "$cmdline" | grep -q "container\|kube\|pod"; then
        echo "PID $pid: $cmdline"
    fi
done
'

# Expected: Should find kubelet, container runtime processes, etc.
```

### Check Agent's Monitoring Output

```bash
# View agent's process monitoring logs
echo "=== Agent's Process Monitoring Output ==="
oc logs -n rootless-monitor $POD --tail=100 | grep -A 20 "Process Monitoring"

# Expected output should show:
# === Process Monitoring ===
# Detected X new processes:
#   PID 1234: /usr/bin/some-process ...
#   PID 5678: /usr/bin/another-process ...
# Total processes tracked: XXX
```

### ✅ Expected Results

- ✅ Can list `/host/proc` directory
- ✅ Can see hundreds of process PIDs
- ✅ Can read process command lines (cmdline)
- ✅ Agent logs show "Detected X new processes"
- ⚠️ Some processes may show "permission denied" - **this is normal and expected**

### ⚠️ About Permission Denied

Some `/proc/<pid>/` files will be unreadable because:
- Different user UID owns the process
- Without `CAP_SYS_PTRACE`, we can't read all process details

**This is EXPECTED** - we're non-root, so we can't access everything.

**What we CAN still read**:
- ✅ All process command lines (`/proc/<pid>/cmdline`)
- ✅ Process status (`/proc/<pid>/status`) for most processes
- ✅ Process stats (`/proc/<pid>/stat`)
- ✅ Detect new processes starting

**What we CANNOT read**:
- ❌ Memory maps for other users' processes (`/proc/<pid>/maps`)
- ❌ Open file descriptors for restricted processes (`/proc/<pid>/fd/`)
- ❌ Detailed memory info for other UIDs

---

## ✅ Test 3: Monitor Host System Information

### What We're Testing
Verify the agent can read host system information from `/sys` and `/proc` for metrics.

### Check /sys Access

```bash
POD=$(oc get pod -n rootless-monitor -l app=rootless-monitor -o jsonpath='{.items[0].metadata.name}')

# Check that /host/sys is mounted
echo "=== Checking /host/sys mount ==="
oc exec -n rootless-monitor $POD -- ls -la /host/sys | head -15

# Expected: Should see directories like block, class, devices, kernel, module, etc.

# Check network interfaces
echo ""
echo "=== Network Interfaces (from /sys) ==="
oc exec -n rootless-monitor $POD -- ls -la /host/sys/class/net/

# Expected: eth0, lo, and other interfaces

# Check block devices (disks)
echo ""
echo "=== Block Devices (from /sys) ==="
oc exec -n rootless-monitor $POD -- ls -la /host/sys/block/

# Expected: sda, vda, or similar disk devices
```

### Check System Metrics Collection

```bash
# View agent's system metrics output
echo "=== Agent's System Metrics Output ==="
oc logs -n rootless-monitor $POD --tail=100 | grep -A 10 "System Metrics"

# Expected output:
# === System Metrics ===
# CPU Usage: XX.X%
# Memory Usage: XX.X% (X.XGB / X.XGB)
# Disk Usage: XX.X% (X.XGB / X.XGB)
# Network I/O: X.XMB sent, X.XMB received
```

### Read Metrics JSON File

```bash
# Check the exported metrics
echo "=== Metrics JSON ==="
oc exec -n rootless-monitor $POD -- cat /tmp/metrics.json

# Pretty print
oc exec -n rootless-monitor $POD -- cat /tmp/metrics.json | jq .

# Expected: Valid JSON with timestamp, node name, metrics
```

### ✅ Expected Results

- ✅ Can read `/host/sys` directories
- ✅ Can see network interfaces
- ✅ Can see block devices
- ✅ Agent collects CPU, memory, disk metrics
- ✅ Metrics exported to `/tmp/metrics.json`

---

## ✅ Test 4: Continuous Monitoring

### Watch Real-Time Logs

```bash
POD=$(oc get pod -n rootless-monitor -l app=rootless-monitor -o jsonpath='{.items[0].metadata.name}')

# Stream logs (Ctrl+C to stop)
oc logs -n rootless-monitor $POD -f

# You should see monitoring cycles every 30 seconds:
# ============================================================
# Monitoring Cycle - 2026-06-08 14:30:00
# ============================================================
# === Process Monitoring ===
# Detected 5 new processes:
#   PID 12345: /usr/bin/program
# ...
# === Network Monitoring ===
# Network connections by state:
#   ESTABLISHED: 42
#   LISTEN: 15
# ...
# === System Metrics ===
# CPU Usage: 12.3%
# ...
```

### Generate Activity to Monitor

In another terminal, create some processes for the agent to detect:

```bash
# Create a test pod that will show up in monitoring
oc run test-nginx --image=nginx -n default

# Wait a bit for the monitoring cycle
sleep 35

# Check if agent detected the new nginx processes
oc logs -n rootless-monitor $POD --tail=100 | grep -i nginx

# Expected: Should see nginx processes detected

# Clean up test pod
oc delete pod test-nginx -n default
```

### ✅ Expected Results

- ✅ Monitoring cycles run every 30 seconds
- ✅ New processes are detected
- ✅ Metrics are continuously updated
- ✅ Agent doesn't crash or restart

---

## ✅ Test 5: Security Restrictions Work

### Test Cannot Escalate Privileges

```bash
POD=$(oc get pod -n rootless-monitor -l app=rootless-monitor -o jsonpath='{.items[0].metadata.name}')

echo "=== Test 1: Cannot use sudo ==="
oc exec -n rootless-monitor $POD -- sudo id 2>&1

# Expected: Error - sudo: command not found OR permission denied
# ✅ PASS if command fails
# ❌ FAIL if you see uid=0(root)
```

### Test Cannot Write to Root Filesystem

```bash
echo "=== Test 2: Cannot write to root filesystem ==="
oc exec -n rootless-monitor $POD -- touch /test.txt 2>&1

# Expected: Error - Read-only file system
# ✅ PASS if error about read-only
# ❌ FAIL if file is created
```

### Test Cannot Modify Host /proc

```bash
echo "=== Test 3: Cannot modify host /proc ==="
oc exec -n rootless-monitor $POD -- sh -c 'echo test > /host/proc/sys/kernel/hostname' 2>&1

# Expected: Error - Read-only file system OR Permission denied
# ✅ PASS if modification fails
```

### Check Actual Capabilities

```bash
echo "=== Test 4: Check capabilities ==="
oc exec -n rootless-monitor $POD -- grep Cap /proc/self/status

# Expected for MINIMAL version (all zeros):
# CapInh: 0000000000000000
# CapPrm: 0000000000000000
# CapEff: 0000000000000000
# CapBnd: 0000000000000000
# CapAmb: 0000000000000000

# ✅ PASS if all are 0000000000000000 (no capabilities)
```

---

## 📊 OpenShift-Specific Monitoring

### Check Pod Resource Usage

```bash
# View resource usage
oc adm top pod -n rootless-monitor

# Expected: Memory and CPU usage shown
```

### Check Node Assignment

```bash
# See which nodes the DaemonSet pods are on
oc get pods -n rootless-monitor -o wide

# Shows: Pod name, Node name, IP, etc.
```

### Check Events

```bash
# View events for the namespace
oc get events -n rootless-monitor --sort-by='.lastTimestamp' | tail -20

# Look for: Pod scheduled, pulled image, started, etc.
```

---

## 🔧 Troubleshooting on OpenShift

### Pod Stuck in Pending

```bash
# Check why
oc describe pod -n rootless-monitor $POD

# Common causes:
# - Image pull issues
# - SCC restrictions (unlikely with our manifests)
# - Resource constraints
```

**Fix for Image Pull**:
```bash
# If using internal registry
oc policy add-role-to-user system:image-puller system:serviceaccount:rootless-monitor:rootless-monitor -n rootless-monitor
```

### Permission Denied Errors

```bash
# Check SCC being used
oc get pod -n rootless-monitor $POD -o yaml | grep scc

# If using privileged SCC (wrong!), force restricted:
oc adm policy remove-scc-from-user privileged -z rootless-monitor -n rootless-monitor
```

### No Process Data

```bash
# Verify /proc mount
oc exec -n rootless-monitor $POD -- ls /host/proc/1

# If error, check DaemonSet volumes section
oc get daemonset -n rootless-monitor rootless-monitor-minimal -o yaml | grep -A 10 volumes
```

---

## 🎯 Success Checklist

After completing all tests, verify:

- [ ] Pod runs on all nodes (DaemonSet)
- [ ] Pod runs as UID 1000 (non-root)
- [ ] Can list `/host/proc` directory
- [ ] Can read process command lines
- [ ] Can see 100+ processes
- [ ] Agent logs show "Detected X new processes"
- [ ] Can read `/host/sys` directories
- [ ] System metrics are collected
- [ ] Metrics file `/tmp/metrics.json` exists
- [ ] Monitoring cycles every 30 seconds
- [ ] Cannot escalate to root (sudo fails)
- [ ] Cannot write to root filesystem
- [ ] Cannot modify `/host/proc`
- [ ] Capabilities are zero (minimal) or justified (enhanced/eBPF)

---

## 📝 Quick Test Script

Copy and run this all at once:

```bash
#!/bin/bash
POD=$(oc get pod -n rootless-monitor -l app=rootless-monitor -o jsonpath='{.items[0].metadata.name}')

echo "=== Testing Rootless Monitor on OpenShift ==="
echo ""

echo "1. User ID Check:"
oc exec -n rootless-monitor $POD -- id
echo ""

echo "2. Process Count:"
oc exec -n rootless-monitor $POD -- sh -c 'ls -1 /host/proc | grep -E "^[0-9]+$" | wc -l'
echo ""

echo "3. Sample Process:"
oc exec -n rootless-monitor $POD -- cat /host/proc/1/cmdline | tr '\0' ' '
echo ""

echo "4. System Metrics:"
oc exec -n rootless-monitor $POD -- cat /tmp/metrics.json | jq '.metrics'
echo ""

echo "5. Security Test (should fail):"
oc exec -n rootless-monitor $POD -- touch /test.txt 2>&1 | head -1
echo ""

echo "6. Capabilities (should be all zeros):"
oc exec -n rootless-monitor $POD -- grep CapEff /proc/self/status
echo ""

echo "=== Test Complete ==="
```

---

## ✨ Success Criteria

**You've proven rootless monitoring works on OpenShift if**:

1. ✅ Pod runs as non-root (UID 1000)
2. ✅ Can monitor host processes via `/host/proc`
3. ✅ Can read host system info via `/host/sys`
4. ✅ Collects system metrics (CPU, memory, disk)
5. ✅ Security restrictions prevent privilege escalation
6. ✅ Runs on OpenShift's strictest SCC (restricted/restricted-v2)

**This proves that EDR-like monitoring is possible without root privileges, even on OpenShift's strict security!**
