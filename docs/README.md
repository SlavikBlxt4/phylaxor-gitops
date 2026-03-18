# Phylaxor GitOps Docs Map

This directory is the entry point for understanding deployment, Helm, and RBAC.

## Start Here

Read these files in order:

1. `PROJECT_CONTEXT.md`
2. `DEPLOYMENT_TOPOLOGY.md`
3. `CONTRACT_ENV.md`
4. `RBAC_MODEL.md`

That sequence explains:
- what is currently deployed
- how components are connected in-cluster
- which values and env vars drive behavior
- which permissions are intentional and conditional

## Scope

This repository covers:
- Helm charts for application services and database services
- per-service ServiceAccounts
- conditional RBAC for the enricher logging modes
- deployment values for Minikube and OpenShift
- Brain Gateway deployment and service wiring

## Current Focus

The deployment layer already supports:
- the main Phylaxor microservices
- feedback UI and feedback gateway
- logging modes and conditional `pods/log` access
- Brain Gateway as a deployed service

The main remaining work is:
- Loki-backed log retrieval
- deployment hardening and validation of the AI path
- optional GitOps/Argo expansion and network isolation

## Document Guide

Core:
- `PROJECT_CONTEXT.md`: deployment-oriented current state
- `DEPLOYMENT_TOPOLOGY.md`: runtime layout and traffic flow
- `CONTRACT_ENV.md`: Helm-facing env var quick reference
- `RBAC_MODEL.md`: permission model and conditional rules

Reference:
- `VALUES_EXAMPLES.md`: example values for target environments
- `E2E_BRAIN_GATEWAY.md`: repeatable validation of the core AI flow
