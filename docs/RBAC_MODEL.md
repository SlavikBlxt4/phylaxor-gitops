# RBAC Model — Phylaxor (GitOps)

This document explains how to implement RBAC for Phylaxor in Helm, with conditional permissions based on logging modes and component function.

## RBAC Architecture

```
ClusterRole (cluster-wide)
    ↓
ClusterRoleBinding (links to ServiceAccount)
    ↓
ServiceAccount (per microservice)
    ↓
Pod (runs with SA token, inherits permissions)
```

**Key principle**: Each component gets its own ServiceAccount. Permissions are **conditional** based on Helm values.

## ServiceAccounts Required

Create one ServiceAccount per component that needs Kubernetes access:

| Component | ServiceAccount | Namespace | RBAC Needed |
|-----------|---|-----------|-------------|
| ingest | phylaxor-ingest | phylaxor | None |
| enricher | phylaxor-enricher | phylaxor | Yes (observer + conditional logs) |
| decision | phylaxor-decision | phylaxor | None |
| notifier | phylaxor-notifier | phylaxor | **None (critical!)** |
| feedback-gateway | phylaxor-feedback | phylaxor | None |
| feedback UI | phylaxor-feedback-ui | phylaxor | None |

**Important**: Notifier must NOT have any Kubernetes RBAC permissions.

## ClusterRoles and ClusterRoleBindings

### 1. Baseline Observer Role (For Enricher)

```yaml
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: phylaxor-observer
rules:
  # Read pod info (status, labels, namespace)
  - apiGroups: [""]
    resources: ["pods"]
    verbs: ["get", "list"]
  # Read node info (capacity, conditions)
  - apiGroups: [""]
    resources: ["nodes"]
    verbs: ["get", "list"]
  # Read cluster events
  - apiGroups: [""]
    resources: ["events"]
    verbs: ["get", "list"]
  # Read namespace info
  - apiGroups: [""]
    resources: ["namespaces"]
    verbs: ["get", "list"]
  # Read storage class info
  - apiGroups: ["storage.k8s.io"]
    resources: ["storageclasses"]
    verbs: ["get", "list"]
```

**Scope**: Cluster-wide (needed to observe all namespaces, nodes, storage).

### 2. Conditional Pod Logs Role (For Enricher, if podlogs mode)

```yaml
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: phylaxor-log-reader
rules:
  # Read pod logs (pods/log subresource)
  - apiGroups: [""]
    resources: ["pods/log"]
    verbs: ["get"]
```

**Scope**: Cluster-wide (but only used if `PHYLAXOR_LOGS_MODE=podlogs`).

### 3. ClusterRoleBindings

```yaml
---
# Bind baseline observer role to enricher
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: phylaxor-observer
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: phylaxor-observer
subjects:
  - kind: ServiceAccount
    name: phylaxor-enricher
    namespace: phylaxor

---
# Conditionally bind pod logs role (only if mode=podlogs)
{{- if eq .Values.logging.mode "podlogs" }}
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: phylaxor-log-reader
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: phylaxor-log-reader
subjects:
  - kind: ServiceAccount
    name: phylaxor-enricher
    namespace: phylaxor
{{- end }}
```

**Why conditional?** Only grant `pods/log` if explicitly enabled via `logging.mode=podlogs`.

## Helm Template Structure

### ServiceAccount Template

```yaml
# templates/serviceaccount.yaml
apiVersion: v1
kind: ServiceAccount
metadata:
  name: phylaxor-enricher
  namespace: {{ .Release.Namespace }}
  labels:
    app: phylaxor
    component: enricher
---
apiVersion: v1
kind: ServiceAccount
metadata:
  name: phylaxor-notifier
  namespace: {{ .Release.Namespace }}
  labels:
    app: phylaxor
    component: notifier
# ... repeat for other components that need RBAC
```

### RBAC Template

```yaml
# templates/rbac.yaml
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: phylaxor-observer
  labels:
    app: phylaxor
rules:
  - apiGroups: [""]
    resources: ["pods"]
    verbs: ["get", "list"]
  - apiGroups: [""]
    resources: ["nodes"]
    verbs: ["get", "list"]
  - apiGroups: [""]
    resources: ["events"]
    verbs: ["get", "list"]
  - apiGroups: [""]
    resources: ["namespaces"]
    verbs: ["get", "list"]
  - apiGroups: ["storage.k8s.io"]
    resources: ["storageclasses"]
    verbs: ["get", "list"]

---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: phylaxor-observer
  labels:
    app: phylaxor
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: phylaxor-observer
subjects:
  - kind: ServiceAccount
    name: phylaxor-enricher
    namespace: {{ .Release.Namespace }}

---
# Conditional pod logs role (only if podlogs mode)
{{- if eq .Values.logging.mode "podlogs" }}
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: phylaxor-log-reader
  labels:
    app: phylaxor
rules:
  - apiGroups: [""]
    resources: ["pods/log"]
    verbs: ["get"]

---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: phylaxor-log-reader
  labels:
    app: phylaxor
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: phylaxor-log-reader
subjects:
  - kind: ServiceAccount
    name: phylaxor-enricher
    namespace: {{ .Release.Namespace }}
{{- end }}
```

## Per-Namespace RBAC (Optional, for Multi-Namespace)

If Phylaxor is deployed in multiple namespaces, use Role + RoleBinding instead:

```yaml
# templates/role.yaml (namespace-scoped)
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  name: phylaxor-observer
  namespace: {{ .Release.Namespace }}
rules:
  - apiGroups: [""]
    resources: ["pods", "events"]
    verbs: ["get", "list"]

---
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  name: phylaxor-observer
  namespace: {{ .Release.Namespace }}
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: Role
  name: phylaxor-observer
subjects:
  - kind: ServiceAccount
    name: phylaxor-enricher
    namespace: {{ .Release.Namespace }}
```

**Note**: Nodes and namespaces are cluster-wide, so use ClusterRole for those.

## Values Configuration

```yaml
# values-minikube.yaml
logging:
  mode: none  # Safe default for dev

rbac:
  create: true  # Create RBAC resources

---
# values-openshift.yaml
logging:
  mode: none  # Safe default for CRC; strict RBAC enforcement

rbac:
  create: true  # Create RBAC resources
```

## Deployment Integration

When deploying enricher, reference the ServiceAccount:

```yaml
# templates/deployments/deploy-enricher.yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: phylaxor-enricher
spec:
  template:
    spec:
      serviceAccountName: phylaxor-enricher  # Use the SA
      containers:
        - name: enricher
          image: phylaxor-enricher:latest
          env:
            - name: PHYLAXOR_LOGS_MODE
              value: {{ .Values.logging.mode }}
```

## Testing RBAC

### Test 1: Verify Observer Permissions (Minikube)

```bash
# Deploy enricher
kubectl create -f deploy.yaml

# Check SA has observer role
kubectl get rolebinding,clusterrolebinding | grep phylaxor

# Verify enricher can read pods
kubectl logs -n phylaxor phylaxor-enricher-xyz | grep "pods retrieved"

# Verify enricher cannot read secrets
kubectl logs -n phylaxor phylaxor-enricher-xyz | grep -i "secret" | grep -i "denied"
```

### Test 2: Verify pods/log Denied (CRC, mode=none)

```bash
# Deploy with mode=none (no pods/log binding)
helm install phylaxor ./apps/phylaxor -f values-openshift.yaml

# Send alert
curl -X POST http://ingest-svc:5000/webhook ...

# Verify: Enricher logs show NO 403 errors (pods/log not attempted)
kubectl logs -n phylaxor phylaxor-enricher-xyz | grep "pods/log"
# (should have no output)
```

### Test 3: Verify pods/log Granted (CRC, mode=podlogs)

```bash
# Deploy with mode=podlogs (pods/log binding created)
helm install phylaxor ./apps/phylaxor -f values-openshift.yaml \
  --set logging.mode=podlogs

# Verify RBAC binding
kubectl get clusterrolebinding phylaxor-log-reader

# Send alert
curl -X POST http://ingest-svc:5000/webhook ...

# Verify: Enricher successfully fetches logs
kubectl logs -n phylaxor phylaxor-enricher-xyz | grep "log lines fetched"
```

### Test 4: Verify pods/log 403 Handling (CRC, mode=podlogs, no RBAC)

```bash
# Deploy with mode=podlogs but do NOT grant pods/log permission
# (Simulate by deleting the binding)
helm install phylaxor ./apps/phylaxor -f values-openshift.yaml \
  --set logging.mode=podlogs
kubectl delete clusterrolebinding phylaxor-log-reader

# Send alert
curl -X POST http://ingest-svc:5000/webhook ...

# Verify: Enricher logs WARN (not ERROR)
kubectl logs -n phylaxor phylaxor-enricher-xyz | grep -i "pods/log" | grep -i "warn"
# Output should contain: "WARN: pods/log denied for pod..."

# Verify: Pipeline continues (event in Redis)
kubectl exec -n phylaxor redis-pod -- redis-cli LLEN phylaxor_enriched
# Should have entries
```

## Audit Logging (OpenShift)

In production OpenShift, enable audit logging to track RBAC violations:

```yaml
# audit-policy.yaml
rules:
  - level: RequestResponse
    verbs: ["get"]
    resources: ["pods/log"]
    namespaces: ["phylaxor"]
    omitStages: ["RequestReceived"]
```

Then check audit logs for 403 denials:
```bash
oc get events -n phylaxor -o wide | grep Forbidden
```

## Security Checklist

Before deploying:

- [ ] Notifier has ZERO Kubernetes RBAC rules (no ClusterRoleBinding)
- [ ] `pods/log` only bound if `logging.mode=podlogs`
- [ ] No wildcards in RBAC rules (e.g., `resources: ["*"]`)
- [ ] Each component has its own ServiceAccount (not default SA)
- [ ] RBAC templates tested on CRC (strict enforcement)
- [ ] `rbac.create: true` in values.yaml
- [ ] All RBAC bindings labeled with `app: phylaxor`

## Related Documents

- **`docs/PROJECT_CONTEXT.md`** — Project architecture and components
- **`docs/CONTRACT_ENV.md`** — Env var contract (logging modes)
- **`docs/VALUES_EXAMPLES.md`** — Example Helm values for different modes
- **`phylaxor-project/docs/SECURITY_MODEL.md`** — Application-level security requirements
