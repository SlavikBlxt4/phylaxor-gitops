# Phylaxor — GitOps

This repository contains the Helm charts and deployment documentation for Phylaxor.

It covers:
- application and database charts
- environment-specific values for Minikube and OpenShift
- per-service ServiceAccounts
- conditional RBAC for logging modes
- Brain Gateway deployment artifacts

For service implementation details, see `../phylaxor-project`.

## Start Here

If you are new to the deployment side, read these files in order:

1. `docs/README.md`
2. `docs/PROJECT_CONTEXT.md`
3. `docs/DEPLOYMENT_TOPOLOGY.md`
4. `docs/CONTRACT_ENV.md`
5. `docs/RBAC_MODEL.md`

## Current State

What this repo already deploys:
- ingest, enricher, decision, notifier
- feedback gateway and feedback UI
- Redis and Postgres charts
- Brain Gateway deployment and service
- logging modes via Helm values
- conditional `pods/log` permission for the enricher

What remains future-facing:
- Loki-backed logging implementation
- more deployment hardening
- optional Argo-oriented expansion

## Repository Structure

```text
phylaxor-gitops/
  apps/phylaxor/          Main application chart
  apps/phylaxor-db/       Postgres and Redis chart
  docs/                   Deployment and RBAC documentation
  deploy_and_test.sh      Deployment helper
  e2e_test_all_modes.sh   Logging-mode validation helper
  quick_rbac_test.sh      RBAC smoke test
```

## Quick Start

Deploy databases:

```bash
helm install phylaxor-db ./apps/phylaxor-db \
  -f apps/phylaxor-db/values-openshift.yaml \
  -n phylaxor --create-namespace
```

Deploy application services:

```bash
helm install phylaxor ./apps/phylaxor \
  -f apps/phylaxor/values-openshift.yaml \
  -n phylaxor
```

Render manifests before applying changes:

```bash
helm template phylaxor ./apps/phylaxor \
  -f apps/phylaxor/values-openshift.yaml > /tmp/phylaxor.yaml
```

## Key Operational Ideas

### Logging Mode Drives RBAC

- `logging.mode=none`: no direct pod log access
- `logging.mode=loki`: future centralized logging path
- `logging.mode=podlogs`: explicit `pods/log` permission

### Service Isolation Matters

- notifier has no Kubernetes RBAC
- enricher is the only component with cluster-observer permissions
- Brain Gateway is an internal service used by decision

### OpenShift Is The Strict Reference

Minikube is useful for iteration, but OpenShift CRC is the environment that validates permission boundaries properly.

## Maintenance Rules

When deployment behavior changes:
- update `docs/PROJECT_CONTEXT.md` if system state changed
- update `docs/DEPLOYMENT_TOPOLOGY.md` if service flow changed
- update `docs/CONTRACT_ENV.md` if Helm-exposed env changed
- update `docs/RBAC_MODEL.md` if permissions changed
