# OpenShift Alertmanager E2E Validation

This test validates a fresh, resource-backed incident through the complete path:

`kube-state-metrics -> PrometheusRule -> Alertmanager -> ingest -> enricher -> decision -> brain-gateway -> OpenAI -> notifier -> Telegram`

It is intentionally stricter than a transport smoke test. A run fails when the alert is stale, pod context is missing, the decision does not use AI, AI usage is not persisted, or Telegram is in dry-run mode.

## Manual Alertmanager Receiver

Keep a webhook receiver in the OpenShift Alertmanager UI with:

- receiver name: `phylaxor-test`
- type: `Webhook`
- URL: `http://ingest.phylaxor.svc.cluster.local:8080/alert`
- matcher: `alertname = PhylaxorRealPipelineTest`
- send resolved alerts: enabled

The matcher remains stable. The runner adds a unique `phylaxor_run_id` label to correlate each invocation.

## Prerequisites

- CRC/OpenShift is running and `oc` is logged in.
- `openshift-user-workload-monitoring` is enabled.
- User-workload Prometheus exposes `kube_pod_status_phase` for the selected Phylaxor pod.
- Application deployments run in `phylaxor`; Postgres runs in `phylaxor-db`.
- Brain Gateway uses a real OpenAI key and `debugMock=false`.
- Notifier has valid Telegram credentials; dry-run does not satisfy this E2E.
- `python3` is available locally for PromQL URL encoding and JSON validation.

The Prometheus service proxy defaults to:

```text
/api/v1/namespaces/openshift-user-workload-monitoring/services/prometheus-user-workload:9091/proxy
```

Override `PROMETHEUS_PROXY_PATH` if the cluster exposes a different service port/path.

## Resource-Backed Fixture

The checked-in template is:

- `phylaxor-project/yaml-definitions/prometheus-rule-test.yaml`

The runner chooses one Ready enricher pod and renders:

- `__TARGET_NAMESPACE__`
- `__TARGET_POD__`
- `__RUN_ID__`

The PromQL query targets exactly that real running pod. It does not crash or restart a workload. Before applying the rule, the runner queries user-workload Prometheus and requires exactly one series with the expected namespace and pod labels.

## Run

```bash
cd phylaxor-gitops
./e2e_alertmanager_openshift.sh
```

Useful overrides:

```bash
RUN_ID=phylaxor-manual-001 KEEP_RULE=true ./e2e_alertmanager_openshift.sh
TARGET_POD=enricher-abc123 ./e2e_alertmanager_openshift.sh
PROMETHEUS_PROXY_PATH=/api/v1/... ./e2e_alertmanager_openshift.sh
```

`RUN_ID` must match `^[a-z0-9][a-z0-9-]{0,62}$`.

## What a Pass Proves

The runner captures initial alert/decision IDs and a UTC start time, then requires a row with:

- `alertname = PhylaxorRealPipelineTest`
- the exact `phylaxor_run_id`
- alert and decision IDs above the captured baselines
- alert and decision timestamps after the run started
- context namespace and pod matching the selected target
- `podStatus` stored as a non-null JSON object
- `path=ai` and a non-empty AI request ID
- an `ai_usage` row matching request ID, alert ID, and decision ID
- correlated markers from ingest, enricher, decision, and Brain Gateway
- `[notifier] sent decision_id=...` for a real Telegram send

Dry-run notification and every non-AI decision path fail.

On success the script prints the run ID, target, alert/decision/request IDs, timestamps, provider, model, token usage, and AI latency.

## Failure Diagnostics

Failures return a non-zero exit code and print bounded diagnostics:

- only database rows associated with the run ID
- at most 40 relevant recent log lines per component
- no Kubernetes Secret reads
- no raw AI response request

The normal Brain Gateway deployment should keep raw response logging disabled; the E2E does not rely on it.

## Cleanup

The rendered local manifest is always removed. By default the runner also deletes only:

```text
PrometheusRule/phylaxor-test-alert in namespace phylaxor
```

Set `KEEP_RULE=true` to leave the rule applied for inspection. Historical alerts, decisions, and AI usage are never deleted to prepare a test; freshness is proven by correlation.

## Current Boundary

This validates direct Pod enrichment because the alert carries real namespace and pod labels. Workload, Node, PVC, namespace-only and cluster target resolution, plus explicit evidence-quality statuses, remain Phase 2 work.
