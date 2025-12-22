#!/bin/bash

##############################################################################
# End-to-End Test: All Logging Modes (none, loki, podlogs)
# 
# This script:
# 1. Deploys phylaxor for each logging mode
# 2. Triggers an alert via PrometheusRule or manual webhook
# 3. Verifies RBAC permissions for enricher and notifier SAs
# 4. Captures logs and outputs a summary
##############################################################################

set -e

NAMESPACE="phylaxor"
CHART_PATH="./apps/phylaxor"
VALUES_FILE="./apps/phylaxor/values-openshift.yaml"
ENRICHER_SA="system:serviceaccount:${NAMESPACE}:phylaxor-enricher-sa"
NOTIFIER_SA="system:serviceaccount:${NAMESPACE}:phylaxor-notifier-sa"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

# Logging
log_info() { echo -e "${BLUE}[INFO]${NC} $*"; }
log_success() { echo -e "${GREEN}[✓]${NC} $*"; }
log_warn() { echo -e "${YELLOW}[⚠]${NC} $*"; }
log_error() { echo -e "${RED}[✗]${NC} $*"; }
log_section() { echo ""; echo -e "${CYAN}═══════════════════════════════════════════════════════════════${NC}"; echo -e "${CYAN}$1${NC}"; echo -e "${CYAN}═══════════════════════════════════════════════════════════════${NC}"; echo ""; }

##############################################################################
# Utility Functions
##############################################################################

test_rbac_permission() {
  local sa="$1"
  local resource="$2"
  local verb="$3"
  local expected="$4"
  
  result=$(oc -n ${NAMESPACE} auth can-i ${verb} ${resource} --as=${sa} 2>&1)
  
  if [[ ${result} == "yes" ]]; then
    if [[ ${expected} == "yes" ]]; then
      log_success "${sa##*:} can ${verb} ${resource}"
      return 0
    else
      log_error "${sa##*:} CAN ${verb} ${resource} (expected: no)"
      return 1
    fi
  else
    if [[ ${expected} == "no" ]]; then
      log_success "${sa##*:} cannot ${verb} ${resource} (as expected)"
      return 0
    else
      log_error "${sa##*:} CANNOT ${verb} ${resource} (expected: yes)"
      return 1
    fi
  fi
}

deploy_mode() {
  local mode="$1"
  log_section "DEPLOYING MODE: ${mode}"
  
  log_info "Deploying phylaxor chart with logs.mode=${mode}..."
  helm upgrade --install phylaxor ${CHART_PATH} \
    -f ${VALUES_FILE} \
    -n ${NAMESPACE} --create-namespace \
    --set logs.mode=${mode} \
    --wait --timeout 3m 2>&1 | tail -20
  
  log_success "Chart deployed for mode: ${mode}"
  
  log_info "Waiting 10s for pods to stabilize..."
  sleep 10
  
  log_info "Pod status:"
  oc -n ${NAMESPACE} get pods -l app=ingest,app=enricher -o wide
}

trigger_alert_prometheus_rule() {
  log_section "TRIGGERING ALERT VIA PROMETHEUSRULE"
  
  log_info "Applying PrometheusRule (phylaxor-test-2)..."
  if oc apply -f ~/github/phylaxor-project/yaml-definitions/prometheus-rule-test.yaml 2>&1; then
    log_success "PrometheusRule applied"
  else
    log_warn "Could not apply PrometheusRule (Prometheus Operator may not be installed)"
    return 1
  fi
  
  log_info "Waiting 30s for alert to fire..."
  sleep 30
  
  log_info "Checking alert status in Prometheus..."
  oc -n monitoring get prometheusrule phylaxor-test-2 -o yaml 2>/dev/null || log_warn "PrometheusRule not accessible"
}

trigger_alert_manual_webhook() {
  log_section "TRIGGERING ALERT VIA MANUAL WEBHOOK POST"
  
  # Create temporary webhook payload
  cat > /tmp/alert_payload.json << 'EOF'
[
  {
    "receiver": "phylaxor",
    "status": "firing",
    "alerts": [
      {
        "status": "firing",
        "labels": {
          "alertname": "PhylaxorE2ETest",
          "severity": "info",
          "namespace": "phylaxor"
        },
        "annotations": {
          "summary": "E2E Test Alert",
          "description": "Automated end-to-end test alert from e2e_test_all_modes.sh"
        },
        "startsAt": "2025-12-18T00:00:00Z",
        "endsAt": "0001-01-01T00:00:00Z"
      }
    ],
    "groupLabels": {},
    "commonLabels": {},
    "commonAnnotations": {},
    "externalURL": "http://localhost:9093"
  }
]
EOF

  # Get ingest service endpoint
  ingest_ip=$(oc -n ${NAMESPACE} get svc ingest -o jsonpath='{.spec.clusterIP}' 2>/dev/null)
  
  if [[ -z ${ingest_ip} ]]; then
    log_error "Could not find ingest service IP"
    return 1
  fi
  
  ingest_url="http://${ingest_ip}:8080/alert"
  log_info "Sending webhook to: ${ingest_url}"
  
  # Try to POST the alert directly from a pod in the cluster
  oc -n ${NAMESPACE} run webhook-trigger --rm -it --restart=Never \
    --image=curlimages/curl:latest -- \
    curl -s -X POST -H 'Content-Type: application/json' \
    --data @/tmp/alert_payload.json \
    http://ingest.${NAMESPACE}.svc.cluster.local:8080/alert 2>&1 | head -20
  
  log_success "Manual webhook POST sent"
  sleep 5
}

verify_logs_received() {
  local mode="$1"
  
  log_section "VERIFYING ALERT PROCESSING (MODE: ${mode})"
  
  log_info "Ingest logs (last 30 lines):"
  echo "---"
  oc -n ${NAMESPACE} logs -l app=ingest --tail=30 2>/dev/null | tail -20 || log_warn "No ingest logs available"
  echo "---"
  
  log_info "Enricher logs (last 30 lines):"
  echo "---"
  oc -n ${NAMESPACE} logs -l app=enricher --tail=30 2>/dev/null | tail -20 || log_warn "No enricher logs available"
  echo "---"
  
  if [[ ${mode} == "podlogs" ]]; then
    log_info "Searching for pod log fetch attempts in enricher logs..."
    if oc -n ${NAMESPACE} logs -l app=enricher --tail=100 2>/dev/null | grep -i "pod\|log\|fetch" | head -5; then
      log_success "Found pod/log references in enricher logs"
    else
      log_warn "No explicit pod/log fetch messages found (may be successful in background)"
    fi
  fi
}

test_rbac_for_mode() {
  local mode="$1"
  
  log_section "RBAC VERIFICATION (MODE: ${mode})"
  
  rbac_pass=0
  rbac_fail=0
  
  # Enricher tests
  log_info "Testing ENRICHER SA permissions:"
  test_rbac_permission "${ENRICHER_SA}" "pods" "get" "yes" && ((rbac_pass++)) || ((rbac_fail++))
  test_rbac_permission "${ENRICHER_SA}" "events" "list" "yes" && ((rbac_pass++)) || ((rbac_fail++))
  
  # pods/log depends on mode
  if [[ ${mode} == "podlogs" ]]; then
    test_rbac_permission "${ENRICHER_SA}" "pods/log" "get" "yes" && ((rbac_pass++)) || ((rbac_fail++))
  else
    test_rbac_permission "${ENRICHER_SA}" "pods/log" "get" "no" && ((rbac_pass++)) || ((rbac_fail++))
  fi
  
  test_rbac_permission "${ENRICHER_SA}" "secrets" "get" "no" && ((rbac_pass++)) || ((rbac_fail++))
  
  # Notifier tests (must have NO permissions)
  log_info "Testing NOTIFIER SA permissions (must be zero):"
  test_rbac_permission "${NOTIFIER_SA}" "pods" "get" "no" && ((rbac_pass++)) || ((rbac_fail++))
  test_rbac_permission "${NOTIFIER_SA}" "events" "list" "no" && ((rbac_pass++)) || ((rbac_fail++))
  test_rbac_permission "${NOTIFIER_SA}" "pods/log" "get" "no" && ((rbac_pass++)) || ((rbac_fail++))
  test_rbac_permission "${NOTIFIER_SA}" "secrets" "get" "no" && ((rbac_pass++)) || ((rbac_fail++))
  
  log_info "RBAC Results: ${rbac_pass} passed, ${rbac_fail} failed"
  return ${rbac_fail}
}

##############################################################################
# Main Flow
##############################################################################

main() {
  log_section "END-TO-END TEST: ALL LOGGING MODES"
  
  # Verify prerequisites
  log_info "Verifying prerequisites..."
  if ! oc cluster-info &>/dev/null; then
    log_error "Not connected to OpenShift cluster"
    exit 1
  fi
  log_success "Connected to cluster: $(oc config current-context)"
  
  if ! command -v helm &>/dev/null; then
    log_error "Helm not found"
    exit 1
  fi
  log_success "Helm is installed: $(helm version --short)"
  
  # Create namespace
  log_info "Ensuring namespace ${NAMESPACE} exists..."
  oc create namespace ${NAMESPACE} 2>/dev/null || true
  log_success "Namespace ready"
  
  # Summary results
  declare -A results
  
  # ========== MODE 1: NONE ==========
  mode="none"
  deploy_mode ${mode}
  
  # Try PrometheusRule first, fall back to manual webhook
  trigger_alert_prometheus_rule || trigger_alert_manual_webhook
  
  verify_logs_received ${mode}
  rbac_status="PASS"
  test_rbac_for_mode ${mode} || rbac_status="FAIL"
  results[${mode}]="${rbac_status}"
  
  # ========== MODE 2: LOKI ==========
  mode="loki"
  deploy_mode ${mode}
  
  trigger_alert_prometheus_rule || trigger_alert_manual_webhook
  
  verify_logs_received ${mode}
  rbac_status="PASS"
  test_rbac_for_mode ${mode} || rbac_status="FAIL"
  results[${mode}]="${rbac_status}"
  
  # ========== MODE 3: PODLOGS ==========
  mode="podlogs"
  deploy_mode ${mode}
  
  trigger_alert_prometheus_rule || trigger_alert_manual_webhook
  
  verify_logs_received ${mode}
  rbac_status="PASS"
  test_rbac_for_mode ${mode} || rbac_status="FAIL"
  results[${mode}]="${rbac_status}"
  
  # ========== FINAL SUMMARY ==========
  log_section "E2E TEST SUMMARY"
  
  echo -e "${CYAN}Logging Mode Results:${NC}"
  for mode in none loki podlogs; do
    status=${results[${mode}]}
    if [[ ${status} == "PASS" ]]; then
      echo -e "  ${mode}: ${GREEN}${status}${NC}"
    else
      echo -e "  ${mode}: ${RED}${status}${NC}"
    fi
  done
  
  log_info "All microservice SAs deployed and verified:"
  oc -n ${NAMESPACE} get sa -o wide
  
  log_info "Current deployment (logs.mode=podlogs):"
  oc -n ${NAMESPACE} get deployment enricher -o jsonpath='{.spec.template.spec.containers[0].env[?(@.name=="PHYLAXOR_LOGS_MODE")].value}'
  echo ""
  
  log_success "E2E Test Complete!"
  log_info "To inspect further:"
  log_info "  - Enricher: oc -n ${NAMESPACE} logs deployment/enricher -f"
  log_info "  - Ingest: oc -n ${NAMESPACE} logs deployment/ingest -f"
  log_info "  - RBAC check: oc -n ${NAMESPACE} auth can-i get pods/log --as=${ENRICHER_SA}"
}

main "$@"
