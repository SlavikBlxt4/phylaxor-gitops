# Deployment Topology — Phylaxor

This document describes how Phylaxor is laid out in Kubernetes or OpenShift.

## High-Level Topology

```text
Cluster
  namespace: phylaxor
    Deployments:
      ingest
      enricher
      decision
      brain-gateway
      notifier
      feedback-gateway
      feedback

    StatefulSets:
      postgres
      redis

    Supporting resources:
      ServiceAccounts
      Services
      ConfigMaps
      Secrets
      RBAC bindings
```

## Components In Cluster

### Deployments

| Component | Main Role | Notes |
|-----------|-----------|-------|
| `ingest` | HTTP alert entrypoint | receives Alertmanager payloads |
| `enricher` | cluster enrichment | optional logs depending on mode |
| `decision` | decision selection | uses history, KB, and Brain Gateway |
| `brain-gateway` | AI contract boundary | validates request/response schemas |
| `notifier` | Telegram sender | no Kubernetes RBAC |
| `feedback-gateway` | Telegram callback receiver | stores feedback |
| `feedback` | dashboard UI | reads operational data from Postgres |

### StatefulSets

| Component | Main Role |
|-----------|-----------|
| `postgres` | persistent store for alerts, KB, decisions, feedback |
| `redis` | queue transport between pipeline stages |

## Service Layout

| Service | Purpose |
|---------|---------|
| `ingest` | receives alert webhooks |
| `enricher` | internal worker service |
| `decision` | internal worker service |
| `brain-gateway` | internal AI service |
| `notifier` | internal Telegram sender |
| `feedback-gateway` | callback/webhook receiver |
| `feedback` | dashboard access |
| `postgres` | database access |
| `redis` | queue access |

## Runtime Data Flow

```text
Alertmanager
  -> ingest
  -> Redis(phylaxor_raw)
  -> enricher
     -> Kubernetes API
     -> optional Loki or pods/log
  -> Redis(phylaxor_enriched)
  -> decision
     -> Postgres
     -> brain-gateway
     -> notifier
  -> Telegram

Telegram callbacks
  -> feedback-gateway
  -> Postgres

feedback UI
  -> Postgres
```

## RBAC Shape

Only the enricher needs Kubernetes read permissions.

Baseline enricher access:
- pods
- events
- nodes
- namespaces
- storageclasses

Conditional enricher access:
- `pods/log` only when `logging.mode=podlogs`

Other services:
- no Kubernetes RBAC unless explicitly documented

## Secrets And Config

Typical runtime inputs:
- database DSN
- Telegram credentials
- Brain Gateway OpenAI API key
- optional Loki credentials
- configmaps for rules and contracts

## Environment Notes

Minikube:
- fast iteration
- looser operational constraints

OpenShift CRC:
- strict RBAC validation
- better reference for production-like behavior

## See Also

- `PROJECT_CONTEXT.md`
- `CONTRACT_ENV.md`
- `RBAC_MODEL.md`
- `../../phylaxor-project/docs/ARCHITECTURE.md`
