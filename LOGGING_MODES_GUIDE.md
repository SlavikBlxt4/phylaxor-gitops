# Phylaxor Logging Modes - Complete Guide

## Overview

The phylaxor enricher supports three logging modes, each with different RBAC permissions and capabilities:

| Mode | Description | RBAC | Use Case |
oc -n phylaxor auth can-i get pods --as=system:serviceaccount:phylaxor:phylaxor-enricher-sa
| `none` | No pod logs fetched | Minimal - no pods/log access | Default, lightweight, privacy-focused |
| `loki` | Logs sent to external Loki/ELK | Minimal - no pods/log access | Centralized logging, external system stores logs |
| `podlogs` | Direct K8s API pod log access | Explicit - pods/log permission required | Full context, requires cluster permissions |
oc -n phylaxor auth can-i get pods/log --as=system:serviceaccount:phylaxor:phylaxor-enricher-sa
---

## RBAC Structure
oc -n phylaxor auth can-i list events --as=system:serviceaccount:phylaxor:phylaxor-enricher-sa
### Namespace-Scoped (Role + RoleBinding)

Located in: `templates/security/role.yaml` and `templates/security/rolebinding.yaml`
oc -n phylaxor auth can-i get nodes --as=system:serviceaccount:phylaxor:phylaxor-enricher-sa
**Always granted:**
- `pods`: get, list, watch
- `events`: get, list, watch

**Conditional (only if logging.mode = "podlogs"):**
- `pods/log`: get

### Cluster-Scoped (ClusterRole + ClusterRoleBinding)
oc -n phylaxor get sa phylaxor-enricher-sa
# Should show: phylaxor-enricher-sa with image pull secrets configured

**Always granted:**
- `nodes`: get, list, watch
- `namespaces`: get, list, watch
oc -n phylaxor get role phylaxor-enricher-role -o yaml
# Should show: pods, events permissions always
#             pods/log permission only if logging.mode=podlogs

## Deployment Steps

### 1. Pull Latest Changes
oc -n phylaxor get rolebinding phylaxor-enricher-rb -o yaml
# Should show: phylaxor-enricher-sa bound to phylaxor-enricher-role
cd ~/github/phylaxor-gitops
git pull
```

oc get clusterrole phylaxor-read-cluster -o yaml
# Should show: nodes, namespaces, storageclasses permissions
```bash
oc login -u kubeadmin -p tNRvC-qD8rk-hnRtS-hNMrZ https://api.crc.testing:6443 --insecure-skip-tls-verify=true
```

oc get clusterrolebinding phylaxor-read-cluster-binding -o yaml
# Should show: phylaxor-enricher-sa bound to phylaxor-read-cluster
```bash
# Full deployment with validation
bash /path/to/deploy_and_test.sh
```
oc -n phylaxor describe pod -l app=enricher | grep "Service Account"
# Should show: phylaxor-enricher-sa

```bash
helm upgrade --install phylaxor ./apps/phylaxor \
  -f apps/phylaxor/values-openshift.yaml \
helm upgrade phylaxor ./apps/phylaxor -f apps/phylaxor/values-openshift.yaml -n phylaxor --force
  --create-namespace
```

---

## Testing Permissions

### Quick Test (after deployment)

```bash
bash quick_rbac_test.sh
```

### Manual Permission Tests

Test if enricher can read pods:
```bash
oc -n phylaxor auth can-i get pods --as=system:serviceaccount:phylaxor:phylaxor-enricher-sa
# Output: yes (for all modes)
```

Test if enricher can read pod logs:
```bash
oc -n phylaxor auth can-i get pods/log --as=system:serviceaccount:phylaxor:phylaxor-enricher-sa
# Output: yes (only for logging.mode=podlogs)
# Output: no (for logging.mode=none or loki)
```

Test if enricher can read events:
```bash
oc -n phylaxor auth can-i list events --as=system:serviceaccount:phylaxor:phylaxor-enricher-sa
# Output: yes (for all modes)
```

Test if enricher can read nodes:
```bash
oc -n phylaxor auth can-i get nodes --as=system:serviceaccount:phylaxor:phylaxor-enricher-sa
# Output: yes (for all modes - cluster-scoped)
```

---

## Testing Each Logging Mode

### Mode 1: "none" (Default - No Pod Logs)

```bash
helm upgrade phylaxor ./apps/phylaxor \
  -f apps/phylaxor/values-openshift.yaml \
  -n phylaxor \
  --set logging.mode=none

# Expected: No pods/log permission
oc -n phylaxor auth can-i get pods/log --as=system:serviceaccount:phylaxor:phylaxor-enricher-sa
# Output: no
```

**What enricher can do:**
- ✅ Read pod metadata (name, phase, status, etc.)
- ✅ Read events in the namespace
- ✅ Read node information (cluster topology)
- ❌ Access pod logs directly

**What enricher cannot do:**
- Cannot fetch logs from running pods

---

### Mode 2: "loki" (Centralized Logging)

```bash
helm upgrade phylaxor ./apps/phylaxor \
  -f apps/phylaxor/values-openshift.yaml \
  -n phylaxor \
  --set logging.mode=loki

# Expected: No pods/log permission (logs from Loki, not K8s API)
oc -n phylaxor auth can-i get pods/log --as=system:serviceaccount:phylaxor:phylaxor-enricher-sa
# Output: no
```

**What enricher can do:**
- ✅ Read pod metadata
- ✅ Read events in the namespace
- ✅ Query Loki API for logs (when Loki is configured)
- ❌ Access pod logs via K8s API

**Configuration needed:**
- Loki endpoint must be configured in environment variables
- LokiLogProvider will fetch logs from Loki, not K8s

---

### Mode 3: "podlogs" (Full Access via K8s API)

```bash
helm upgrade phylaxor ./apps/phylaxor \
  -f apps/phylaxor/values-openshift.yaml \
  -n phylaxor \
  --set logging.mode=podlogs

# Expected: pods/log permission GRANTED
oc -n phylaxor auth can-i get pods/log --as=system:serviceaccount:phylaxor:phylaxor-enricher-sa
# Output: yes
```

**What enricher can do:**
- ✅ Read pod metadata
- ✅ Read events in the namespace
- ✅ Access pod logs directly via Kubernetes API
- ✅ Full observability of pod runtime behavior

**What enricher cannot do:**
- Cannot access secrets or other privileged resources
- Still limited to phylaxor namespace for pod logs

---

## Verification Checklist

After deployment, verify:

### ServiceAccount Setup
```bash
oc -n phylaxor get sa phylaxor-enricher-sa
# Should show: phylaxor-enricher-sa with image pull secrets configured
```

### Role Configuration
```bash
oc -n phylaxor get role phylaxor-enricher-role -o yaml
# Should show: pods, events permissions always
#             pods/log permission only if logging.mode=podlogs
```

### RoleBinding Setup
```bash
oc -n phylaxor get rolebinding phylaxor-enricher-rb -o yaml
# Should show: phylaxor-enricher-sa bound to phylaxor-enricher-role
```

### ClusterRole Configuration
```bash
oc get clusterrole phylaxor-read-cluster -o yaml
# Should show: nodes, namespaces, storageclasses permissions
```

### ClusterRoleBinding Setup
```bash
oc get clusterrolebinding phylaxor-read-cluster-binding -o yaml
# Should show: phylaxor-enricher-sa bound to phylaxor-read-cluster
```

### Enricher Pod Status
```bash
oc -n phylaxor get pods -l app=enricher
oc -n phylaxor describe pod -l app=enricher
oc -n phylaxor logs -f deployment/enricher
```

---

## Troubleshooting

### Problem: Enricher cannot read pods/events

**Check 1: Is the Role deployed?**
```bash
oc -n phylaxor get role phylaxor-role
```

**Check 2: Is the RoleBinding correct?**
```bash
oc -n phylaxor get rolebinding phylaxor-rb -o yaml
```

**Check 3: Does the pod use the correct SA?**
```bash
oc -n phylaxor describe pod -l app=enricher | grep "Service Account"
# Should show: phylaxor-enricher-sa
```

**Fix: Redeploy the chart**
```bash
helm upgrade phylaxor ./apps/phylaxor -f apps/phylaxor/values-openshift.yaml -n phylaxor --force
```

### Problem: Enricher cannot read pods/log even with mode=podlogs

**Check 1: Is the logging.mode set correctly?**
```bash
oc -n phylaxor get deployment enricher -o yaml | grep PHYLAXOR_LOGS_MODE
# Should show: value: "podlogs"
```

**Check 2: Are pods/log rules in the ClusterRole?**
```bash
oc get clusterrole phylaxor-read-cluster -o yaml | grep pods/log
# Should show the pods/log resource
```

**Fix: Verify the values file and redeploy**
```bash
helm upgrade phylaxor ./apps/phylaxor \
  -f apps/phylaxor/values-openshift.yaml \
  -n phylaxor \
  --set logging.mode=podlogs \
  --force
```

---

## Environment Variables Reference

These variables control logging behavior:

```yaml
PHYLAXOR_LOGS_MODE: "none"           # none | loki | podlogs
PHYLAXOR_EVENTS_ENABLED: "true"      # Enable/disable event reading
PHYLAXOR_LOGS_MAX_LINES: "500"       # Max lines to fetch per pod
PHYLAXOR_LOGS_MAX_BYTES: "100000"    # Max bytes per log retrieval
PHYLAXOR_LOGS_LOOKBACK: "300"        # Seconds back to look for logs
PHYLAXOR_LOGS_TIMEOUT: "5"           # Timeout for K8s API calls (seconds)
```

See `values-minikube.yaml` and `values-openshift.yaml` for configuration.

---

## Security Best Practices

1. **Default to "none" mode** - No unnecessary API permissions
2. **Use "loki" for production** - Offload logs to external system
3. **Use "podlogs" only when needed** - Requires explicit opt-in via RBAC
4. **Monitor RBAC changes** - Audit who can modify permissions
5. **Use namespaced roles** - Pods/events access is namespace-scoped
6. **Cluster resources read-only** - Nodes/storageclasses are get/list only

---

## Code References

- **Application code:** `phylaxor-project/services/enricher/log_provider.py`
- **RBAC templates:** `phylaxor-gitops/apps/phylaxor/templates/security/`
- **Helm values:** `phylaxor-gitops/apps/phylaxor/values-*.yaml`
- **Deployment template:** `phylaxor-gitops/apps/phylaxor/templates/deployments/deploy-enricher.yaml`

---

## Support

For issues or questions, check:
1. `deploy_and_test.sh` - Full deployment validation
2. `quick_rbac_test.sh` - Quick permission check
3. Logs: `oc -n phylaxor logs -f deployment/enricher`
4. Events: `oc -n phylaxor get events`
