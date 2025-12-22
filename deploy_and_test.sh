#!/bin/bash

# ═══════════════════════════════════════════════════════════════════════════
# Phylaxor Deployment & RBAC Testing Script
# ═══════════════════════════════════════════════════════════════════════════
# This script deploys the phylaxor Helm chart and validates all RBAC permissions
# Run this on your remote server (pc-casa) after pulling the latest code

set -e

NAMESPACE="phylaxor"
# Use enricher service account for RBAC validation
SA_NAME="phylaxor-enricher-sa"
SERVICE_ACCOUNT="system:serviceaccount:${NAMESPACE}:${SA_NAME}"
CHART_PATH="./apps/phylaxor"
VALUES_FILE="./apps/phylaxor/values-openshift.yaml"

# Color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo ""
echo "╔════════════════════════════════════════════════════════════════════════════════╗"
echo "║                    Phylaxor Deployment & RBAC Validation                       ║"
echo "╚════════════════════════════════════════════════════════════════════════════════╝"
echo ""

# ═══════════════════════════════════════════════════════════════════════════
# Step 1: Verify Prerequisites
# ═══════════════════════════════════════════════════════════════════════════

echo -e "${BLUE}═══════════════════════════════════════════════════════════════════════════════${NC}"
echo "STEP 1: Verifying Prerequisites"
echo -e "${BLUE}═══════════════════════════════════════════════════════════════════════════════${NC}"
echo ""

# Check if logged in to cluster
if ! oc cluster-info &>/dev/null; then
  echo -e "${RED}❌ Not logged in to OpenShift cluster${NC}"
  echo "Run: oc login -u kubeadmin -p tNRvC-qD8rk-hnRtS-hNMrZ https://api.crc.testing:6443 --insecure-skip-tls-verify=true"
  exit 1
fi
echo -e "${GREEN}✅ Connected to OpenShift cluster${NC}"
echo "   Current context: $(oc config current-context)"
echo ""

# Check if Helm is installed
if ! command -v helm &>/dev/null; then
  echo -e "${RED}❌ Helm is not installed${NC}"
  exit 1
fi
echo -e "${GREEN}✅ Helm is installed${NC}"
echo "   Version: $(helm version --short)"
echo ""

# Check if chart exists
if [ ! -d "${CHART_PATH}" ]; then
  echo -e "${RED}❌ Helm chart not found at ${CHART_PATH}${NC}"
  exit 1
fi
echo -e "${GREEN}✅ Helm chart found at ${CHART_PATH}${NC}"
echo ""

# ═══════════════════════════════════════════════════════════════════════════
# Step 2: Create Namespace
# ═══════════════════════════════════════════════════════════════════════════

echo -e "${BLUE}═══════════════════════════════════════════════════════════════════════════════${NC}"
echo "STEP 2: Creating Namespace"
echo -e "${BLUE}═══════════════════════════════════════════════════════════════════════════════${NC}"
echo ""

if oc get namespace ${NAMESPACE} &>/dev/null; then
  echo -e "${YELLOW}⚠️  Namespace '${NAMESPACE}' already exists${NC}"
else
  echo "Creating namespace: ${NAMESPACE}"
  oc create namespace ${NAMESPACE}
  echo -e "${GREEN}✅ Namespace created${NC}"
fi
echo ""

# ═══════════════════════════════════════════════════════════════════════════
# Step 3: Deploy Helm Chart
# ═══════════════════════════════════════════════════════════════════════════

echo -e "${BLUE}═══════════════════════════════════════════════════════════════════════════════${NC}"
echo "STEP 3: Deploying Phylaxor Helm Chart"
echo -e "${BLUE}═══════════════════════════════════════════════════════════════════════════════${NC}"
echo ""
echo "Command: helm upgrade --install phylaxor ${CHART_PATH} -f ${VALUES_FILE} -n ${NAMESPACE}"
echo ""

helm upgrade --install phylaxor ${CHART_PATH} -f ${VALUES_FILE} -n ${NAMESPACE} \
  --set logging.mode=none \
  --wait --timeout 5m

echo ""
echo -e "${GREEN}✅ Helm chart deployed successfully${NC}"
echo ""

# ═══════════════════════════════════════════════════════════════════════════
# Step 4: Verify RBAC Resources
# ═══════════════════════════════════════════════════════════════════════════

echo -e "${BLUE}═══════════════════════════════════════════════════════════════════════════════${NC}"
echo "STEP 4: Verifying RBAC Resources"
echo -e "${BLUE}═══════════════════════════════════════════════════════════════════════════════${NC}"
echo ""

echo "Role in namespace (${NAMESPACE}):"
oc -n ${NAMESPACE} get role phylaxor-enricher-role -o wide || echo "  (not yet deployed)"
echo ""

echo "RoleBinding in namespace (${NAMESPACE}):"
oc -n ${NAMESPACE} get rolebinding phylaxor-enricher-rb -o wide || echo "  (not yet deployed)"
echo ""

echo "ClusterRole:"
oc get clusterrole phylaxor-read-cluster -o wide || echo "  (not yet deployed)"
echo ""

echo "ClusterRoleBinding:"
oc get clusterrolebinding phylaxor-read-cluster-binding -o wide || echo "  (not yet deployed)"
echo ""

# ═══════════════════════════════════════════════════════════════════════════
# Step 5: Test RBAC Permissions
# ═══════════════════════════════════════════════════════════════════════════

echo -e "${BLUE}═══════════════════════════════════════════════════════════════════════════════${NC}"
echo "STEP 5: Testing RBAC Permissions"
echo -e "${BLUE}═══════════════════════════════════════════════════════════════════════════════${NC}"
echo ""
echo "ServiceAccount: ${SERVICE_ACCOUNT}"
echo ""

# Function to test permission
test_permission() {
  local resource=$1
  local verb=$2
  local expected=$3
  local scope=$4
  
  result=$(oc -n ${NAMESPACE} auth can-i ${verb} ${resource} --as=${SERVICE_ACCOUNT} 2>&1)
  
  if [[ ${result} == "yes" ]]; then
    if [[ ${expected} == "yes" ]]; then
      printf "%-40s %-10s ${GREEN}✅ YES${NC}\n" "${resource}" "${verb}"
      return 0
    else
      printf "%-40s %-10s ${RED}❌ YES (unexpected)${NC}\n" "${resource}" "${verb}"
      return 1
    fi
  else
    if [[ ${expected} == "no" ]]; then
      printf "%-40s %-10s ${GREEN}✅ NO (as expected)${NC}\n" "${resource}" "${verb}"
      return 0
    else
      printf "%-40s %-10s ${RED}❌ NO (missing permission)${NC}\n" "${resource}" "${verb}"
      return 1
    fi
  fi
}

echo "NAMESPACE-SCOPED PERMISSIONS (phylaxor):"
echo "────────────────────────────────────────────────────────────────────────────────"
test_permission "pods" "get" "yes"
test_permission "pods" "list" "yes"
test_permission "pods" "watch" "yes"
test_permission "events" "get" "yes"
test_permission "events" "list" "yes"
test_permission "events" "watch" "yes"
test_permission "pods/log" "get" "no"  # Should fail for logging.mode=none
echo ""

echo "CLUSTER-SCOPED PERMISSIONS:"
echo "────────────────────────────────────────────────────────────────────────────────"
test_permission "nodes" "get" "yes"
test_permission "nodes" "list" "yes"
test_permission "storageclasses" "get" "yes"
test_permission "storageclasses" "list" "yes"
test_permission "namespaces" "get" "yes"
test_permission "namespaces" "list" "yes"
echo ""

# ═══════════════════════════════════════════════════════════════════════════
# Step 6: Verify Enricher Pod
# ═══════════════════════════════════════════════════════════════════════════

echo -e "${BLUE}═══════════════════════════════════════════════════════════════════════════════${NC}"
echo "STEP 6: Verifying Enricher Pod Status"
echo -e "${BLUE}═══════════════════════════════════════════════════════════════════════════════${NC}"
echo ""

echo "Enricher pods:"
oc -n ${NAMESPACE} get pods -l app=enricher -o wide || echo "  (not yet running)"
echo ""

echo "Enricher pod logs (last 50 lines):"
oc -n ${NAMESPACE} logs -l app=enricher --tail=50 2>/dev/null || echo "  (no logs yet)"
echo ""

# ═══════════════════════════════════════════════════════════════════════════
# Step 7: Summary
# ═══════════════════════════════════════════════════════════════════════════

echo -e "${BLUE}═══════════════════════════════════════════════════════════════════════════════${NC}"
echo "DEPLOYMENT COMPLETE"
echo -e "${BLUE}═══════════════════════════════════════════════════════════════════════════════${NC}"
echo ""
echo -e "${GREEN}✅ Phylaxor has been deployed successfully!${NC}"
echo ""
echo "Useful commands for monitoring:"
echo "  • View all resources:        oc -n ${NAMESPACE} get all"
echo "  • View RBAC:                 oc -n ${NAMESPACE} get role,rolebinding"
echo "  • View enricher logs:        oc -n ${NAMESPACE} logs -f deployment/enricher"
echo "  • Test permissions:          oc -n ${NAMESPACE} auth can-i list pods --as=${SERVICE_ACCOUNT}"
echo "  • Describe pod:              oc -n ${NAMESPACE} describe pod -l app=enricher"
echo ""
echo "To test with different logging modes:"
echo "  helm upgrade phylaxor ${CHART_PATH} -f ${VALUES_FILE} -n ${NAMESPACE} --set logging.mode=podlogs"
echo "  helm upgrade phylaxor ${CHART_PATH} -f ${VALUES_FILE} -n ${NAMESPACE} --set logging.mode=loki"
echo ""
