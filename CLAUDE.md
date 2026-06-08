# CLAUDE.md - Project Instructions

## Project Overview

This is a **Rootless Node Monitoring Agent** - a proof-of-concept demonstrating that EDR-like monitoring capabilities can be achieved in Kubernetes **without root privileges**.

**Purpose**: Show security vendors that Pod Security Standards (Restricted tier) compliance is achievable while maintaining monitoring functionality.

## Project Context

### Background
We work in telco infrastructure where partners deploy CNFs (Container Network Functions) in our Kubernetes hub cluster. A security vendor had monitoring agents (similar to EDR/NEDR) running with root privileges, which violates our security policies.

**Our Security Requirements**:
- All containers MUST run as non-root (UID ≥ 1000)
- Pod Security Standards: Restricted tier enforcement
- Minimal Linux capabilities (drop ALL, add only what's justified)
- Read-only root filesystem where possible
- No privilege escalation allowed

### What This Project Demonstrates

✅ **Process monitoring** via `/proc` filesystem without root  
✅ **Network monitoring** with specific capabilities (not root)  
✅ **System metrics** collection (CPU, memory, disk, network)  
✅ **Security event detection** (suspicious process patterns)  
✅ **Three variants**: minimal (zero capabilities), enhanced (CAP_SYS_PTRACE, CAP_NET_RAW), eBPF (CAP_BPF, CAP_PERFMON)

## Architecture Principles

### Security-First Design

1. **Non-Root User**
   - Container runs as UID 1000 (`monitor` user)
   - Never UID 0 (root)
   - Enforced at pod AND container level (`runAsNonRoot: true`)

2. **Capability Minimization**
   - Drop ALL capabilities by default
   - Add back ONLY what's needed and justified
   - Three variants show progression: none → traditional → modern (eBPF)

3. **Read-Only Root Filesystem**
   - Container's root FS is immutable
   - Only `/tmp` and `/var/log` writable (tmpfs)
   - Prevents malware persistence

4. **Host Access via Read-Only Mounts**
   - `/proc` mounted as `/host/proc` (read-only)
   - `/sys` mounted as `/host/sys` (read-only)
   - No writable host paths

### Monitoring Strategy

**What We Monitor**:
- **Processes**: Via `/host/proc/<pid>/cmdline`, `/proc/<pid>/status`
- **Network**: Via `psutil.net_connections()` (requires CAP_NET_RAW for full data)
- **System**: CPU, memory, disk, network I/O via `psutil`
- **Security**: Pattern matching on process command lines for suspicious activity

**What We Don't Need Root For**:
- Reading `/proc` (world-readable files)
- Reading `/sys` (world-readable)
- System metrics (accessible to any user)
- Kubernetes API queries (RBAC-controlled)

**What Capabilities Enable**:
- `CAP_SYS_PTRACE`: Inspect other processes' memory/state
- `CAP_NET_RAW`: Capture network packets
- `CAP_BPF`: Load eBPF programs (modern, recommended)
- `CAP_PERFMON`: Access performance events

## File Structure

```
rootless-monitor-agent/
├── monitor.py              # Main monitoring agent (Python)
├── Dockerfile              # Multi-stage build with non-root user
├── README.md               # User-facing documentation
├── TESTING.md              # Comprehensive test guide
├── CONTRIBUTING.md         # Contribution guidelines
├── LICENSE                 # MIT License
├── deploy.sh               # One-command deployment script
├── git-setup.sh            # GitHub initialization helper
├── .gitignore              # Git ignore rules
│
└── kubernetes/             # K8s manifests
    ├── namespace.yaml              # Namespace with PSS enforcement
    ├── serviceaccount.yaml         # RBAC (read-only K8s API)
    ├── configmap.yaml              # Agent configuration
    ├── daemonset-minimal.yaml      # Zero capabilities variant
    ├── daemonset-enhanced.yaml     # CAP_SYS_PTRACE + CAP_NET_RAW
    ├── daemonset-ebpf.yaml         # CAP_BPF + CAP_PERFMON (modern)
    └── pod-security-policy.yaml    # Legacy PSP (deprecated)
```

## Key YAML Patterns

### Security Context (Container Level)

```yaml
securityContext:
  # CRITICAL: Non-root enforcement
  runAsNonRoot: true
  runAsUser: 1000
  runAsGroup: 1000
  
  # CRITICAL: Prevent privilege escalation
  allowPrivilegeEscalation: false
  
  # CRITICAL: Immutable root FS
  readOnlyRootFilesystem: true
  
  # CRITICAL: Minimal capabilities
  capabilities:
    drop:
      - ALL
    add:
      # Only add what's justified
      # - CAP_SYS_PTRACE  # For process inspection
      # - CAP_NET_RAW     # For network capture
      # - CAP_BPF         # For eBPF (recommended)
```

### Volume Mounts (Read-Only Host Access)

```yaml
volumeMounts:
  # Process monitoring
  - name: host-proc
    mountPath: /host/proc
    readOnly: true  # NEVER writable!
  
  # System info
  - name: host-sys
    mountPath: /host/sys
    readOnly: true  # NEVER writable!
  
  # Writable temp space (required with readOnlyRootFilesystem)
  - name: tmp
    mountPath: /tmp
  
volumes:
  - name: host-proc
    hostPath:
      path: /proc
      type: Directory
  
  - name: host-sys
    hostPath:
      path: /sys
      type: Directory
  
  - name: tmp
    emptyDir: {}  # Ephemeral tmpfs
```

## Development Guidelines

### When Making Changes

1. **Security First**: Never compromise on security requirements
2. **Test All Variants**: Changes should work with minimal, enhanced, and eBPF
3. **Document Capabilities**: If adding capabilities, document WHY in YAML comments
4. **Verify Non-Root**: Always test that `oc rsh <pod> id` shows UID 1000

### Adding New Monitoring Features

**Before adding a feature that needs capabilities**:
1. Try without capabilities first
2. Document why capabilities are needed
3. Use the most specific capability (not CAP_SYS_ADMIN)
4. Add to enhanced/eBPF variant only, not minimal

**Example**: To add file monitoring:
- First try: Read `/host/proc/<pid>/fd/` (no capabilities needed)
- If insufficient: Consider `CAP_DAC_READ_SEARCH` (read any file)
- Document: "File monitoring needs X because Y"

### Testing Checklist

Before committing:
- [ ] `docker build` succeeds
- [ ] Container runs as UID 1000
- [ ] `deploy.sh minimal` works
- [ ] Process monitoring shows data
- [ ] Security restrictions work (sudo fails, root FS read-only)
- [ ] All YAML has explanatory comments

## Common Tasks

### Build and Test Locally

```bash
# Build image
docker build -t rootless-monitor:latest .

# Verify non-root
docker run --rm rootless-monitor:latest id
# Expected: uid=1000(monitor) gid=1000(monitor)

# Deploy to Kubernetes
./deploy.sh minimal

# Check logs
oc logs -n rootless-monitor -l app=rootless-monitor -f

# Verify security
oc rsh -n rootless-monitor $POD id
oc rsh -n rootless-monitor $POD grep Cap /proc/self/status
```

### Add New Suspicious Pattern

Edit `kubernetes/configmap.yaml`:
```yaml
suspicious-patterns: |
  [
    "nc -l",
    "YOUR_NEW_PATTERN"
  ]
```

Then: `oc apply -f kubernetes/configmap.yaml && oc rollout restart daemonset -n rootless-monitor`

### Switch Variants

```bash
# Minimal (no capabilities)
oc apply -f kubernetes/daemonset-minimal.yaml

# Enhanced (CAP_SYS_PTRACE, CAP_NET_RAW)
oc apply -f kubernetes/daemonset-enhanced.yaml

# eBPF (CAP_BPF, CAP_PERFMON - requires Linux 5.8+)
oc apply -f kubernetes/daemonset-ebpf.yaml
```

## Reference Information

### Why Each Security Setting Exists

| Setting | Purpose | What It Prevents |
|---------|---------|------------------|
| `runAsNonRoot: true` | Forces non-root user | Running as UID 0 (root) |
| `runAsUser: 1000` | Explicitly sets UID | Image defaulting to root |
| `allowPrivilegeEscalation: false` | Blocks setuid/setgid | Gaining more privileges |
| `readOnlyRootFilesystem: true` | Immutable root FS | Malware persistence |
| `capabilities.drop: [ALL]` | Remove all caps | Kernel-level privileges |
| `seccompProfile: RuntimeDefault` | Syscall filtering | Dangerous syscalls |

### Capability Reference

| Capability | What It Allows | When We Need It |
|------------|----------------|-----------------|
| `CAP_SYS_PTRACE` | Trace processes | Detailed process inspection |
| `CAP_NET_RAW` | Raw sockets | Network packet capture |
| `CAP_NET_ADMIN` | Network config | Interface monitoring |
| `CAP_BPF` | Load eBPF programs | Modern kernel observability |
| `CAP_PERFMON` | Perf events | Performance monitoring |
| `CAP_SYS_ADMIN` | ❌ TOO BROAD | Avoid - too powerful |

### Pod Security Standards Compliance

**Restricted Tier Requirements** (what we enforce):
- ✅ `runAsNonRoot: true`
- ✅ Drop ALL capabilities
- ✅ No privilege escalation
- ✅ No host namespaces (hostNetwork, hostPID, hostIPC)
- ✅ Restricted volume types
- ✅ Seccomp profile required
- ✅ Read-only root filesystem (strongly recommended)

## Vendor Communication

When talking to security vendors about rootless requirements:

**Key Points to Emphasize**:
1. This is a **compliance requirement**, not a preference
2. We've **proven it's possible** with this project
3. We can grant **specific capabilities** if justified
4. **eBPF is the modern approach** (industry standard)
5. Other telcos enforce the same requirements

**What to Provide**:
- Link to this GitHub repo as proof-of-concept
- Our Pod Security Standards configuration
- Decision tree for capabilities (see nokia-nedr-rootless-proposal.html)
- Offer to conduct joint PoC testing

## Known Limitations

### What Doesn't Work Without Root

- **Cannot read all process memory**: Some `/proc/<pid>/` files require matching UID
- **Cannot kill arbitrary processes**: Need to be same UID or have CAP_KILL
- **Cannot bind to ports < 1024**: Need CAP_NET_BIND_SERVICE
- **Cannot change file ownership**: Need CAP_CHOWN

### Acceptable Trade-offs

- ✅ Can monitor 95%+ of processes (command lines visible)
- ✅ Can detect security events via pattern matching
- ✅ Can collect system-wide metrics
- ⚠️ Some processes may show "permission denied" (expected, not critical)

## Troubleshooting

### Pod Won't Start - "violates PodSecurity"

**Cause**: Security context doesn't meet Restricted requirements  
**Fix**: Check that all security settings are present in manifest  
**Verify**: `oc describe pod -n rootless-monitor ...` shows violation details

### "Permission denied" for some /proc files

**Cause**: Non-root user can't read other users' processes  
**Status**: **EXPECTED** - this is normal and acceptable  
**Impact**: Can still monitor command lines and most process info

### Network monitoring shows warnings

**Cause**: Missing `CAP_NET_RAW` capability  
**Fix**: Use `daemonset-enhanced.yaml` or `daemonset-ebpf.yaml`  
**Or**: Accept limited network monitoring in minimal variant

## Related Resources

### Internal Documents
- `nokia-nedr-rootless-proposal.html` - Formal proposal to vendors
- `nedr-security-enforcement-guide.html` - Enforcement mechanisms (for our side)

### External References
- [Kubernetes Pod Security Standards](https://kubernetes.io/docs/concepts/security/pod-security-standards/)
- [Linux Capabilities](https://man7.org/linux/man-pages/man7/capabilities.7.html)
- [eBPF Documentation](https://ebpf.io/)
- [Falco](https://falco.org/) - Industry example of eBPF-based security

## Project Goals

✅ **Demonstrate** rootless monitoring is possible  
✅ **Educate** vendors on Pod Security Standards  
✅ **Provide** reference implementation  
✅ **Enable** telco security compliance  

**NOT** a production monitoring solution - this is a proof-of-concept to show vendors what's possible.
