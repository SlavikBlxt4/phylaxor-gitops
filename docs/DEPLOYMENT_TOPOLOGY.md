# Deployment Topology — Phylaxor

This document describes the Kubernetes/OpenShift deployment layout: namespaces, components, services, and inter-component communication.

## High-Level Topology

```
Kubernetes Cluster
  │
  ├─ phylaxor (namespace)
  │   ├─ ingest (Deployment)
  │   ├─ enricher (Deployment)
  │   ├─ decision (Deployment)
  │   ├─ notifier (Deployment)
  │   ├─ feedback-gateway (Deployment)
  │   ├─ feedback (Deployment) [optional UI]
  │   │
  │   ├─ redis (StatefulSet)
  │   │   └─ Service: phylaxor-redis
  │   │
  │   ├─ postgres (StatefulSet)
  │   │   └─ Service: phylaxor-postgres
  │   │
  │   ├─ ServiceAccounts (enricher, notifier, etc.)
  │   ├─ ConfigMaps (alertmanager config, KB rules)
  │   └─ Secrets (DB passwords, Telegram token, Loki auth)
  │
  ├─ alertmanager (namespace) [external, sends webhooks to ingest]
  │
  ├─ prometheus (namespace) [external, generates alerts]
  │
  └─ (OpenShift only) openshift-logging (namespace)
      └─ Loki/LokiStack [for centralized logging]
```

## Namespace: phylaxor

### Deployments

| Component | Replicas | Port | RBAC | Notes |
|-----------|----------|------|------|-------|
| **ingest** | 1–2 | 5000 | None | HTTP webhook endpoint |
| **enricher** | 1–3 | (none) | Observer + conditional logs | Processes alerts |
| **decision** | 1–2 | (none) | None | Generates recommendations |
| **notifier** | 1 | (none) | **None** (critical) | Sends Telegram notifications |
| **feedback-gateway** | 1 | 8081 | None | Telegram callback handler |
| **feedback** | 1 | 8080 | None | Dashboard UI (optional) |

### StatefulSets

| Component | Replicas | Port | Storage | Notes |
|-----------|----------|------|---------|-------|
| **postgres** | 1 | 5432 | Persistent | Knowledge base, decisions, feedback |
| **redis** | 1 | 6379 | Ephemeral or persistent | Event queues (phylaxor_raw, phylaxor_enriched) |

### Services

| Service | Type | Selector | Port | Notes |
|---------|------|----------|------|-------|
| phylaxor-ingest | ClusterIP | ingest | 5000 | Internal + expose to Alertmanager |
| phylaxor-enricher | ClusterIP | enricher | (none) | Internal (Redis consumer) |
| phylaxor-decision | ClusterIP | decision | (none) | Internal (Redis consumer) |
| phylaxor-notifier | ClusterIP | notifier | (none) | Internal (Redis consumer) |
| phylaxor-feedback-gateway | ClusterIP | feedback-gateway | 8081 | Internal + expose to Telegram |
| phylaxor-feedback | ClusterIP | feedback | 8080 | Internal (UI access) |
| phylaxor-postgres | ClusterIP | postgres | 5432 | Internal (all components) |
| phylaxor-redis | ClusterIP | redis | 6379 | Internal (ingest, enricher, decision, notifier) |

### Ingress / Routes

#### Minikube (Ingress)

```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: phylaxor-ingest
  namespace: phylaxor
spec:
  rules:
    - host: phylaxor-ingest.minikube.local
      http:
        paths:
          - path: /webhook
            pathType: Prefix
            backend:
              service:
                name: phylaxor-ingest
                port:
                  number: 5000
```

#### OpenShift (Route)

```yaml
apiVersion: route.openshift.io/v1
kind: Route
metadata:
  name: phylaxor-ingest
  namespace: phylaxor
spec:
  host: phylaxor-ingest.example.com
  port:
    targetPort: 5000
  to:
    kind: Service
    name: phylaxor-ingest
  tls:
    termination: edge  # Edge termination (optional TLS)
```

## Data Flow

### Alert Processing Pipeline

```
1. Alertmanager
   └─→ HTTP POST /webhook (TLS if available)
       └─→ phylaxor-ingest Service (5000)
           └─→ ingest Pod
               └─→ Normalize alert
                   └─→ Push to Redis phylaxor_raw

2. enricher Pod (consumer)
   └─→ Redis BLPOP phylaxor_raw
       └─→ Fetch context:
           ├─→ Kubernetes API (observer role)
           │   └─→ pods, nodes, events, storage
           └─→ Logs (if enabled):
               └─→ Kubernetes API pods/log (if PHYLAXOR_LOGS_MODE=podlogs)
                   OR Loki API (if PHYLAXOR_LOGS_MODE=loki)
       └─→ Push to Redis phylaxor_enriched

3. decision Pod (consumer)
   └─→ Redis BLPOP phylaxor_enriched
       └─→ Query Postgres:
           ├─→ kb_items + kb_matchers (KB rules)
           ├─→ decisions (historical lookup)
           └─→ alerts (fingerprint lookup)
       └─→ Generate recommendation
           └─→ Insert into Postgres decisions table
               └─→ Push to Redis (for notifier)

4. notifier Pod (consumer)
   └─→ Redis BLPOP (decision)
       └─→ Send Telegram message
           └─→ notifier has NO Kubernetes access
               (only Telegram API + Postgres read)

5. Telegram User
   └─→ Click feedback button
       └─→ Telegram Bot Webhook
           └─→ phylaxor-feedback-gateway Service (8081)
               └─→ feedback-gateway Pod
                   └─→ Insert vote into Postgres feedback table
```

## ServiceAccounts and RBAC

### ServiceAccounts

```
phylaxor (namespace)
  ├─ phylaxor-ingest (no RBAC rules)
  ├─ phylaxor-enricher
  │   └─ ClusterRoleBinding → phylaxor-observer (baseline)
  │   └─ ClusterRoleBinding → phylaxor-log-reader (if mode=podlogs)
  ├─ phylaxor-decision (no RBAC rules)
  ├─ phylaxor-notifier (NO RBAC RULES - critical!)
  ├─ phylaxor-feedback-gateway (no RBAC rules)
  └─ phylaxor-feedback (no RBAC rules)
```

See `docs/RBAC_MODEL.md` for detailed RBAC implementation.

## ConfigMaps and Secrets

### ConfigMaps

| Name | Purpose | Mounted To |
|------|---------|-----------|
| phylaxor-alertmanager-config | Alertmanager webhook URL | Alertmanager (external) |
| phylaxor-kb-rules | Knowledge base matchers (YAML) | decision Pod (optional, for init) |
| phylaxor-logging-config | Logging mode and limits | All enricher Pods (env vars) |

### Secrets

| Name | Purpose | Mounted To | Note |
|------|---------|-----------|------|
| phylaxor-db-credentials | Postgres username/password | All Pods (env vars) | Created by Helm |
| phylaxor-telegram-token | Telegram bot token | notifier Pod (env var) | Optional (can be disabled) |
| phylaxor-loki-credentials | Loki auth (basic/bearer) | enricher Pod (env var) | Only if mode=loki |

## Network Communication

### Internal (Cluster)

```
ingest ←→ Redis (6379)
enricher ←→ Redis (6379)
decision ←→ Redis (6379)
notifier ←→ Redis (6379)
         ←→ Postgres (5432)
All Pods ←→ Postgres (5432) [for KB, decisions, feedback]
enricher ←→ Kubernetes API (443)
```

### External

```
Alertmanager (external cluster) → ingest Service (5000)
notifier → Telegram API (https://api.telegram.org)
enricher → Loki API (if mode=loki, internal or external)
Feedback dashboard ← Telegram callbacks → feedback-gateway Service (8081)
```

### NetworkPolicy (Optional, Recommended)

```yaml
# Deny all by default
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: phylaxor-default-deny
  namespace: phylaxor
spec:
  podSelector: {}
  policyTypes:
    - Ingress
    - Egress

---
# Allow ingest to receive from Alertmanager (external)
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: phylaxor-ingest-ingress
  namespace: phylaxor
spec:
  podSelector:
    matchLabels:
      component: ingest
  policyTypes:
    - Ingress
  ingress:
    - from:
        - namespaceSelector:
            matchLabels:
              name: monitoring  # Alertmanager namespace
      ports:
        - protocol: TCP
          port: 5000

---
# Allow enricher to query Kubernetes API (for pods, events, etc.)
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: phylaxor-enricher-kubernetes-api
  namespace: phylaxor
spec:
  podSelector:
    matchLabels:
      component: enricher
  policyTypes:
    - Egress
  egress:
    - to:
        - namespaceSelector: {}
      ports:
        - protocol: TCP
          port: 443  # Kubernetes API

---
# Allow notifier to reach Telegram API (external)
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: phylaxor-notifier-telegram
  namespace: phylaxor
spec:
  podSelector:
    matchLabels:
      component: notifier
  policyTypes:
    - Egress
  egress:
    - to:
        - namespaceSelector: {}
      ports:
        - protocol: TCP
          port: 443  # External HTTPS

---
# Allow all internal (Redis, Postgres) communication
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: phylaxor-internal
  namespace: phylaxor
spec:
  podSelector: {}
  policyTypes:
    - Egress
  egress:
    - to:
        - podSelector: {}
      ports:
        - protocol: TCP
          port: 5432  # Postgres
        - protocol: TCP
          port: 6379  # Redis
```

## Deployment Strategy

### Minikube (Development)

```yaml
# Minimal resources, no persistence, permissive RBAC
replicaCount: 1
postgres:
  persistence:
    enabled: false  # emptyDir
redis:
  persistence:
    enabled: false  # emptyDir
resources:
  requests:
    memory: "128Mi"
  limits:
    memory: "512Mi"
```

### OpenShift CRC (Testing)

```yaml
# Moderate resources, some persistence, strict RBAC
replicaCount: 1–2
postgres:
  persistence:
    enabled: true
    size: 10Gi
redis:
  persistence:
    enabled: true
    size: 5Gi
resources:
  requests:
    memory: "256Mi"
  limits:
    memory: "1Gi"
```

### Production (Future)

```yaml
# High availability, full persistence, monitoring
replicaCount: 3
postgres:
  replicas: 3  # HA with streaming replication
  persistence:
    enabled: true
    size: 100Gi
    backups: enabled
redis:
  replicas: 3  # Cluster mode
  persistence:
    enabled: true
    size: 50Gi
monitoring:
  enabled: true  # Prometheus scrape config
  alerting: enabled
resources:
  requests:
    memory: "512Mi"
    cpu: "250m"
  limits:
    memory: "2Gi"
    cpu: "1000m"
```

## Scaling

### Horizontal Scaling

- **ingest**: Scale 1–3 (webhook endpoints); use Service load balancing
- **enricher**: Scale 1–5 (Redis consumer group; faster alert processing)
- **decision**: Scale 1–3 (Redis consumer group; faster recommendations)
- **notifier**: Scale 1–2 (Telegram rate limits ~30 msg/sec; no parallel benefit)
- **postgres**: Scale 1 (single primary; HA requires replication setup)
- **redis**: Scale 1 (single primary; cluster mode optional)

### Vertical Scaling

For high-volume alert ingestion, increase resource limits (memory, CPU) for:
- enricher (heavy Kubernetes API queries, log fetching)
- decision (KB matching, DB queries)

## Health Checks

### Readiness Probes

```yaml
readinessProbe:
  httpGet:
    path: /healthz
    port: 8080
  initialDelaySeconds: 5
  periodSeconds: 10
```

### Liveness Probes

```yaml
livenessProbe:
  httpGet:
    path: /livez
    port: 8080
  initialDelaySeconds: 15
  periodSeconds: 20
```

## Monitoring (Future)

```yaml
# Prometheus ServiceMonitor (optional)
apiVersion: monitoring.coreos.com/v1
kind: ServiceMonitor
metadata:
  name: phylaxor
  namespace: phylaxor
spec:
  selector:
    matchLabels:
      app: phylaxor
  endpoints:
    - port: metrics
      interval: 30s
```

## Related Documents

- **`docs/RBAC_MODEL.md`** — RBAC implementation in Helm
- **`docs/VALUES_EXAMPLES.md`** — Helm values for different scenarios
- **`phylaxor-project/ARCHITECTURE.md`** — Component details
