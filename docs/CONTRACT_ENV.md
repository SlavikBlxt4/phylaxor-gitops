# Configuration Contract — Phylaxor (GitOps)

This is the Helm-facing quick reference for the application environment contract.

The full contract lives in `../../phylaxor-project/docs/CONTRACT_ENV.md`.

## Enricher Logging Variables

| Variable | Default | Purpose |
|----------|---------|---------|
| `PHYLAXOR_LOGS_MODE` | `none` | `none`, `loki`, or `podlogs` |
| `PHYLAXOR_EVENTS_ENABLED` | `true` | enable event enrichment |
| `PHYLAXOR_LOGS_MAX_LINES` | `500` | max tailed log lines |
| `PHYLAXOR_LOGS_MAX_BYTES` | `100000` | max log payload size |
| `PHYLAXOR_LOGS_LOOKBACK` | `300` | log lookback window in seconds |
| `PHYLAXOR_LOGS_TIMEOUT` | `5` | log fetch timeout in seconds |

## Loki Variables

| Variable | Default | Purpose |
|----------|---------|---------|
| `PHYLAXOR_LOKI_ENABLED` | `false` | future Loki path toggle |
| `PHYLAXOR_LOKI_ENDPOINT` | empty | Loki endpoint |
| `PHYLAXOR_LOKI_TENANT_ID` | empty | Loki tenant |
| `PHYLAXOR_LOKI_USERNAME` | empty | basic auth username |
| `PHYLAXOR_LOKI_PASSWORD` | empty | basic auth password |
| `PHYLAXOR_LOKI_BEARER_TOKEN` | empty | bearer token |

## Brain Gateway Variables

| Variable | Default | Purpose |
|----------|---------|---------|
| `BRAIN_GATEWAY_URL` | app-defined | internal Brain Gateway base URL |
| `BRAIN_GATEWAY_TIMEOUT_SECONDS` | `20` | request timeout |
| `BRAIN_GATEWAY_MAX_RETRIES` | `2` | retry count for transient failures |
| `BRAIN_GATEWAY_RETRY_BACKOFF_MS` | `250` | retry backoff |
| `BRAIN_GATEWAY_MAX_OUTPUT_TOKENS` | `1024` | AI output budget |
| `PHYLAXOR_BRAIN_DEBUG_RAW` | `false` | log raw model output |
| `PHYLAXOR_BRAIN_DEBUG_MOCK` | `false` | return mock AI responses |

## Helm Values Shape

The chart currently exposes at least:

```yaml
logging:
  mode: none
  eventsEnabled: true
  maxLines: 500
  maxBytes: 100000
  lookbackSeconds: 300
  timeout: 5

brainGateway:
  debugRaw: false
  debugMock: false
```

## Rule

When Helm starts exposing a new application env var, update this file and the app-repo contract together.
