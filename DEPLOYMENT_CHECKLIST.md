# Phylaxor Deployment Checklist

## Pre-Deployment (Local Machine)

- [x] Updated `log_provider.py` in enricher service with three implementations (none, loki, podlogs)
- [x] Updated `worker.py` to use LogProvider factory pattern
- [x] Updated `Dockerfile` to copy `log_provider.py`
- [x] Updated `docker-compose.yml` with all PHYLAXOR_LOGS_* environment variables
- [x] Updated `values-minikube.yaml` with logging configuration
- [x] Updated `values-openshift.yaml` with logging configuration
- [x] Updated `deploy-enricher.yaml` to map all logging environment variables
- [x] Updated `role.yaml` with pods/log conditional rules
- [x] Updated `clusterrole.yaml` (removed duplicate permissions, kept cluster-scoped only)
- [x] Updated `clusterrolebinding.yaml` 
- [x] Tested Docker image locally - all tests passed ✅
- [x] Created `deploy_and_test.sh` deployment script
- [x] Created `quick_rbac_test.sh` permission test script
- [x] Created `LOGGING_MODES_GUIDE.md` documentation
- [ ] Push code changes to git

**Before running on remote server:**
```bash
cd ~/github/phylaxor-gitops
git add -A
git commit -m "feat: implement logs.mode feature with three logging modes (none/loki/podlogs) and conditional RBAC"
git push
```

---

## On Remote Server (pc-casa)

### 1. SSH Connection & Login
```bash
# Open terminal and SSH to your server
ssh pc-casa

# Inside server, login to OpenShift
oc login -u kubeadmin -p tNRvC-qD8rk-hnRtS-hNMrZ https://api.crc.testing:6443 --insecure-skip-tls-verify=true
```

### 2. Pull Latest Code
```bash
cd ~/github/phylaxor-gitops
git pull
```

### 3. Deploy with Full Validation
```bash
# This script will:
# - Verify prerequisites
# - Create namespace
# - Deploy Helm chart
# - Verify RBAC resources
# - Test all permissions
bash deploy_and_test.sh
```

**Expected output:**
```
✅ Helm chart deployed successfully
✅ All RBAC resources verified
✅ All permissions working correctly
```

### 4. Quick Permission Test (Anytime)
```bash
bash quick_rbac_test.sh
```

---

## Verification Matrix

### Logging Mode: "none" (Default)

| Permission | Should Have | Command |
|-----------|-------------|---------|
| get pods | ✅ Yes | `oc -n phylaxor auth can-i get pods --as=system:serviceaccount:phylaxor:phylaxor-sa` |
| list events | ✅ Yes | `oc -n phylaxor auth can-i list events --as=system:serviceaccount:phylaxor:phylaxor-sa` |
| get pods/log | ❌ No | `oc -n phylaxor auth can-i get pods/log --as=system:serviceaccount:phylaxor:phylaxor-sa` |
| get nodes | ✅ Yes | `oc -n phylaxor auth can-i get nodes --as=system:serviceaccount:phylaxor:phylaxor-sa` |

### Logging Mode: "loki"

Same as "none" - pods/log permission NOT granted (logs from external Loki system, not K8s API)

### Logging Mode: "podlogs"

| Permission | Should Have | Command |
|-----------|-------------|---------|
| get pods | ✅ Yes | `oc -n phylaxor auth can-i get pods --as=system:serviceaccount:phylaxor:phylaxor-sa` |
| list events | ✅ Yes | `oc -n phylaxor auth can-i list events --as=system:serviceaccount:phylaxor:phylaxor-sa` |
| get pods/log | ✅ **Yes** | `oc -n phylaxor auth can-i get pods/log --as=system:serviceaccount:phylaxor:phylaxor-sa` |
| get nodes | ✅ Yes | `oc -n phylaxor auth can-i get nodes --as=system:serviceaccount:phylaxor:phylaxor-sa` |

---

## How to Test Different Logging Modes

### Test Mode: none
```bash
helm upgrade phylaxor ./apps/phylaxor -f apps/phylaxor/values-openshift.yaml -n phylaxor --set logging.mode=none
sleep 10
bash quick_rbac_test.sh
# Expected: pods/log = NO
```

### Test Mode: loki
```bash
helm upgrade phylaxor ./apps/phylaxor -f apps/phylaxor/values-openshift.yaml -n phylaxor --set logging.mode=loki
sleep 10
bash quick_rbac_test.sh
# Expected: pods/log = NO (logs come from external Loki, not K8s)
```

### Test Mode: podlogs
```bash
helm upgrade phylaxor ./apps/phylaxor -f apps/phylaxor/values-openshift.yaml -n phylaxor --set logging.mode=podlogs
sleep 10
bash quick_rbac_test.sh
# Expected: pods/log = YES (explicit permission granted)
```

---

## Monitoring & Troubleshooting

### Check Enricher Status
```bash
oc -n phylaxor get pods -l app=enricher
oc -n phylaxor describe pod -l app=enricher
oc -n phylaxor logs -f deployment/enricher
```

### Check RBAC Resources
```bash
# Namespace-scoped
oc -n phylaxor get role,rolebinding

# Cluster-scoped
oc get clusterrole,clusterrolebinding | grep phylaxor

# Details
oc -n phylaxor describe role phylaxor-role
oc describe clusterrole phylaxor-read-cluster
```

### If Permissions Are Missing

**Step 1: Verify Helm deployment**
```bash
helm status phylaxor -n phylaxor
helm get values phylaxor -n phylaxor
```

**Step 2: Check what's actually deployed**
```bash
oc -n phylaxor get all
```

**Step 3: Force redeploy**
```bash
helm upgrade phylaxor ./apps/phylaxor -f apps/phylaxor/values-openshift.yaml -n phylaxor --force
```

**Step 4: Verify again**
```bash
bash quick_rbac_test.sh
```

---

## Key Files Modified

### Application Code (phylaxor-project)
- `services/enricher/log_provider.py` - LogProvider ABC + 3 implementations
- `services/enricher/worker.py` - Integration of log_provider factory
- `services/enricher/Dockerfile` - Added COPY for log_provider.py
- `services/enricher/test_log_provider.py` - 15 unit tests
- `docker-compose.yml` - Added logging environment variables

### Infrastructure (phylaxor-gitops)
- `apps/phylaxor/values-minikube.yaml` - Added logging section
- `apps/phylaxor/values-openshift.yaml` - Added logging section
- `apps/phylaxor/templates/deployments/deploy-enricher.yaml` - Mapped env vars
- `apps/phylaxor/templates/security/role.yaml` - Added pods/log conditional
- `apps/phylaxor/templates/security/enricher-rbac/clusterrole.yaml` - Cleaned up
- `apps/phylaxor/templates/security/enricher-rbac/clusterrolebinding.yaml` - Kept simple

### Documentation
- `LOGGING_MODES_GUIDE.md` - Complete three-mode reference
- `deploy_and_test.sh` - Full deployment + validation
- `quick_rbac_test.sh` - Quick permission check

---

## Support Commands Reference

```bash
# General
oc cluster-info
oc config current-context
oc whoami

# Namespace operations
oc get ns
oc get all -n phylaxor
oc describe ns phylaxor

# RBAC testing
oc -n phylaxor auth can-i list pods --as=system:serviceaccount:phylaxor:phylaxor-sa
oc -n phylaxor auth can-i-list  # Show all permissions for SA

# Pod inspection
oc -n phylaxor get pods
oc -n phylaxor describe pod <pod-name>
oc -n phylaxor logs <pod-name>
oc -n phylaxor logs -f deployment/enricher

# Helm operations
helm list -n phylaxor
helm status phylaxor -n phylaxor
helm get values phylaxor -n phylaxor
helm history phylaxor -n phylaxor

# Rollback if needed
helm rollback phylaxor 0 -n phylaxor
```

---

## Next Steps After Deployment

1. **Monitor enricher logs** for any startup errors
2. **Run quick_rbac_test.sh** to verify all permissions
3. **Test each logging mode** with the test commands above
4. **Check Pod status** to ensure it's running without errors
5. **Validate application behavior** with real enrichment jobs

---

## Success Criteria

✅ All checks passed when you see:
- Helm chart deployed
- All RBAC resources created
- All permission tests passed
- Enricher pod running
- No errors in pod logs

You can now:
- Access pod information in enricher
- Read events in phylaxor namespace
- Control pod logs access via logging.mode setting
- Switch between three logging modes without changing RBAC structure
