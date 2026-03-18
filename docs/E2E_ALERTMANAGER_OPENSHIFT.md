# OpenShift Alertmanager E2E Validation

This document describes the validation path for a real alert delivered through OpenShift monitoring.

Validated flow:

`PrometheusRule -> Alertmanager -> ingest -> enricher -> decision -> brain-gateway -> notifier -> Telegram`

## Environment-Specific Note

In the current CRC environment:
- `openshift-user-workload-monitoring` is enabled for user metrics and rules
- Alertmanager pods are visible in `openshift-monitoring`
- the practical routing test used a receiver created in the Alertmanager UI

That means this validation is real end to end, but the receiver setup is currently manual in the OpenShift Alertmanager UI.

## Receiver Configuration

Create a webhook receiver in the Alertmanager UI with:

- receiver name: `phylaxor-test`
- receiver type: `Webhook`
- URL: `http://ingest.phylaxor.svc.cluster.local:8080/alert`
- matcher: `alertname = PhylaxorRealPipelineTest`
- send resolved alerts: enabled

## PrometheusRule

The repository includes a working rule at:

- `phylaxor-project/yaml-definitions/prometheus-rule-test.yaml`

It creates a synthetic alert named:

- `PhylaxorRealPipelineTest`

## Repeatable Validation

Run:

```bash
cd phylaxor-gitops
./e2e_alertmanager_openshift.sh
```

This script:
- applies the `PrometheusRule`
- waits for the alert to propagate
- checks `decisions` and `ai_usage` in Postgres
- verifies that the decision path is `ai`
- verifies service logs across the pipeline

## Database Namespace

Application namespace:
- `phylaxor`

Database namespace:
- `phylaxor-db`

Postgres verification must be done in `phylaxor-db`.
