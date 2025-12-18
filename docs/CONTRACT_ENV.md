# Configuration Contract — Phylaxor (GitOps)

This document is **identical** to `phylaxor-project/docs/CONTRACT_ENV.md`. It is kept synchronized across both repositories.

See `phylaxor-project/docs/CONTRACT_ENV.md` for the full specification and rationale.

## Environment Variables (MVP) — Quick Reference

| Variable | Type | Default | Required | Use |
|----------|------|---------|----------|-----|
| `PHYLAXOR_LOGS_MODE` | enum | `none` | No | `none` \| `loki` \| `podlogs` |
| `PHYLAXOR_EVENTS_ENABLED` | bool | `true` | No | Enable cluster event fetching |
| `PHYLAXOR_LOGS_MAX_LINES` | int | `500` | No | Max log lines per pod |
| `PHYLAXOR_LOGS_MAX_BYTES` | int | `100000` | No | Max log bytes per event (100 KB) |
| `PHYLAXOR_LOGS_LOOKBACK` | int | `300` | No | Log lookback window (seconds) |
| `PHYLAXOR_LOKI_ENABLED` | bool | `false` | No | Enable Loki backend (placeholder) |
| `PHYLAXOR_LOKI_ENDPOINT` | string | — | If loki mode | Loki query API URL |
| `PHYLAXOR_LOKI_TENANT_ID` | string | — | If loki mode | Loki tenant identifier |
| `PHYLAXOR_LOKI_USERNAME` | string | — | If Loki basic auth | Username for Loki |
| `PHYLAXOR_LOKI_PASSWORD` | string | — | If Loki basic auth | Password for Loki (from Secret) |
| `PHYLAXOR_LOKI_BEARER_TOKEN` | string | — | If Loki bearer auth | Bearer token for Loki (from Secret) |

## Defaults (MVP)

| Variable | Default | Reason |
|----------|---------|--------|
| `PHYLAXOR_LOGS_MODE` | `none` | Safest; zero log exposure risk |
| `PHYLAXOR_EVENTS_ENABLED` | `true` | Events are low-risk; valuable for context |
| `PHYLAXOR_LOGS_MAX_LINES` | `500` | Balance between coverage and size |
| `PHYLAXOR_LOGS_MAX_BYTES` | `100000` | ~100 KB per event; prevents bloat |
| `PHYLAXOR_LOGS_LOOKBACK` | `300` | Most relevant logs within 5 min of alert |
| `PHYLAXOR_LOKI_ENABLED` | `false` | Placeholder; not required for MVP |

## Helm Values Example

In `values.yaml` or `values-minikube.yaml`:

```yaml
# Logging configuration
logging:
  mode: none  # none, loki, or podlogs
  eventsEnabled: true
  maxLines: 500
  maxBytes: 100000
  lookbackSeconds: 300

# Loki integration (placeholder for future)
loki:
  enabled: false
  endpoint: ""
  tenantId: ""
  auth:
    type: none  # none, basicAuth, bearerToken
    username: ""
    password: ""  # From Secret
    bearerToken: ""  # From Secret
```

## In Deployment/StatefulSet

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: phylaxor-enricher
spec:
  template:
    spec:
      containers:
        - name: enricher
          env:
            - name: PHYLAXOR_LOGS_MODE
              value: {{ .Values.logging.mode }}
            - name: PHYLAXOR_EVENTS_ENABLED
              value: {{ .Values.logging.eventsEnabled | quote }}
            - name: PHYLAXOR_LOGS_MAX_LINES
              value: {{ .Values.logging.maxLines | quote }}
            - name: PHYLAXOR_LOGS_MAX_BYTES
              value: {{ .Values.logging.maxBytes | quote }}
            - name: PHYLAXOR_LOGS_LOOKBACK
              value: {{ .Values.logging.lookbackSeconds | quote }}
```

## Full Specification

For complete env var documentation, see **`phylaxor-project/docs/CONTRACT_ENV.md`**.

This file serves as the Helm-focused reference. Both repositories use identical contract.
