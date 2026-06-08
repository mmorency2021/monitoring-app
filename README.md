# Rootless Node Monitoring Agent

A demonstration of EDR-like monitoring capabilities **without root privileges**, designed to show vendors (or any vendor) how to implement secure, rootless container monitoring in Kubernetes.

## 🎯 Purpose

This project proves that **effective node monitoring is possible without running as root**. It demonstrates:

- ✅ Process monitoring via `/proc` filesystem
- ✅ Network connection tracking
- ✅ System metrics collection
- ✅ Security event detection
- ✅ All with non-root user (UID 1000)
- ✅ Compliant with Kubernetes Pod Security Standards (Restricted tier)

## 🏗️ Architecture

```
┌─────────────────────────────────────────┐
│  Kubernetes Node                        │
│  ┌───────────────────────────────────┐  │
│  │ rootless-monitor Pod              │  │
│  │ ┌───────────────────────────────┐ │  │
│  │ │ monitor container             │ │  │
│  │ │ User: monitor (UID 1000)      │ │  │
│  │ │ ────────────────────────────  │ │  │
│  │ │ • Read /host/proc (ro)        │ │  │
│  │ │ • Read /host/sys (ro)         │ │  │
│  │ │ • Write to /tmp (tmpfs)       │ │  │
│  │ │ • Capabilities: (varies)      │ │  │
│  │ └───────────────────────────────┘ │  │
│  └───────────────────────────────────┘  │
└─────────────────────────────────────────┘
```

## 📦 What's Included

### Application
- **`monitor.py`**: Python-based monitoring agent
- **`Dockerfile`**: Multi-stage build with non-root user

### Kubernetes Manifests
Three deployment variants with different capability levels:

1. **`daemonset-minimal.yaml`** (MOST RESTRICTIVE)
   - Zero capabilities
   - Only basic process/system monitoring
   - Best for proving rootless concept

2. **`daemonset-enhanced.yaml`** (BALANCED)
   - `CAP_SYS_PTRACE` - process inspection
   - `CAP_NET_RAW` - network packet capture
   - Similar to what NEDR would need

3. **`daemonset-ebpf.yaml`** (MODERN, RECOMMENDED)
   - `CAP_BPF` - eBPF program loading
   - `CAP_PERFMON` - performance monitoring
   - Requires Linux kernel 5.8+

### Security Configs
- **`namespace.yaml`**: Namespace with Pod Security Standards enforcement
- **`serviceaccount.yaml`**: RBAC with read-only K8s API access
- **`pod-security-policy.yaml`**: Legacy PSP for older clusters
- **`configmap.yaml`**: Agent configuration

## 🚀 Quick Start

### 1. Build the Container Image

```bash
cd rootless-monitor-agent

# Build the image
docker build -t rootless-monitor:latest .

# Verify it's built correctly
docker run --rm rootless-monitor:latest id
# Should show: uid=1000(monitor) gid=1000(monitor)
```

### 2. Deploy to Kubernetes

```bash
# Create namespace (with Pod Security Standards enforcement)
kubectl apply -f kubernetes/namespace.yaml

# Create ServiceAccount and RBAC
kubectl apply -f kubernetes/serviceaccount.yaml

# Create ConfigMap
kubectl apply -f kubernetes/configmap.yaml

# Deploy ONE of the following variants:

# Option A: Minimal (no capabilities)
kubectl apply -f kubernetes/daemonset-minimal.yaml

# Option B: Enhanced (CAP_SYS_PTRACE, CAP_NET_RAW)
kubectl apply -f kubernetes/daemonset-enhanced.yaml

# Option C: eBPF (CAP_BPF, CAP_PERFMON) - requires Linux 5.8+
kubectl apply -f kubernetes/daemonset-ebpf.yaml
```

### 3. Verify Deployment

```bash
# Check pods are running
kubectl get pods -n rootless-monitor

# Verify security context
kubectl get pod -n rootless-monitor -l app=rootless-monitor -o jsonpath='{.items[0].spec.securityContext}' | jq

# Check logs
kubectl logs -n rootless-monitor -l app=rootless-monitor --tail=50

# Verify running as non-root
kubectl exec -n rootless-monitor -l app=rootless-monitor -- id
# Expected: uid=1000(monitor) gid=1000(monitor)
```

### 4. Test Monitoring Capabilities

```bash
# View real-time monitoring output
kubectl logs -n rootless-monitor -l app=rootless-monitor -f

# Check metrics file
kubectl exec -n rootless-monitor -l app=rootless-monitor -- cat /tmp/metrics.json

# Verify capabilities
kubectl exec -n rootless-monitor -l app=rootless-monitor -- capsh --print

# Test security - this SHOULD FAIL (no privilege escalation)
kubectl exec -n rootless-monitor -l app=rootless-monitor -- sudo id
# Expected: Error - command not found or permission denied
```

## 📊 Monitoring Capabilities by Variant

| Feature | Minimal | Enhanced | eBPF |
|---------|---------|----------|------|
| **Capabilities** | None | CAP_SYS_PTRACE<br>CAP_NET_RAW | CAP_BPF<br>CAP_PERFMON |
| **Process Monitoring** | ✅ Basic | ✅ Full | ✅ Full |
| **Network Monitoring** | ❌ Limited | ✅ Full | ✅ Full |
| **System Metrics** | ✅ Yes | ✅ Yes | ✅ Yes |
| **Security Detection** | ✅ Pattern-based | ✅ Enhanced | ✅ Kernel-level |
| **Root Required?** | ❌ No | ❌ No | ❌ No |
| **Kernel Version** | Any | Any | 5.8+ |

## 🔐 Security Features

### What Makes This Secure

1. **Non-Root User**
   - Runs as UID 1000 (never root)
   - `runAsNonRoot: true` enforced at pod and container level

2. **Minimal Capabilities**
   - Drops ALL capabilities by default
   - Only adds specific ones needed (justified per variant)

3. **Read-Only Root Filesystem**
   - Container's root FS is immutable
   - Only `/tmp` and `/var/log` are writable (tmpfs)

4. **No Privilege Escalation**
   - `allowPrivilegeEscalation: false`
   - Cannot gain more privileges than parent

5. **Namespace Enforcement**
   - Pod Security Standards (Restricted tier)
   - Blocks non-compliant pods automatically

6. **Least Privilege RBAC**
   - ServiceAccount has read-only access to K8s API
   - Cannot modify cluster state

### What It Can Do (Without Root)

- ✅ Read `/proc` filesystem (process info)
- ✅ Read `/sys` filesystem (system info)
- ✅ Monitor system metrics (CPU, memory, disk, network)
- ✅ Detect suspicious process patterns
- ✅ Track network connections (with CAP_NET_RAW)
- ✅ Inspect process memory (with CAP_SYS_PTRACE)
- ✅ Load eBPF programs (with CAP_BPF)
- ✅ Export metrics and logs

### What It Cannot Do (Security Guaranteed)

- ❌ Modify host filesystem
- ❌ Access other containers' data
- ❌ Escalate to root privileges
- ❌ Bypass security policies
- ❌ Write to read-only volumes
- ❌ Change container's own security context

## 🧪 Testing Security

### Verify Non-Root Operation

```bash
# Should show UID 1000, not 0
kubectl exec -n rootless-monitor -l app=rootless-monitor -- id

# Should fail - no sudo
kubectl exec -n rootless-monitor -l app=rootless-monitor -- sudo whoami

# Should fail - read-only root FS
kubectl exec -n rootless-monitor -l app=rootless-monitor -- touch /test.txt
```

### Check Capabilities

```bash
# See what capabilities are granted
kubectl exec -n rootless-monitor -l app=rootless-monitor -- grep Cap /proc/self/status

# Decode capabilities (if capsh is available)
kubectl exec -n rootless-monitor -l app=rootless-monitor -- capsh --print
```

### Validate Pod Security Standards

```bash
# Check namespace labels
kubectl get namespace rootless-monitor -o yaml | grep pod-security

# Try to deploy a privileged pod (should be BLOCKED)
cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: Pod
metadata:
  name: test-privileged
  namespace: rootless-monitor
spec:
  containers:
  - name: test
    image: busybox
    command: ["sleep", "3600"]
    securityContext:
      privileged: true
EOF
# Expected: Error - violates PodSecurity "restricted:latest"
```

## 📝 Configuration

Edit `kubernetes/configmap.yaml` to customize:

```yaml
data:
  # How often to run monitoring cycle (seconds)
  monitor-interval: "30"

  # Enable/disable monitoring features
  monitor-processes: "true"
  monitor-network: "true"
  monitor-system: "true"
  monitor-security: "true"

  # Patterns to flag as suspicious
  suspicious-patterns: |
    [
      "nc -l",
      "/dev/tcp",
      "chmod 777"
    ]

  # Logging level
  log-level: "INFO"
```

Apply changes:
```bash
kubectl apply -f kubernetes/configmap.yaml
kubectl rollout restart daemonset/rootless-monitor-minimal -n rootless-monitor
```

## 🎓 For vendors / Vendors

This project demonstrates:

### ✅ What You Should Do

1. **Create non-root user in Dockerfile**
   ```dockerfile
   RUN useradd -u 1000 -g 1000 monitor
   USER monitor
   ```

2. **Set security context in manifests**
   ```yaml
   securityContext:
     runAsNonRoot: true
     runAsUser: 1000
     readOnlyRootFilesystem: true
     capabilities:
       drop: [ALL]
       add: [CAP_SYS_PTRACE]  # Only if needed
   ```

3. **Use read-only host mounts**
   ```yaml
   volumeMounts:
   - name: host-proc
     mountPath: /host/proc
     readOnly: true  # CRITICAL
   ```

4. **Document required capabilities**
   - Test with zero capabilities first
   - Add capabilities one by one
   - Justify each capability in documentation

5. **Prefer eBPF over traditional approaches**
   - Requires fewer capabilities
   - Better performance and stability
   - Industry best practice

### ❌ What to Avoid

- Running as root (UID 0)
- `privileged: true`
- `allowPrivilegeEscalation: true`
- `CAP_SYS_ADMIN` (too broad)
- Writable host path mounts
- `hostNetwork: true` (if avoidable)
- `hostPID: true` (use CAP_SYS_PTRACE instead)

## 📚 References

### Kubernetes Security
- [Pod Security Standards](https://kubernetes.io/docs/concepts/security/pod-security-standards/)
- [Security Context](https://kubernetes.io/docs/tasks/configure-pod-container/security-context/)
- [Linux Capabilities](https://man7.org/linux/man-pages/man7/capabilities.7.html)

### eBPF
- [eBPF Documentation](https://ebpf.io/)
- [Cilium Tetragon](https://github.com/cilium/tetragon)
- [Falco](https://falco.org/)

### Industry Examples
- [Microsoft Defender eBPF Mode](https://learn.microsoft.com/en-us/defender-endpoint/linux-support-ebpf)
- [Datadog Agent eBPF](https://docs.datadoghq.com/infrastructure/process/)

## 🐛 Troubleshooting

### Pod Won't Start

```bash
# Check events
kubectl describe pod -n rootless-monitor -l app=rootless-monitor

# Common issues:
# - "Error: container has runAsNonRoot and image has non-numeric user"
#   → User is not set in Dockerfile, add USER 1000

# - "violates PodSecurity"
#   → Security context doesn't meet restricted requirements
```

### No Process Monitoring Data

```bash
# Check if /proc is mounted
kubectl exec -n rootless-monitor -l app=rootless-monitor -- ls /host/proc

# Check permissions
kubectl exec -n rootless-monitor -l app=rootless-monitor -- ls -la /host/proc/1
```

### Network Monitoring Fails

```bash
# Requires CAP_NET_RAW capability
# Use daemonset-enhanced.yaml or daemonset-ebpf.yaml

# Check capabilities
kubectl exec -n rootless-monitor -l app=rootless-monitor -- grep Cap /proc/self/status
```

## 📄 License

This is a proof-of-concept for educational purposes. Use it to demonstrate secure, rootless monitoring to vendors.

## 🤝 Contributing

This is a demonstration project to help telcos enforce security requirements with vendors. Feel free to adapt it for your own use cases.

---

**Key Takeaway**: Rootless monitoring is not only possible, but it's the **industry best practice**. Vendors should adapt to Pod Security Standards rather than requesting exceptions.
