# Project Context — Phylaxor (GitOps)

This is the **canonical global context** document for Phylaxor deployment (Helm, RBAC, Argo apps). This is identical to the application repo version; it is kept synchronized across both repositories.

## What is Phylaxor

Phylaxor is a microservice-based **AI SRE Agent for Kubernetes / OpenShift** that automates incident response:

1. **Consumes** alerts from Alertmanager (webhook)
2. **Enriches** with cluster context (pods, events, logs, metrics)
3. **Applies** knowledge-base rules and historical decisions
4. **Notifies** on-call engineers (Telegram) with actionable troubleshooting steps
5. **Collects** feedback (thumbs up/down) to improve recommendations

**Goal**: Reduce MTTR (Mean Time To Resolution) by providing context-aware, repeatable incident responses.

## Target Environments

- **Kubernetes vanilla** (dev/labs): Minikube
- **OpenShift enterprise** (dev/labs): CRC (CodeReady Containers)

Primary focus: **enterprise-ready behavior for OpenShift** (strict RBAC, security-first, defensible design).

## High-Level Architecture

See application repo `ARCHITECTURE.md` for detailed flow and ASCII diagrams.

**Simplified flow**:
```
Alertmanager → ingest → Redis → enricher → Redis → decision → notifier (Telegram)
                                                      ↓
                                                  Postgres (decisions, KB, feedback)
```

## Microservices Overview

| Service | Role | RBAC | Permissions |
|---------|------|------|-------------|
| **ingest** | HTTP webhook endpoint | No | None (internal only) |
| **enricher** | Cluster context + logs | Yes | Observer + conditional pods/log |
| **decision** | KB matching + history | No | Postgres read-only |
| **notifier** | Telegram notification | No | No kube perms (critical!) |
| **feedback-gateway** | Telegram callbacks | No | Postgres write (feedback only) |
| **feedback** | Dashboard UI | No | Postgres read-only |
| **postgres** | Database (KB, history, feedback) | Yes | Storage, init script |
| **redis** | Event queue | No | Internal only |

See `docs/RBAC_MODEL.md` for detailed RBAC specification and Helm implementation.

## Current System State

### Working Components
- ✅ Feedback gateway: Telegram callback buttons → Postgres
- ✅ Decision engine: KB matching + historical lookup
- ✅ Enricher: cluster context + pod status + events
- ✅ Ingest: alert normalization → Redis
- ✅ Notifier: Telegram integration

### Known Issue
**OpenShift RBAC limitation**: Reading pod logs via Kubernetes API (`pods/log`) fails with 403 unless explicitly granted via ClusterRole.

This drives the **logging modes** strategy (see `docs/CONTRACT_ENV.md`).

## Security Posture

### Non-Negotiables
1. **No Secrets by default** — Do not grant Secret read permission
2. **Explicit opt-in for log access** — Logs may contain sensitive data
3. **Graceful degradation** — RBAC 403 errors do NOT break the pipeline
4. **Separation of duties** — Notifier has NO kube/log permissions
5. **Minimum RBAC principle** — Only grant what is strictly needed

### OpenShift vs Minikube
- **OpenShift CRC**: Strict RBAC enforcement (security testing ground)
- **Minikube**: Permissive by default (fast iteration)

## Configuration Contract (MVP)

Environment variables control behavior (see `docs/CONTRACT_ENV.md`):

- `PHYLAXOR_LOGS_MODE` — `none` | `loki` | `podlogs` (default: `none`)
- `PHYLAXOR_EVENTS_ENABLED` — `true` | `false` (default: `true`)
- `PHYLAXOR_LOGS_MAX_LINES`, `PHYLAXOR_LOGS_MAX_BYTES`, `PHYLAXOR_LOGS_LOOKBACK`
- Loki settings (endpoint, tenant, auth) — placeholder for future

**Why env vars first?** Simple, testable, and avoid CRDs/operators for now.

## Logging Modes Explained

See `docs/LOGGING_MODES.md` for deep dive.

| Mode | Source | Risk | Use Case |
|------|--------|------|----------|
| `none` | Events + resource status only | None (no logs read) | Default, safest |
| `loki` | Centralized logging backend | Low (enterprise-recommended) | OpenShift Logging / LokiStack |
| `podlogs` | Kubernetes API `pods/log` | High (logs can leak secrets) | Manual fallback if Loki unavailable |

## Immediate Next Steps

1. ✅ Define the env var contract (this doc + `CONTRACT_ENV.md`)
2. ⏳ Update Helm templates to expose logging mode config
3. ⏳ Implement RBAC conditionally (grant `pods/log` only if mode=podlogs)
4. ⏳ Test on CRC with OpenShift RBAC enforcement
5. ⏳ Implement Loki provider (future)

## Key Constraints

- Project is **Deployments + StatefulSets** (not CRDs/operators yet)
- RBAC templates must be **conditional** (grant permissions based on Helm values)
- Goal: Reach an **MVP that is launchable** without security concerns

## References

- **`phylaxor-project/ARCHITECTURE.md`** — Component details
- **`phylaxor-project/docs/CONTRACT_ENV.md`** — Env var specification
- **`docs/RBAC_MODEL.md`** — Helm implementation of conditional RBAC
- **`docs/VALUES_EXAMPLES.md`** — Example values for Minikube/CRC
- **`docs/DEPLOYMENT_TOPOLOGY.md`** — Namespace layout and serviceaccounts
