#!/bin/bash

set -euo pipefail

APP_NAMESPACE="${APP_NAMESPACE:-phylaxor}"
DB_NAMESPACE="${DB_NAMESPACE:-phylaxor-db}"
RELEASE_NAME="${RELEASE_NAME:-phylaxor}"
CHART_PATH="${CHART_PATH:-./apps/phylaxor}"
VALUES_FILE="${VALUES_FILE:-./apps/phylaxor/values-openshift.yaml}"
TIMEOUT_SECONDS="${TIMEOUT_SECONDS:-120}"
POLL_SECONDS="${POLL_SECONDS:-5}"
ALERTNAME="${ALERTNAME:-PhylaxorBrainGatewayE2E-$(date +%s)}"

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

wait_for_rollout() {
  local deployment="$1"
  oc -n "${APP_NAMESPACE}" rollout status "deployment/${deployment}" --timeout=180s >/dev/null
}

verify_prerequisites() {
  require_cmd oc
  require_cmd helm

  if ! oc cluster-info >/dev/null 2>&1; then
    log_error "Not connected to an OpenShift/Kubernetes cluster"
    exit 1
  fi

  if [[ ! -d "${CHART_PATH}" ]]; then
    log_error "Chart path not found: ${CHART_PATH}"
    exit 1
  fi

  log_success "Connected to cluster: $(oc config current-context)"
}

deploy_app() {
  log_info "Deploying ${RELEASE_NAME} in namespace ${APP_NAMESPACE}"
  helm upgrade --install "${RELEASE_NAME}" "${CHART_PATH}" \
    -f "${VALUES_FILE}" \
    -n "${APP_NAMESPACE}" \
    --create-namespace \
    --set namespaceCreate=false \
    --wait --timeout 5m >/dev/null

  wait_for_rollout ingest
  wait_for_rollout enricher
  wait_for_rollout decision
  wait_for_rollout brain-gateway
  wait_for_rollout notifier

  log_success "Application deployments are ready"
}

trigger_alert() {
  local target_pod
  target_pod="$(oc -n "${APP_NAMESPACE}" get pod -l app=enricher -o jsonpath='{.items[0].metadata.name}')"
  if [[ -z "${target_pod}" ]]; then
    log_error "Could not determine a target pod for the alert"
    exit 1
  fi

  log_info "Triggering alert ${ALERTNAME} against ingest"

  cat <<EOF | oc -n "${APP_NAMESPACE}" run webhook-trigger --rm -i --restart=Never \
    --image=curlimages/curl:latest -- \
    sh -c "cat >/tmp/payload.json && curl -sS -X POST http://ingest.${APP_NAMESPACE}.svc.cluster.local:8080/alert -H 'Content-Type: application/json' --data @/tmp/payload.json"
{
  "alerts": [
    {
      "status": "firing",
      "startsAt": "$(date -u +"%Y-%m-%dT%H:%M:%SZ")",
      "labels": {
        "alertname": "${ALERTNAME}",
        "severity": "warning",
        "namespace": "${APP_NAMESPACE}",
        "pod": "${target_pod}"
      },
      "annotations": {
        "summary": "Brain Gateway E2E validation",
        "description": "Automated E2E validation for alert -> AI -> Telegram"
      }
    }
  ]
}
EOF

  log_success "Alert submitted"
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

  log_error "Timed out waiting for decision row for alert ${ALERTNAME}"
  exit 1
}

verify_logs_and_db() {
  local decision_row="$1"
  local decision_id="${decision_row%%|*}"
  local rest="${decision_row#*|}"
  local path="${rest%%|*}"
  local ai_request_id="${decision_row##*|}"

  log_info "Decision row: decision_id=${decision_id} path=${path} ai_request_id=${ai_request_id}"

  if [[ "${path}" != "ai" ]]; then
    log_error "Expected decision path=ai but got ${path}"
    psql_query "SELECT d.id, d.path, d.reason, d.ai_request_id FROM decisions d JOIN alerts a ON a.id = d.alert_id WHERE a.alertname = '${ALERTNAME}' ORDER BY d.id DESC LIMIT 5;"
    exit 1
  fi

  if [[ -z "${ai_request_id}" ]]; then
    log_error "Decision path is ai but ai_request_id is empty"
    exit 1
  fi

  local ai_usage_count
  ai_usage_count="$(psql_query "SELECT COUNT(*) FROM ai_usage WHERE request_id = '${ai_request_id}';" | tr -d '[:space:]')"
  if [[ "${ai_usage_count}" == "0" || -z "${ai_usage_count}" ]]; then
    log_error "No ai_usage row found for request_id=${ai_request_id}"
    exit 1
  fi

  oc -n "${APP_NAMESPACE}" logs deployment/ingest --since=10m | grep -F "${ALERTNAME}" >/dev/null
  oc -n "${APP_NAMESPACE}" logs deployment/enricher --since=10m | grep -F "alertname=${ALERTNAME}" >/dev/null
  oc -n "${APP_NAMESPACE}" logs deployment/decision --since=10m | grep -F "brain_response request_id=${ai_request_id}" >/dev/null
  oc -n "${APP_NAMESPACE}" logs deployment/decision --since=10m | grep -F "decision_made path=ai decision_id=${decision_id}" >/dev/null
  oc -n "${APP_NAMESPACE}" logs deployment/decision --since=10m | grep -F "notifier_sent path=ai decision_id=${decision_id}" >/dev/null
  oc -n "${APP_NAMESPACE}" logs deployment/brain-gateway --since=10m | grep -F "${ai_request_id}" >/dev/null

  if oc -n "${APP_NAMESPACE}" logs deployment/notifier --since=10m | grep -F "sent decision_id=${decision_id}" >/dev/null; then
    log_success "Notifier sent the Telegram message"
  elif oc -n "${APP_NAMESPACE}" logs deployment/notifier --since=10m | grep -F "dry-run decision_id=${decision_id}" >/dev/null; then
    log_warn "Notifier is in dry-run mode; Telegram delivery not verified, but decision handoff is correct"
  else
    log_error "Notifier did not log a send or dry-run for decision_id=${decision_id}"
    exit 1
  fi

  log_success "Database and log verification passed"
  echo ""
  echo "Alert name:      ${ALERTNAME}"
  echo "Decision id:     ${decision_id}"
  echo "AI request id:   ${ai_request_id}"
  echo "Postgres ns:     ${DB_NAMESPACE}"
  echo ""
  psql_query "SELECT d.id, d.path, d.rule_id, d.reason, d.ai_request_id, a.alertname FROM decisions d JOIN alerts a ON a.id = d.alert_id WHERE d.id = ${decision_id};"
}

main() {
  verify_prerequisites
  deploy_app
  trigger_alert
  decision_row="$(wait_for_decision)"
  verify_logs_and_db "${decision_row}"
  log_success "Brain Gateway E2E validation completed successfully"
}

main "$@"
