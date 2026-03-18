#!/bin/bash

set -euo pipefail

APP_NAMESPACE="${APP_NAMESPACE:-phylaxor}"
DB_NAMESPACE="${DB_NAMESPACE:-phylaxor-db}"
RULE_FILE="${RULE_FILE:-../phylaxor-project/yaml-definitions/prometheus-rule-test.yaml}"
TIMEOUT_SECONDS="${TIMEOUT_SECONDS:-180}"
POLL_SECONDS="${POLL_SECONDS:-10}"
ALERTNAME="${ALERTNAME:-PhylaxorRealPipelineTest}"

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

verify_prerequisites() {
  require_cmd oc

  if ! oc cluster-info >/dev/null 2>&1; then
    log_error "Not connected to a cluster"
    exit 1
  fi

  if [[ ! -f "${RULE_FILE}" ]]; then
    log_error "PrometheusRule file not found: ${RULE_FILE}"
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
  In the Alertmanager UI for openshift-monitoring, create a webhook receiver that routes
  alertname=${ALERTNAME}
  to http://ingest.${APP_NAMESPACE}.svc.cluster.local:8080/alert

This script does not automate UI receiver creation.
EOF
}

apply_rule() {
  log_info "Applying PrometheusRule ${RULE_FILE}"
  oc apply -f "${RULE_FILE}" >/dev/null
  log_success "PrometheusRule applied"
}

wait_for_decision() {
  local waited=0
  while (( waited < TIMEOUT_SECONDS )); do
    local row
    row="$(psql_query "SELECT d.id || '|' || d.path || '|' || COALESCE(d.ai_request_id,'') FROM decisions d JOIN alerts a ON a.id = d.alert_id WHERE a.alertname = '${ALERTNAME}' ORDER BY d.id DESC LIMIT 1;")"
    row="$(echo "${row}" | tr -d '[:space:]')"
    if [[ -n "${row}" ]]; then
      echo "${row}"
      return 0
    fi
    sleep "${POLL_SECONDS}"
    waited=$((waited + POLL_SECONDS))
  done

  log_error "Timed out waiting for alert ${ALERTNAME} to reach Phylaxor"
  exit 1
}

verify_result() {
  local decision_row="$1"
  local decision_id="${decision_row%%|*}"
  local rest="${decision_row#*|}"
  local path="${rest%%|*}"
  local ai_request_id="${decision_row##*|}"

  log_info "Decision row: decision_id=${decision_id} path=${path} ai_request_id=${ai_request_id}"

  if [[ "${path}" != "ai" ]]; then
    log_error "Expected path=ai, got ${path}"
    exit 1
  fi

  local ai_usage_count
  ai_usage_count="$(psql_query "SELECT COUNT(*) FROM ai_usage WHERE request_id='${ai_request_id}';" | tr -d '[:space:]')"
  if [[ -z "${ai_usage_count}" || "${ai_usage_count}" == "0" ]]; then
    log_error "No ai_usage row found for request_id=${ai_request_id}"
    exit 1
  fi

  oc -n "${APP_NAMESPACE}" logs deployment/ingest --since=15m | grep -F "${ALERTNAME}" >/dev/null
  oc -n "${APP_NAMESPACE}" logs deployment/enricher --since=15m | grep -F "alertname=${ALERTNAME}" >/dev/null
  oc -n "${APP_NAMESPACE}" logs deployment/decision --since=15m | grep -F "brain_response request_id=${ai_request_id}" >/dev/null
  oc -n "${APP_NAMESPACE}" logs deployment/decision --since=15m | grep -F "decision_made path=ai decision_id=${decision_id}" >/dev/null

  log_success "OpenShift Alertmanager validation passed"
  echo ""
  echo "Alert name:    ${ALERTNAME}"
  echo "Decision id:   ${decision_id}"
  echo "AI request id: ${ai_request_id}"
}

cleanup_hint() {
  echo ""
  echo "Cleanup:"
  echo "  oc delete -f ${RULE_FILE}"
  echo "  Remove the temporary receiver/matcher from the Alertmanager UI if no longer needed."
}

main() {
  verify_prerequisites
  apply_rule
  decision_row="$(wait_for_decision)"
  verify_result "${decision_row}"
  cleanup_hint
}

main "$@"
