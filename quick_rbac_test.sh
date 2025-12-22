#!/bin/bash

# Quick RBAC Test Script - Run this to verify enricher permissions

NAMESPACE="phylaxor"
# Test the enricher service account by default
SA_NAME="phylaxor-enricher-sa"
SERVICE_ACCOUNT="system:serviceaccount:${NAMESPACE}:${SA_NAME}"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m'

echo "╔════════════════════════════════════════════════════════════════╗"
echo "║         Quick RBAC Permission Check for phylaxor-enricher     ║"
echo "╚════════════════════════════════════════════════════════════════╝"
echo ""

test_perm() {
  local resource="$1"
  local verb="$2"
  local base_resource="${resource}"
  local subresource=""
  if [[ "${resource}" == */* ]]; then
    base_resource="${resource%%/*}"
    subresource="${resource#*/}"
  fi

  if [[ -n "${subresource}" ]]; then
    result=$(oc -n ${NAMESPACE} auth can-i ${verb} ${base_resource} --subresource=${subresource} --as=${SERVICE_ACCOUNT} 2>&1)
  else
    result=$(oc -n ${NAMESPACE} auth can-i ${verb} ${base_resource} --as=${SERVICE_ACCOUNT} 2>&1)
  fi
  if [[ ${result} == "yes" ]]; then
    printf "${GREEN}✅${NC} Can ${verb} ${resource}\n"
  else
    printf "${RED}❌${NC} Cannot ${verb} ${resource}\n"
  fi
}

echo "NAMESPACE-SCOPED (phylaxor):"
test_perm "pods" "get"
test_perm "pods" "list"
test_perm "events" "get"
test_perm "events" "list"
test_perm "pods/log" "get"
echo ""

echo "CLUSTER-SCOPED:"
test_perm "nodes" "get"
test_perm "nodes" "list"
test_perm "storageclasses" "get"
test_perm "namespaces" "get"
