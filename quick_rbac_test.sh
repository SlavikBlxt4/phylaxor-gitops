#!/bin/bash

# Quick RBAC Test Script - Run this to verify enricher permissions

NAMESPACE="phylaxor"
SA_NAME="phylaxor-sa"
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
  result=$(oc -n ${NAMESPACE} auth can-i $2 $1 --as=${SERVICE_ACCOUNT} 2>&1)
  if [[ ${result} == "yes" ]]; then
    printf "${GREEN}✅${NC} Can $2 $1\n"
  else
    printf "${RED}❌${NC} Cannot $2 $1\n"
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
