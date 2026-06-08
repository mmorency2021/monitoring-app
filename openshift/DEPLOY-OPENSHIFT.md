# OpenShift Deployment Guide - Rootless Monitor

## Why You Need a Custom SCC

OpenShift's default Security Context Constraints (SCCs) **cannot** run this monitoring agent:

| SCC | Why It Fails |
|-----|-------------|
| **restricted-v2** | ❌ Forbids hostPath volumes (need /proc, /sys)<br>❌ Requires UID > 1000000000 (we use 1000) |
| **anyuid** | ❌ Forbids hostPath volumes |
| **hostaccess** | ❌ Requires UID > 1000000000 |
| **privileged** | ✅ Would work but grants **root + full privileges** (defeats the purpose!) |

**Solution**: Custom SCC that allows:
- ✅ hostPath volumes (read-only /proc and /sys)
- ✅ UID 1000 (non-root but low UID)
- ✅ Minimal capabilities (only what monitoring needs)
- ❌ No root, no privilege escalation

---

## Deployment Steps

### 1. Create the Custom SCC

```bash
# As cluster-admin
oc apply -f openshift/scc-rootless-monitor.yaml
```

**Verify SCC was created:**
```bash
oc get scc rootless-monitor-scc
```

Expected output:
```
NAME                    PRIV    CAPS                                      SELINUX     RUNASUSER          FSGROUP     SUPGROUP   PRIORITY   READONLYROOTFS   VOLUMES
rootless-monitor-scc    false   [SYS_PTRACE NET_RAW BPF PERFMON]          MustRunAs   MustRunAsRange     MustRunAs   RunAsAny   5          true             [configMap downwardAPI emptyDir hostPath ...]
```

### 2. Create Namespace and ServiceAccount

```bash
# Create namespace with monitoring labels
oc apply -f kubernetes/namespace.yaml

# Create service account
oc apply -f kubernetes/serviceaccount.yaml
```

### 3. Grant SCC to ServiceAccount

```bash
# This allows the rootless-monitor service account to use the custom SCC
oc adm policy add-scc-to-user rootless-monitor-scc \
  -z rootless-monitor \
  -n rootless-monitor
```

**Verify the binding:**
```bash
oc get scc rootless-monitor-scc -o yaml | grep -A 5 "users:"
```

Expected output should include:
```yaml
users:
- system:serviceaccount:rootless-monitor:rootless-monitor
```

### 4. Create ConfigMap

```bash
oc apply -f kubernetes/configmap.yaml
```

### 5. Deploy DaemonSet

Choose one variant based on your needs:

**Option A: Minimal (No Capabilities - Recommended for PoC)**
```bash
oc apply -f kubernetes/daemonset-minimal.yaml
```

**Option B: Enhanced (CAP_SYS_PTRACE + CAP_NET_RAW)**
```bash
oc apply -f kubernetes/daemonset-enhanced.yaml
```

**Option C: eBPF (CAP_BPF + CAP_PERFMON - Requires Linux 5.8+)**
```bash
oc apply -f kubernetes/daemonset-ebpf.yaml
```

### 6. Verify Deployment

```bash
# Check pods are running
oc get pods -n rootless-monitor

# Expected output:
# NAME                             READY   STATUS    RESTARTS   AGE
# rootless-monitor-minimal-xxxxx   1/1     Running   0          30s
# rootless-monitor-minimal-yyyyy   1/1     Running   0          30s
# rootless-monitor-minimal-zzzzz   1/1     Running   0          30s
```

**Verify security context:**
```bash
# Check which SCC is being used
oc get pod -n rootless-monitor -l app=rootless-monitor \
  -o jsonpath='{.items[0].metadata.annotations.openshift\.io/scc}'

# Expected: rootless-monitor-scc
```

**Verify running as non-root:**
```bash
oc exec -n rootless-monitor -l app=rootless-monitor -- id

# Expected:
# uid=1000(monitor) gid=1000(monitor) groups=1000(monitor)
```

**Check logs:**
```bash
oc logs -n rootless-monitor -l app=rootless-monitor --tail=20
```

---

## Troubleshooting

### Error: "unable to validate against any security context constraint"

**Symptom:**
```
Error creating: pods "rootless-monitor-minimal-" is forbidden: 
unable to validate against any security context constraint
```

**Cause**: ServiceAccount not authorized to use the SCC

**Fix:**
```bash
# Re-run the SCC binding
oc adm policy add-scc-to-user rootless-monitor-scc \
  -z rootless-monitor \
  -n rootless-monitor

# Verify it was added
oc describe scc rootless-monitor-scc | grep Users -A 5
```

---

### Error: "1000 is not an allowed group"

**Symptom:**
```
.spec.securityContext.fsGroup: Invalid value: [1000]: 1000 is not an allowed group
```

**Cause**: SCC doesn't have the right fsGroup range

**Fix:**
```bash
# Check current SCC fsGroup settings
oc get scc rootless-monitor-scc -o yaml | grep -A 3 fsGroup

# Should show:
#   fsGroup:
#     type: MustRunAs
#     ranges:
#       - min: 1000
#         max: 1000
```

If not, reapply the SCC:
```bash
oc apply -f openshift/scc-rootless-monitor.yaml
```

---

### Error: "must be in the ranges: [1000910000, 1000919999]"

**Symptom:**
```
.containers[0].runAsUser: Invalid value: 1000: must be in the ranges: [1000910000, 1000919999]
```

**Cause**: Pod is using a different SCC (like `restricted-v2`) instead of your custom one

**Fix:**
```bash
# Check which SCC is being used
oc describe pod -n rootless-monitor <pod-name> | grep scc

# If it shows wrong SCC, check binding:
oc get scc rootless-monitor-scc -o yaml | grep users -A 5

# Re-apply binding
oc adm policy add-scc-to-user rootless-monitor-scc \
  -z rootless-monitor \
  -n rootless-monitor

# Delete and recreate pods
oc delete pods -n rootless-monitor --all
```

---

### Error: "hostPath volumes are not allowed to be used"

**Symptom:**
```
spec.volumes[0]: Invalid value: "hostPath": hostPath volumes are not allowed to be used
```

**Cause**: Using an SCC that doesn't allow hostPath (like `restricted-v2`)

**Fix**: Ensure custom SCC has:
```yaml
allowHostDirVolumePlugin: true
allowedHostPaths:
  - pathPrefix: "/proc"
    readOnly: true
  - pathPrefix: "/sys"
    readOnly: true
```

Reapply SCC if needed:
```bash
oc apply -f openshift/scc-rootless-monitor.yaml
```

---

### Pods Not Starting - Check Events

```bash
# See what's preventing pod creation
oc get events -n rootless-monitor --sort-by='.lastTimestamp' | tail -20

# Describe the DaemonSet
oc describe ds -n rootless-monitor rootless-monitor-minimal

# Describe a pod (if created)
oc describe pod -n rootless-monitor <pod-name>
```

---

### Image Pull Issues

**Public image (recommended):**
```bash
# Should work with no auth
oc run test-pull \
  --image=ghcr.io/mmorency2021/monitoring-app:latest \
  --restart=Never \
  -n rootless-monitor

# Check if it pulled
oc get pod test-pull -n rootless-monitor

# Clean up
oc delete pod test-pull -n rootless-monitor
```

**Private image:**
See [PACKAGE-MANAGEMENT.md](../PACKAGE-MANAGEMENT.md) for setting up imagePullSecrets.

---

## Testing Monitoring Functionality

### Test Process Monitoring

```bash
# Check if processes are visible
oc exec -n rootless-monitor -l app=rootless-monitor -- \
  ls /host/proc | head -20

# Should show process IDs like: 1, 2, 3, 4, ...
```

### Test System Monitoring

```bash
# Check system info is readable
oc exec -n rootless-monitor -l app=rootless-monitor -- \
  cat /host/sys/class/net/eth0/operstate

# Should show: up or down
```

### Test Metrics Collection

```bash
# View metrics file
oc exec -n rootless-monitor -l app=rootless-monitor -- \
  cat /tmp/metrics.json | jq .

# View logs
oc logs -n rootless-monitor -l app=rootless-monitor -f
```

### Compare Root vs Non-Root Access

```bash
# Test as non-root (UID 1000)
oc exec -n rootless-monitor -l app=rootless-monitor -- \
  ls /host/proc/1/cmdline

# Test via oc debug (runs as root for comparison)
oc debug node/<node-name> -- chroot /host ls /proc/1/cmdline

# Both should work! Proving non-root can monitor
```

---

## Cleanup

### Remove Everything

```bash
# Delete DaemonSet
oc delete -f kubernetes/daemonset-minimal.yaml

# Delete ConfigMap and ServiceAccount
oc delete -f kubernetes/configmap.yaml
oc delete -f kubernetes/serviceaccount.yaml

# Delete namespace
oc delete -f kubernetes/namespace.yaml

# Remove SCC binding
oc adm policy remove-scc-from-user rootless-monitor-scc \
  -z rootless-monitor \
  -n rootless-monitor

# Delete SCC (cluster-admin only)
oc delete scc rootless-monitor-scc
```

---

## Security Review Checklist

Before deploying to production, verify:

- [ ] SCC has `allowPrivilegedContainer: false`
- [ ] SCC has `allowPrivilegeEscalation: false`
- [ ] SCC enforces `runAsUser: MustRunAsRange` with `uidRangeMin: 1000`
- [ ] SCC restricts hostPath to `/proc` and `/sys` only (read-only)
- [ ] SCC has `readOnlyRootFilesystem: true`
- [ ] ServiceAccount has minimal RBAC (read-only K8s API)
- [ ] Only necessary capabilities are granted (see variant docs)
- [ ] DaemonSet has resource limits defined
- [ ] Logs are being collected and monitored

---

## Next Steps

After successful deployment:

1. **Test monitoring functionality** - See [OPENSHIFT-TESTING.md](OPENSHIFT-TESTING.md)
2. **Review collected metrics** - Check `/tmp/metrics.json`
3. **Adjust configuration** - Edit ConfigMap and restart pods
4. **Share with vendor** - Use this as proof that rootless monitoring works
5. **Document actual requirements** - What capabilities were actually needed?

---

## Key Differences from Kubernetes

| Aspect | Kubernetes | OpenShift |
|--------|-----------|-----------|
| **Default policy** | None (permissive) | SCCs (restrictive) |
| **UID ranges** | Any | Namespace-specific (1000000000+) |
| **Custom UID** | Easy | Requires custom SCC |
| **hostPath** | Allowed by default | Forbidden by default SCCs |
| **RBAC binding** | `kubectl` | `oc adm policy` |

**Bottom line**: OpenShift is more secure by default, but requires explicit SCC for monitoring use cases.

---

## References

- [OpenShift SCC Documentation](https://docs.openshift.com/container-platform/latest/authentication/managing-security-context-constraints.html)
- [SCC Comparison](https://docs.openshift.com/container-platform/latest/authentication/managing-security-context-constraints.html#security-context-constraints-about_configuring-internal-oauth)
- [Managing SCCs](https://docs.openshift.com/container-platform/latest/authentication/managing-security-context-constraints.html#examining-a-security-context-constraints-object_configuring-internal-oauth)
