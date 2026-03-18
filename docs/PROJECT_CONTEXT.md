# Project Context — Phylaxor (GitOps)

This is the deployment-oriented context document for the GitOps repository.

## Deployment Scope

This repo is responsible for:
- Helm charts for application services
- Helm charts for Postgres and Redis
- values files for Minikube and OpenShift
- per-service ServiceAccounts
- conditional RBAC for enricher log access
- Brain Gateway deployment resources

## Runtime Model

The deployed system includes:
- ingest
- enricher
- decision
- brain-gateway
- notifier
- feedback-gateway
- feedback UI
- Redis
- Postgres

## Current State

What is already represented in GitOps:
- logging modes are exposed through values
- `pods/log` is conditional in RBAC
- Brain Gateway is deployed as a first-class service
- OpenShift and Minikube values are maintained separately
- the core AI path has been validated end to end

What is not finished:
- Loki-backed behavior is still future work
- some docs still lag behind implementation details and are being normalized
- additional hardening like network isolation is still optional

## Security Model Summary

The deployment layer must preserve these rules:

1. notifier has no Kubernetes permissions
2. enricher gets the minimum read-only cluster access needed
3. direct pod log access is granted only for `logging.mode=podlogs`
4. Secret access is not broadened casually
5. OpenShift remains the strict environment for validating RBAC assumptions

## Topology Summary

```text
Alertmanager -> ingest -> Redis -> enricher -> Redis -> decision
decision -> Postgres
decision -> Brain Gateway
decision -> notifier
Telegram -> feedback-gateway -> Postgres
feedback UI -> Postgres
```

See `DEPLOYMENT_TOPOLOGY.md` for the cluster layout.

## Operational Priorities

The most relevant deployment priorities now are:

1. keep Brain Gateway deployment and configuration aligned with the app repo
2. finish the Loki path when ready
3. keep OpenShift-safe RBAC as the default reference
4. keep the validated E2E path easy to rerun

## Reading Order

Read these in order:

1. `README.md`
2. `docs/README.md`
3. `docs/PROJECT_CONTEXT.md`
4. `docs/DEPLOYMENT_TOPOLOGY.md`
5. `docs/CONTRACT_ENV.md`
6. `docs/RBAC_MODEL.md`
