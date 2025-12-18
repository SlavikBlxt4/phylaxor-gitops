# Values Examples — Phylaxor Helm

This document provides complete Helm values examples for different deployment scenarios.

## Example 1: Minikube — Safe Dev (mode=none)

**Use case**: Fast iteration, no RBAC complexity, no log exposure.

**File**: `values-minikube.yaml`

```yaml
# Global
replicaCount: 1
environment: minikube

# Logging: Safest mode (no logs)
logging:
  mode: none
  eventsEnabled: true
  maxLines: 500
  maxBytes: 100000
  lookbackSeconds: 300

# RBAC: Create observer role for enricher
rbac:
  create: true
  # pods/log NOT granted (mode=none)

# Services
services:
  ingest:
    type: ClusterIP
    port: 5000
  feedback:
    type: ClusterIP
    port: 8080
  notifier:
    type: ClusterIP
    port: 8081

# Database
postgres:
  enabled: true
  version: 14
  persistence:
    enabled: false  # Use emptyDir for dev
  connection:
    host: postgres
    port: 5432
    database: phylaxor
    user: phylaxor
    password: dev-password  # Only for dev!

# Redis
redis:
  enabled: true
  version: 7
  persistence:
    enabled: false  # Use emptyDir for dev

# Telegram (optional for dev)
notifier:
  telegram:
    enabled: false
    botToken: ""  # Not needed for testing

# Image registry
image:
  registry: docker.io
  pullPolicy: IfNotPresent

# Resource limits (loose for dev)
resources:
  requests:
    memory: "128Mi"
    cpu: "100m"
  limits:
    memory: "512Mi"
    cpu: "500m"
```

### Deploy on Minikube

```bash
helm install phylaxor ./apps/phylaxor -f apps/phylaxor/values-minikube.yaml -n phylaxor --create-namespace
```

### Verify

```bash
# Check deployments
kubectl get deployments -n phylaxor

# Check RBAC (should have observer binding, no log-reader binding)
kubectl get clusterrolebinding | grep phylaxor

# Send test alert
kubectl port-forward -n phylaxor svc/phylaxor-ingest 5000:5000 &
curl -X POST http://localhost:5000/webhook \
  -H "Content-Type: application/json" \
  -d '{"alerts": [{"status": "firing", "labels": {"alertname": "Test"}}]}'
```

---

## Example 2: OpenShift CRC — Enterprise Simulation (mode=none)

**Use case**: Validate tight RBAC without log complexity. Simulates production constraints.

**File**: `values-openshift.yaml`

```yaml
# Global
replicaCount: 1
environment: openshift-crc

# Logging: Safe mode (no logs, respects CRC strict RBAC)
logging:
  mode: none
  eventsEnabled: true
  maxLines: 500
  maxBytes: 100000
  lookbackSeconds: 300

# RBAC: Create observer role only (not pods/log)
rbac:
  create: true
  # pods/log NOT granted (mode=none, respects security)

# Namespace
namespace: phylaxor

# Services (OpenShift Route instead of Ingress for ingest)
services:
  ingest:
    type: ClusterIP
    port: 5000
  feedback:
    type: ClusterIP
    port: 8080

# Database (use internal postgres)
postgres:
  enabled: true
  version: 14
  persistence:
    enabled: true
    size: 10Gi
    storageClass: fast  # OpenShift storage
  connection:
    host: postgres.phylaxor.svc.cluster.local
    port: 5432
    database: phylaxor
    user: phylaxor
    password: ""  # Use Secret in production

# Redis
redis:
  enabled: true
  version: 7
  persistence:
    enabled: true
    size: 5Gi
    storageClass: fast

# OpenShift-specific
openshift:
  enabled: true
  route:
    enabled: true
    host: phylaxor-ingest.example.com  # Replace with actual CRC hostname
    tls:
      enabled: false  # Only for testing

# Resource limits (reasonable for enterprise)
resources:
  requests:
    memory: "256Mi"
    cpu: "100m"
  limits:
    memory: "1Gi"
    cpu: "500m"

# Security Context
securityContext:
  runAsNonRoot: true
  runAsUser: 65534
  allowPrivilegeEscalation: false
  capabilities:
    drop: ["ALL"]
```

### Deploy on OpenShift CRC

```bash
# Login to CRC
oc login -u developer -p developer

# Create namespace and install Helm chart
helm install phylaxor ./apps/phylaxor \
  -f apps/phylaxor/values-openshift.yaml \
  -n phylaxor --create-namespace
```

### Verify RBAC Strictness

```bash
# Check ClusterRoleBindings (should have observer, NOT log-reader)
oc get clusterrolebinding | grep phylaxor

# Verify enricher cannot read pods/log
oc logs -n phylaxor phylaxor-enricher-xyz | grep -i "pod log" | grep -i "denied"
# (should have no output if mode=none, or should NOT appear since not attempted)

# Verify pipeline works without logs
oc logs -n phylaxor phylaxor-enricher-xyz | grep "enriched event"
```

---

## Example 3: Minikube — Testing Pod Logs (mode=podlogs)

**Use case**: Test graceful degradation and RBAC 403 handling.

**File**: `values-minikube-podlogs.yaml`

Based on Example 1, with logging mode changed:

```yaml
# Copy from values-minikube.yaml, but:
logging:
  mode: podlogs  # Enable direct pod log access
  eventsEnabled: true
  maxLines: 200  # Smaller for testing
  maxBytes: 50000
  lookbackSeconds: 600  # 10 min lookback

# RBAC: pods/log IS granted (because mode=podlogs)
rbac:
  create: true
  # pods/log WILL be bound (mode=podlogs in templates)
```

### Deploy and Test

```bash
helm install phylaxor ./apps/phylaxor -f values-minikube-podlogs.yaml -n phylaxor --create-namespace

# Send alert
curl -X POST http://localhost:5000/webhook ...

# Verify logs are fetched
kubectl logs -n phylaxor phylaxor-enricher-xyz | grep "log lines fetched"
```

---

## Example 4: OpenShift CRC — Testing RBAC 403 (mode=podlogs, no permission)

**Use case**: Simulate OpenShift denying pods/log and test graceful degradation.

**File**: `values-openshift-podlogs-test.yaml`

```yaml
# Copy from values-openshift.yaml, but:
logging:
  mode: podlogs  # Try to use pod logs
  eventsEnabled: true
  maxLines: 200
  maxBytes: 50000
  lookbackSeconds: 600

rbac:
  create: true
  # In this test, we will CREATE the binding but then DELETE it manually
  # to simulate OpenShift denying pods/log permission
```

### Deploy and Simulate Denial

```bash
# Deploy normally
helm install phylaxor ./apps/phylaxor \
  -f values-openshift-podlogs-test.yaml \
  -n phylaxor --create-namespace

# Verify binding was created
oc get clusterrolebinding phylaxor-log-reader

# NOW delete it (simulate admin not granting permission)
oc delete clusterrolebinding phylaxor-log-reader

# Send alert
curl -X POST http://ingest-svc:5000/webhook ...

# Verify graceful degradation: WARN in logs, not ERROR
oc logs -n phylaxor phylaxor-enricher-xyz | grep -i "pods/log" | grep -i "warn"
# Should see: "WARN: pods/log denied for pod X in namespace Y"

# Verify pipeline continued (events in Redis)
oc exec -n phylaxor redis-pod -- redis-cli LLEN phylaxor_enriched
# Should have entries

# Verify decision was generated
oc exec -n phylaxor postgres-pod -- psql -U phylaxor phylaxor -c "SELECT COUNT(*) FROM decisions;"
# Should have entries
```

---

## Example 5: OpenShift CRC — Future Loki Mode (Placeholder)

**Use case**: Future enterprise path with centralized logging.

**File**: `values-openshift-loki.yaml` (Future)

```yaml
# Copy from values-openshift.yaml, but:
logging:
  mode: loki  # Centralized logging backend
  eventsEnabled: true
  maxLines: 200
  maxBytes: 100000
  lookbackSeconds: 600

# Loki integration (placeholder for future implementation)
loki:
  enabled: true
  endpoint: https://loki.openshift-logging.svc.cluster.local:3100
  tenantId: phylaxor
  auth:
    type: basicAuth
    username: phylaxor-reader
    password: ""  # From Secret (see below)

# Secret for Loki credentials
secrets:
  loki:
    name: loki-credentials
    # This Secret must exist before deploying:
    # oc create secret generic loki-credentials \
    #   --from-literal=password=<password> \
    #   -n phylaxor

rbac:
  create: true
  # pods/log NOT needed (Loki provides logs, not API)
```

### Prerequisites (When Loki is Ready)

```bash
# Install Loki/Logging in OpenShift (admin task)
# oc apply -f loki-operator.yaml

# Create credentials Secret
oc create secret generic loki-credentials \
  --from-literal=password=mypassword \
  -n phylaxor

# Deploy
helm install phylaxor ./apps/phylaxor \
  -f values-openshift-loki.yaml \
  -n phylaxor --create-namespace
```

---

## Comparison: All Modes

| Aspect | Minikube mode=none | CRC mode=none | Minikube mode=podlogs | CRC mode=podlogs (test) | CRC mode=loki (future) |
|--------|---|---|---|---|---|
| **Log access** | None | None | API direct | API direct | Loki central |
| **RBAC complexity** | Low | Low | Medium | Medium | Low |
| **pods/log binding** | No | No | Yes | Yes (then delete) | No |
| **Risk** | None | None | High | High | Low |
| **Use case** | Dev | Demo | Dev/test | Test 403 handling | Enterprise |

---

## How to Use These Examples

### Quick Start

1. **Choose your scenario** (Minikube safe, CRC safe, or mode=podlogs test)
2. **Copy the values file** to your checkout
3. **Update placeholders** (e.g., OpenShift hostname, Loki endpoint)
4. **Deploy**:
   ```bash
   helm install phylaxor ./apps/phylaxor -f values-YOUR-SCENARIO.yaml -n phylaxor --create-namespace
   ```
5. **Verify** using the test commands in each section

### Customization

All examples inherit from Chart defaults in `Chart.yaml`. To override:

```bash
helm install phylaxor ./apps/phylaxor \
  -f values-minikube.yaml \
  --set logging.mode=podlogs \  # Override one value
  -n phylaxor
```

## Related Documents

- **`docs/CONTRACT_ENV.md`** — Env var specification
- **`docs/RBAC_MODEL.md`** — RBAC implementation in Helm
- **`docs/DEPLOYMENT_TOPOLOGY.md`** — Namespace layout and services
- **`phylaxor-project/docs/LOGGING_MODES.md`** — Logging mode analysis
