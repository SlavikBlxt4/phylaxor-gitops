#!/bin/bash

set -euo pipefail

APP_NAMESPACE="${APP_NAMESPACE:-phylaxor}"
DB_NAMESPACE="${DB_NAMESPACE:-phylaxor-db}"
RULE_FILE="${RULE_FILE:-../phylaxor-project/yaml-definitions/prometheus-rule-test.yaml}"
TIMEOUT_SECONDS="${TIMEOUT_SECONDS:-180}"
POLL_SECONDS="${POLL_SECONDS:-10}"
ALERTNAME="${ALERTNAME:-PhylaxorRealPipelineTest}"
KEEP_RULE="${KEEP_RULE:-false}"
PROMETHEUS_PROXY_PATH="${PROMETHEUS_PROXY_PATH:-/api/v1/namespaces/openshift-user-workload-monitoring/services/prometheus-user-workload:9091/proxy}"
RUN_ID="${RUN_ID:-phylaxor-$(date -u +%Y%m%d%H%M%S)-${RANDOM}}"
RUN_STARTED_AT=""
BASE_ALERT_ID="0"
BASE_DECISION_ID="0"
TARGET_POD="${TARGET_POD:-}"
RENDERED_RULE=""
RULE_APPLIED="false"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info() { echo -e "${BLUE}[INFO]${NC} $*"; }
log_success() { echo -e "${GREEN}[OK]${NC} $*"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $*"; }
log_error() { echo -e "${RED}[ERR]${NC} $*" >&2; }

require_cmd() {
  if ! command -v "$1" >/dev/null 2>&1; then
    log_error "Command not found: $1"
    exit 1
  fi
}

validate_run_id() {
  if [[ ! "${RUN_ID}" =~ ^[a-z0-9][a-z0-9-]{0,62}$ ]]; then
    log_error "RUN_ID must match ^[a-z0-9][a-z0-9-]{0,62}$"
    exit 1
  fi
}

validate_runtime_inputs() {
  if [[ ! "${ALERTNAME}" =~ ^[A-Za-z0-9_:-]{1,128}$ ]]; then
    log_error "ALERTNAME contains unsupported characters"
    exit 1
  fi
  if [[ ! "${TIMEOUT_SECONDS}" =~ ^[1-9][0-9]*$ || ! "${POLL_SECONDS}" =~ ^[1-9][0-9]*$ ]]; then
    log_error "TIMEOUT_SECONDS and POLL_SECONDS must be positive integers"
    exit 1
  fi
  if [[ "${KEEP_RULE}" != "true" && "${KEEP_RULE}" != "false" ]]; then
    log_error "KEEP_RULE must be true or false"
    exit 1
  fi
}

validate_k8s_name() {
  local value="$1"
  local label="$2"
  if [[ ! "${value}" =~ ^[a-z0-9]([a-z0-9.-]*[a-z0-9])?$ ]]; then
    log_error "${label} is not a safe Kubernetes name"
    exit 1
  fi
}

postgres_pod() {
  oc -n "${DB_NAMESPACE}" get pods --no-headers 2>/dev/null | awk '/^postgres-/{print $1; exit}'
}

psql_query() {
  local sql="$1"
  local pod
  pod="$(postgres_pod)"
  if [[ -z "${pod}" ]]; then
    log_error "Postgres pod not found in namespace ${DB_NAMESPACE}"
    exit 1
  fi
  oc -n "${DB_NAMESPACE}" exec "${pod}" -- psql -U postgres phylaxor -tAc "${sql}"
}

bounded_logs() {
  local deployment="$1"
  local pattern="$2"
  oc -n "${APP_NAMESPACE}" logs "deployment/${deployment}" --since=20m 2>/dev/null \
    | grep -E "${pattern}" \
    | tail -n 40 || true
}

show_diagnostics() {
  set +e
  if [[ -z "${RUN_STARTED_AT}" ]] || ! command -v oc >/dev/null 2>&1; then
    return
  fi
  echo ""
  log_warn "Bounded diagnostics for run_id=${RUN_ID}"
  psql_query "SELECT a.id AS alert_id, d.id AS decision_id, d.path, d.ai_request_id, a.created_at, d.created_at FROM alerts a LEFT JOIN decisions d ON d.alert_id=a.id WHERE a.alertname='${ALERTNAME}' AND a.labels->>'phylaxor_run_id'='${RUN_ID}' ORDER BY a.id DESC, d.id DESC LIMIT 5;"
  psql_query "SELECT id, alert_id, decision_id, request_id, provider, model, input_tokens, output_tokens, latency_ms, created_at FROM ai_usage WHERE alert_id IN (SELECT id FROM alerts WHERE labels->>'phylaxor_run_id'='${RUN_ID}') ORDER BY id DESC LIMIT 5;"
  bounded_logs ingest "run_id=${RUN_ID}|${ALERTNAME}"
  bounded_logs enricher "run_id=${RUN_ID}|${ALERTNAME}"
  bounded_logs decision "brain_|decision_made|notifier_"
  bounded_logs notifier '\[notifier\]'
}

cleanup() {
  local exit_code="$?"
  set +e
  if (( exit_code != 0 )); then
    show_diagnostics
  fi
  if [[ "${RULE_APPLIED}" == "true" && "${KEEP_RULE}" != "true" ]]; then
    oc -n "${APP_NAMESPACE}" delete prometheusrule phylaxor-test-alert --ignore-not-found >/dev/null 2>&1 || true
  elif [[ "${RULE_APPLIED}" == "true" ]]; then
    log_warn "KEEP_RULE=true; leaving PrometheusRule phylaxor-test-alert applied"
  fi
  if [[ -n "${RENDERED_RULE}" && -f "${RENDERED_RULE}" ]]; then
    rm -f "${RENDERED_RULE}"
  fi
  exit "${exit_code}"
}

trap cleanup EXIT

verify_prerequisites() {
  require_cmd oc
  require_cmd python3
  validate_run_id
  validate_runtime_inputs
  validate_k8s_name "${APP_NAMESPACE}" APP_NAMESPACE
  validate_k8s_name "${DB_NAMESPACE}" DB_NAMESPACE

  if ! oc cluster-info >/dev/null 2>&1; then
    log_error "Not connected to an OpenShift/Kubernetes cluster"
    exit 1
  fi
  if [[ ! -f "${RULE_FILE}" ]]; then
    log_error "PrometheusRule template not found: ${RULE_FILE}"
    exit 1
  fi
  if ! oc -n openshift-monitoring get pods | grep -qi alertmanager; then
    log_error "No Alertmanager pods found in openshift-monitoring"
    exit 1
  fi
  if ! oc get ns openshift-user-workload-monitoring >/dev/null 2>&1; then
    log_error "openshift-user-workload-monitoring namespace not found"
    exit 1
  fi
  cat <<EOF

Manual prerequisite:
  In the Alertmanager UI for openshift-monitoring, keep a webhook receiver routing
  alertname=${ALERTNAME}
  to http://ingest.${APP_NAMESPACE}.svc.cluster.local:8080/alert

Run id: ${RUN_ID}
EOF
}

select_target_pod() {
  if [[ -z "${TARGET_POD}" ]]; then
    TARGET_POD="$(oc -n "${APP_NAMESPACE}" get pods -l app=enricher \
      --field-selector=status.phase=Running \
      -o jsonpath='{.items[0].metadata.name}')"
  fi
  if [[ -z "${TARGET_POD}" ]]; then
    log_error "No running enricher pod found in ${APP_NAMESPACE}"
    exit 1
  fi
  validate_k8s_name "${TARGET_POD}" TARGET_POD
  oc -n "${APP_NAMESPACE}" wait --for=condition=Ready "pod/${TARGET_POD}" --timeout=5s >/dev/null
  log_success "Selected real target pod ${APP_NAMESPACE}/${TARGET_POD}"
}

verify_metric_series() {
  local promql encoded response
  promql="kube_pod_status_phase{namespace=\"${APP_NAMESPACE}\",pod=\"${TARGET_POD}\",phase=\"Running\"} == 1"
  encoded="$(python3 -c 'import sys, urllib.parse; print(urllib.parse.quote(sys.argv[1], safe=""))' "${promql}")"
  response="$(oc get --raw "${PROMETHEUS_PROXY_PATH}/api/v1/query?query=${encoded}")"
  python3 -c '
import json, sys
namespace, pod = sys.argv[1:3]
payload = json.load(sys.stdin)
results = payload.get("data", {}).get("result", [])
matching = [r for r in results if r.get("metric", {}).get("namespace") == namespace and r.get("metric", {}).get("pod") == pod]
if payload.get("status") != "success" or len(results) != 1 or len(matching) != 1:
    raise SystemExit(f"expected exactly one matching metric series, got total={len(results)} matching={len(matching)}")
' "${APP_NAMESPACE}" "${TARGET_POD}" <<<"${response}"
  log_success "User-workload Prometheus returned exactly one target series"
}

capture_baseline() {
  RUN_STARTED_AT="$(date -u +'%Y-%m-%dT%H:%M:%SZ')"
  BASE_ALERT_ID="$(psql_query 'SELECT COALESCE(MAX(id),0) FROM alerts;' | tr -d '[:space:]')"
  BASE_DECISION_ID="$(psql_query 'SELECT COALESCE(MAX(id),0) FROM decisions;' | tr -d '[:space:]')"
  [[ "${BASE_ALERT_ID}" =~ ^[0-9]+$ ]] || { log_error "Invalid alert baseline"; exit 1; }
  [[ "${BASE_DECISION_ID}" =~ ^[0-9]+$ ]] || { log_error "Invalid decision baseline"; exit 1; }
  log_info "Baseline alert_id=${BASE_ALERT_ID} decision_id=${BASE_DECISION_ID} started_at=${RUN_STARTED_AT}"
}

render_and_apply_rule() {
  RENDERED_RULE="$(mktemp "${TMPDIR:-/tmp}/phylaxor-rule.XXXXXX.yaml")"
  sed \
    -e "s/__TARGET_NAMESPACE__/${APP_NAMESPACE}/g" \
    -e "s/__TARGET_POD__/${TARGET_POD}/g" \
    -e "s/__RUN_ID__/${RUN_ID}/g" \
    "${RULE_FILE}" > "${RENDERED_RULE}"

  if grep -Eq '__TARGET_NAMESPACE__|__TARGET_POD__|__RUN_ID__' "${RENDERED_RULE}"; then
    log_error "PrometheusRule rendering left unresolved placeholders"
    exit 1
  fi
  oc apply --dry-run=client -f "${RENDERED_RULE}" >/dev/null
  oc apply -f "${RENDERED_RULE}" >/dev/null
  RULE_APPLIED="true"
  log_success "Applied resource-backed PrometheusRule for run_id=${RUN_ID}"
}

wait_for_decision() {
  local waited=0 row
  while (( waited < TIMEOUT_SECONDS )); do
    row="$(psql_query "
      SELECT concat_ws('|', a.id, d.id, d.path, COALESCE(d.ai_request_id,''), a.created_at, d.created_at)
      FROM alerts a
      JOIN decisions d ON d.alert_id = a.id
      WHERE a.alertname = '${ALERTNAME}'
        AND a.labels->>'phylaxor_run_id' = '${RUN_ID}'
        AND a.id > ${BASE_ALERT_ID}
        AND d.id > ${BASE_DECISION_ID}
        AND a.created_at >= '${RUN_STARTED_AT}'::timestamptz
        AND d.created_at >= '${RUN_STARTED_AT}'::timestamptz
      ORDER BY d.id DESC LIMIT 1;
    " | tr -d '\r\n')"
    if [[ -n "${row}" ]]; then
      echo "${row}"
      return 0
    fi
    sleep "${POLL_SECONDS}"
    waited=$((waited + POLL_SECONDS))
  done
  log_error "Timed out waiting for a fresh decision for run_id=${RUN_ID}"
  return 1
}

require_log() {
  local deployment="$1"
  local text="$2"
  if ! oc -n "${APP_NAMESPACE}" logs "deployment/${deployment}" --since-time="${RUN_STARTED_AT}" | grep -F "${text}" >/dev/null; then
    log_error "Missing ${deployment} log marker: ${text}"
    return 1
  fi
}

verify_result() {
  local decision_row="$1"
  local alert_id decision_id path ai_request_id alert_created decision_created
  IFS='|' read -r alert_id decision_id path ai_request_id alert_created decision_created <<<"${decision_row}"

  [[ "${alert_id}" =~ ^[0-9]+$ ]] || { log_error "Invalid alert id in decision row"; return 1; }
  [[ "${decision_id}" =~ ^[0-9]+$ ]] || { log_error "Invalid decision id in decision row"; return 1; }
  if [[ "${path}" != "ai" ]]; then
    log_error "Expected path=ai, got ${path}"
    return 1
  fi
  if [[ -z "${ai_request_id}" ]]; then
    log_error "AI decision has an empty request id"
    return 1
  fi
  if [[ ! "${ai_request_id}" =~ ^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$ ]]; then
    log_error "AI decision returned an invalid request id"
    return 1
  fi

  local context_result
  context_result="$(psql_query "
    SELECT concat_ws('|', context->'alert'->>'namespace', context->'alert'->>'pod', jsonb_typeof(context->'alert'->'podStatus'))
    FROM decisions WHERE id=${decision_id} AND alert_id=${alert_id};
  " | tr -d '\r\n')"
  if [[ "${context_result}" != "${APP_NAMESPACE}|${TARGET_POD}|object" ]]; then
    log_error "Required pod context missing: expected ${APP_NAMESPACE}|${TARGET_POD}|object, got ${context_result:-empty}"
    return 1
  fi

  local usage_row
  usage_row="$(psql_query "
    SELECT concat_ws('|', provider, model, input_tokens, output_tokens, latency_ms, created_at)
    FROM ai_usage
    WHERE request_id='${ai_request_id}' AND alert_id=${alert_id} AND decision_id=${decision_id}
      AND provider IS NOT NULL AND model IS NOT NULL
      AND input_tokens IS NOT NULL AND output_tokens IS NOT NULL
    ORDER BY id DESC LIMIT 1;
  " | tr -d '\r\n')"
  if [[ -z "${usage_row}" ]]; then
    log_error "No fully correlated ai_usage row found"
    return 1
  fi

  require_log ingest "run_id=${RUN_ID}"
  require_log enricher "run_id=${RUN_ID}"
  require_log decision "brain_response request_id=${ai_request_id}"
  require_log decision "decision_made path=ai decision_id=${decision_id}"
  require_log decision "notifier_sent path=ai decision_id=${decision_id}"
  require_log brain-gateway "${ai_request_id}"
  if oc -n "${APP_NAMESPACE}" logs deployment/notifier --since-time="${RUN_STARTED_AT}" | grep -F "dry-run decision_id=${decision_id}" >/dev/null; then
    log_error "Notifier used dry-run for decision_id=${decision_id}"
    return 1
  fi
  require_log notifier "sent decision_id=${decision_id}"

  local provider model input_tokens output_tokens ai_latency usage_created
  IFS='|' read -r provider model input_tokens output_tokens ai_latency usage_created <<<"${usage_row}"
  log_success "OpenShift Alertmanager E2E validation passed"
  echo ""
  echo "Run id:         ${RUN_ID}"
  echo "Target:         ${APP_NAMESPACE}/${TARGET_POD}"
  echo "Alert id:       ${alert_id} (${alert_created})"
  echo "Decision id:    ${decision_id} (${decision_created})"
  echo "AI request id:  ${ai_request_id}"
  echo "AI provider:    ${provider}"
  echo "AI model:       ${model}"
  echo "AI tokens:      input=${input_tokens} output=${output_tokens}"
  echo "AI latency:     ${ai_latency} ms"
  echo "AI usage row:   ${usage_created}"
}

main() {
  verify_prerequisites
  select_target_pod
  verify_metric_series
  capture_baseline
  render_and_apply_rule
  local decision_row
  decision_row="$(wait_for_decision)"
  verify_result "${decision_row}"
}

main "$@"
