# Phylaxor — GitOps (Helm + Argo)

This repository contains Helm charts, RBAC templates, and Argo app definitions for deploying Phylaxor.

For application code, see `phylaxor-project/`.

## Repository Structure

```
phylaxor-gitops/
  ├── apps/
  │   ├── phylaxor/                    # Main Phylaxor Helm chart
  │   │   ├── Chart.yaml
  │   │   ├── values.yaml              # Default values (safe defaults)
  │   │   ├── values-minikube.yaml     # Dev environment
  │   │   ├── values-openshift.yaml    # Enterprise simulation (CRC)
  │   │   └── templates/
  │   │       ├── namespace.yaml
  │   │       ├── serviceaccount.yaml  # Per-component ServiceAccounts
  │   │       ├── rbac.yaml            # Conditional RBAC (pods/log based on mode)
  │   │       ├── configmaps/          # App config, KB rules
  │   │       ├── deployments/         # Microservices
  │   │       ├── security/            # OpenShift CRC-specific
  │   │       └── services/            # Kubernetes Services
  │   │
  │   └── phylaxor-db/                 # Postgres + Redis StatefulSets
  │       ├── Chart.yaml
  │       ├── values-minikube.yaml
  │       ├── values-openshift.yaml
  │       └── templates/
  │           ├── statefulsets/
  │           ├── services/
  │           └── storage/
  │
  ├── config/
  │   └── app-catalog/                 # Argo AppProject (future)
  │
  ├── docs/
  │   ├── PROJECT_CONTEXT.md           # Global context (synchronized with app repo)
  │   ├── CONTRACT_ENV.md              # Env var contract (synchronized)
  │   ├── RBAC_MODEL.md                # RBAC implementation in Helm
  │   ├── VALUES_EXAMPLES.md           # Complete Helm values examples
  │   └── DEPLOYMENT_TOPOLOGY.md       # Namespace layout, services, network
  │
  └── .github/
      └── copilot-instructions.md      # Copilot instructions for this repo
```

## Quick Start

### Deploy on Minikube (Development)

```bash
# Prerequisites: Minikube, Helm 3+

# Add Phylaxor repo (if using external repo; else use local)
# helm repo add phylaxor https://your-registry.example.com
# helm repo update

# Deploy databases + services
helm install phylaxor-db ./apps/phylaxor-db \
  -f apps/phylaxor-db/values-minikube.yaml \
  -n phylaxor --create-namespace

helm install phylaxor ./apps/phylaxor \
  -f apps/phylaxor/values-minikube.yaml \
  -n phylaxor

# Verify
kubectl get deployments -n phylaxor
kubectl get pods -n phylaxor

# Send test alert
kubectl port-forward -n phylaxor svc/phylaxor-ingest 5000:5000 &
curl -X POST http://localhost:5000/webhook \
  -H "Content-Type: application/json" \
  -d '{"alerts": [{"status": "firing", "labels": {"alertname": "Test"}}]}'

# Check logs
kubectl logs -n phylaxor -l component=enricher
kubectl logs -n phylaxor -l component=decision
```

### Deploy on OpenShift CRC (Enterprise Simulation)

```bash
# Prerequisites: CRC, oc CLI

# Login to CRC
oc login -u developer -p developer

# Deploy
helm install phylaxor-db ./apps/phylaxor-db \
  -f apps/phylaxor-db/values-openshift.yaml \
  -n phylaxor --create-namespace

helm install phylaxor ./apps/phylaxor \
  -f apps/phylaxor/values-openshift.yaml \
  -n phylaxor

# Verify RBAC (should enforce strict permissions)
oc get clusterrolebinding | grep phylaxor
```

## Global Context & Contract

**Before modifying Helm charts or RBAC, read these documents:**

1. **`docs/PROJECT_CONTEXT.md`** — Project architecture, microservices, current state
2. **`docs/CONTRACT_ENV.md`** — Environment variable contract (logging modes, defaults)
3. **`docs/RBAC_MODEL.md`** — RBAC implementation and conditional permissions
4. **`docs/VALUES_EXAMPLES.md`** — Complete Helm values for all scenarios
5. **`docs/DEPLOYMENT_TOPOLOGY.md`** — Namespace layout, services, networking
6. **`.github/copilot-instructions.md`** — Copilot instructions and non-negotiables

## Key Concepts

### Logging Modes (Configuration)

Three logging modes available:

| Mode | Source | RBAC | Use Case |
|------|--------|------|----------|
| `none` | Events + resource status only | Observer | Default, safest |
| `loki` | Centralized logging backend | Observer | Enterprise (future) |
| `podlogs` | Kubernetes API pods/log | Observer + pods/log | Dev/test labs |

**Default**: `none` (safest).

**RBAC**: Helm conditionally grants `pods/log` only if `logging.mode=podlogs`.

See `docs/VALUES_EXAMPLES.md` for complete values files for each mode.

### RBAC Model

**Key principles**:

1. **No Secrets by default** — Never grant Secret permission
2. **Conditional pods/log** — Only if `logging.mode=podlogs`
3. **Notifier has zero RBAC** — Critical for security
4. **Minimum privileges** — Each component gets only what it needs
5. **Separate ServiceAccounts** — Never use default SA

See `docs/RBAC_MODEL.md` for Helm implementation.

### Deployment Topology

One namespace (`phylaxor`):

```
├─ Deployments: ingest, enricher, decision, notifier, feedback-gateway, feedback
├─ StatefulSets: postgres, redis
├─ Services: phylaxor-ingest, phylaxor-postgres, phylaxor-redis, etc.
├─ ServiceAccounts: phylaxor-ingest, phylaxor-enricher, phylaxor-notifier, etc.
└─ RBAC: ClusterRoles + ClusterRoleBindings (conditional based on mode)
```

See `docs/DEPLOYMENT_TOPOLOGY.md` for complete topology.

## Security Posture

### Non-Negotiables

- ✅ **No Secrets by default** — Do not grant Secret read permission
- ✅ **Conditional RBAC** — pods/log only if explicitly enabled
- ✅ **Notifier isolation** — Notifier has NO Kubernetes permissions
- ✅ **Minimum RBAC** — List exact resources and verbs (no wildcards)

See `docs/RBAC_MODEL.md` and `phylaxor-project/docs/SECURITY_MODEL.md` for details.

## Configuration

### Helm Values

All values are in `values.yaml` and environment-specific overrides:

```bash
# Override specific values
helm install phylaxor ./apps/phylaxor \
  -f values-minikube.yaml \
  --set logging.mode=podlogs \  # Override mode
  -n phylaxor
```

### Environment Variables

Applications receive env vars from Helm templates. See `docs/CONTRACT_ENV.md`:

```yaml
# In values.yaml
logging:
  mode: none
  maxLines: 500

# Helm template passes to Deployment
env:
  - name: PHYLAXOR_LOGS_MODE
    value: {{ .Values.logging.mode }}
  - name: PHYLAXOR_LOGS_MAX_LINES
    value: {{ .Values.logging.maxLines | quote }}
```

## Testing Deployments

### Scenario 1: Safe Mode (mode=none)

```bash
helm install phylaxor ./apps/phylaxor \
  -f values-minikube.yaml \
  -n phylaxor

# Verify: No pods/log RBAC binding
kubectl get clusterrolebinding | grep log-reader
# (should have no output)

# Send alert, verify pipeline works
```

### Scenario 2: OpenShift RBAC 403 (mode=podlogs on CRC, no permission)

```bash
# Deploy with mode=podlogs
helm install phylaxor ./apps/phylaxor \
  -f values-openshift.yaml \
  --set logging.mode=podlogs \
  -n phylaxor

# Verify binding created
oc get clusterrolebinding phylaxor-log-reader

# Delete it (simulate admin not granting permission)
oc delete clusterrolebinding phylaxor-log-reader

# Send alert
# Verify: WARN in enricher logs (graceful degradation)
oc logs -n phylaxor phylaxor-enricher-xyz | grep -i "pods/log" | grep -i "warn"
```

See `docs/VALUES_EXAMPLES.md` for complete scenarios and test procedures.

## Development Workflow

### 1. Make Changes to Helm Chart

```bash
# Edit templates, values, etc.
vim apps/phylaxor/values.yaml
vim apps/phylaxor/templates/rbac.yaml
```

### 2. Validate Helm Template Rendering

```bash
helm template phylaxor ./apps/phylaxor \
  -f values-minikube.yaml > /tmp/manifest.yaml

# Check RBAC
grep -A 5 "ClusterRoleBinding" /tmp/manifest.yaml

# Check conditional logic (pods/log should NOT appear with mode=none)
grep "pods/log" /tmp/manifest.yaml
```

### 3. Test on Minikube

```bash
helm install phylaxor ./apps/phylaxor \
  -f values-minikube.yaml \
  -n phylaxor --create-namespace

# Send alert, verify pipeline
```

### 4. Test on CRC

```bash
oc login -u developer -p developer

helm install phylaxor ./apps/phylaxor \
  -f values-openshift.yaml \
  -n phylaxor --create-namespace

# Verify RBAC enforcement (strict)
```

### 5. Update Documentation

- Update `docs/RBAC_MODEL.md` if RBAC changed
- Update `docs/VALUES_EXAMPLES.md` if new values added
- Update `docs/DEPLOYMENT_TOPOLOGY.md` if topology changed

## RBAC Development Guidelines

See **`.github/copilot-instructions.md`** for detailed guidelines:

- ✅ Never grant `pods/log` unconditionally
- ✅ Always make `pods/log` conditional in Helm (if-eq mode=podlogs)
- ✅ Ensure notifier has ZERO RBAC bindings
- ✅ Test on both Minikube and CRC
- ✅ Use `helm template` to verify rendering
- ✅ Document all RBAC changes in `docs/RBAC_MODEL.md`

## Troubleshooting

### RBAC 403 Errors

```bash
# Check ServiceAccount exists
kubectl get serviceaccount -n phylaxor phylaxor-enricher

# Check ClusterRoleBinding
kubectl get clusterrolebinding | grep phylaxor-observer

# If pods/log denied (expected on CRC with mode=none)
kubectl logs -n phylaxor phylaxor-enricher-xyz | grep -i "pods/log"
# Should show warning (not error) if mode=podlogs without permission
```

### Pod Logs

```bash
# View enricher logs
kubectl logs -n phylaxor -l component=enricher -f

# View decision logs
kubectl logs -n phylaxor -l component=decision -f

# View notifier logs
kubectl logs -n phylaxor -l component=notifier -f
```

### Redis Events

```bash
# Check Redis for raw alerts
kubectl exec -n phylaxor redis-pod -- redis-cli LLEN phylaxor_raw

# Check Redis for enriched alerts
kubectl exec -n phylaxor redis-pod -- redis-cli LLEN phylaxor_enriched
```

### Database

```bash
# Query Postgres
kubectl exec -n phylaxor postgres-pod -- psql -U phylaxor phylaxor

# Check decisions table
SELECT COUNT(*) FROM decisions;

# Check feedback
SELECT COUNT(*) FROM feedback;
```

## Next Steps

1. ✅ Helm charts created (current)
2. ✅ RBAC templates conditional (based on logging mode)
3. ⏳ Test on CRC (strict RBAC enforcement)
4. ⏳ Implement Loki provider (future)
5. ⏳ Add Argo CD apps (future)

## References

- **`phylaxor-project/`** — Application code repo
- **`phylaxor-project/docs/SECURITY_MODEL.md`** — App-level security requirements
- **`phylaxor-project/ARCHITECTURE.md`** — Component architecture
- **`docs/TEST_MATRIX.md`** (in app repo) — E2E test scenarios

---

**Last Updated**: December 2025  
**Contact**: SlavikBlxt4 (GitHub)
