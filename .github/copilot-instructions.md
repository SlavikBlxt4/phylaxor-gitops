# Copilot Instructions — Phylaxor GitOps

This file contains instructions for GitHub Copilot and other AI agents working on the Phylaxor GitOps (Helm/Argo) repository.

## Critical Context Documents

**Read these in order before suggesting changes to RBAC, Helm templates, or deployments:**

1. **`docs/PROJECT_CONTEXT.md`** — Global project goals, microservices, current state
2. **`docs/CONTRACT_ENV.md`** — Environment variable contract (logging modes)
3. **`docs/RBAC_MODEL.md`** — RBAC implementation and conditional permissions
4. **`docs/VALUES_EXAMPLES.md`** — Helm values for different scenarios (Minikube, CRC, Loki)
5. **`docs/DEPLOYMENT_TOPOLOGY.md`** — Namespace layout, services, network topology

Also read from application repo (`phylaxor-project/`):
- **`docs/SECURITY_MODEL.md`** — Security boundaries and principles
- **`docs/LOGGING_MODES.md`** — Deep analysis of logging modes

These documents are the **single source of truth**. They override any assumptions or history.

---

## Non-Negotiables (MUST follow)

### 1. Never Grant Secrets Permission by Default
- **Rule**: Do NOT add `secrets` to any ClusterRole or Role
- **Exception**: Only if explicitly approved via GitHub issue + security review
- **Action**: If a feature requires secret access, propose it in `docs/RBAC_MODEL.md` first

```yaml
# WRONG: Never do this
rules:
  - apiGroups: [""]
    resources: ["secrets"]
    verbs: ["get", "list"]  # ❌ Don't add

# RIGHT: No secrets permission
rules:
  - apiGroups: [""]
    resources: ["pods", "events"]
    verbs: ["get", "list"]
```

### 2. pods/log Permission Only If PHYLAXOR_LOGS_MODE=podlogs
- **Rule**: `pods/log` ClusterRoleBinding must be **conditional** in Helm
- **Implementation**: Use `{{- if eq .Values.logging.mode "podlogs" }}`
- **Default**: `logging.mode: none` (no pods/log binding)

```yaml
# RIGHT: Conditional binding
{{- if eq .Values.logging.mode "podlogs" }}
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: phylaxor-log-reader
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: phylaxor-log-reader
subjects:
  - kind: ServiceAccount
    name: phylaxor-enricher
    namespace: {{ .Release.Namespace }}
{{- end }}
```

### 3. Notifier Must Have ZERO Kubernetes RBAC
- **Rule**: Notifier ServiceAccount has no ClusterRole/Role binding
- **Verification**: Verify `notifier` is NOT in any RBAC rules
- **Why**: If notifier is compromised, attacker cannot access cluster

```yaml
# WRONG: Don't bind notifier to any role
subjects:
  - kind: ServiceAccount
    name: phylaxor-notifier  # ❌ Never add this
    namespace: phylaxor

# RIGHT: Notifier is a separate SA with no bindings
apiVersion: v1
kind: ServiceAccount
metadata:
  name: phylaxor-notifier
  namespace: phylaxor
# No ClusterRoleBinding or RoleBinding
```

### 4. No Wildcard RBAC Rules
- **Rule**: Never use `*` for `resources` or `verbs`
- **Pattern**: List exact resources and verbs needed

```yaml
# WRONG: Too broad
rules:
  - apiGroups: ["*"]
    resources: ["*"]
    verbs: ["*"]

# RIGHT: Specific resources and verbs
rules:
  - apiGroups: [""]
    resources: ["pods"]
    verbs: ["get", "list"]
  - apiGroups: [""]
    resources: ["nodes"]
    verbs: ["get", "list"]
```

### 5. Baseline Observer Only (No Secrets, No Write)
- **Rule**: Default enricher ClusterRole includes observer resources (pods, nodes, events, etc.), but **not** secrets or write permissions
- **Verification**: Approved list:
  - `pods` (get, list)
  - `nodes` (get, list)
  - `events` (get, list)
  - `namespaces` (get, list)
  - `storageclasses` (get, list)
  - `pods/log` (get) — **only if mode=podlogs**

```yaml
# RIGHT: Baseline observer role
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: phylaxor-observer
rules:
  - apiGroups: [""]
    resources: ["pods"]
    verbs: ["get", "list"]
  - apiGroups: [""]
    resources: ["nodes"]
    verbs: ["get", "list"]
  - apiGroups: [""]
    resources: ["events"]
    verbs: ["get", "list"]
  - apiGroups: [""]
    resources: ["namespaces"]
    verbs: ["get", "list"]
  - apiGroups: ["storage.k8s.io"]
    resources: ["storageclasses"]
    verbs: ["get", "list"]
  # No secrets, no write permissions, no pods/log (conditional elsewhere)
```

### 6. Each Component Gets Its Own ServiceAccount
- **Rule**: Never use `default` ServiceAccount
- **Pattern**: One ServiceAccount per component (ingest, enricher, decision, notifier, etc.)

```yaml
# RIGHT: Separate ServiceAccounts
apiVersion: v1
kind: ServiceAccount
metadata:
  name: phylaxor-ingest
---
apiVersion: v1
kind: ServiceAccount
metadata:
  name: phylaxor-enricher
---
apiVersion: v1
kind: ServiceAccount
metadata:
  name: phylaxor-notifier
```

---

## Helm Template Guidelines

### 1. Use Conditional Logic for Security-Sensitive Features
```yaml
# Example: pods/log only if enabled
{{- if eq .Values.logging.mode "podlogs" }}
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: phylaxor-log-reader
{{- end }}
```

### 2. Reference ServiceAccounts Correctly in Deployments
```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: phylaxor-enricher
spec:
  template:
    spec:
      serviceAccountName: phylaxor-enricher  # Correct reference
```

### 3. Pass Env Vars from Helm Values
```yaml
# In values.yaml
logging:
  mode: none
  maxLines: 500

# In deployment template
env:
  - name: PHYLAXOR_LOGS_MODE
    value: {{ .Values.logging.mode }}
  - name: PHYLAXOR_LOGS_MAX_LINES
    value: {{ .Values.logging.maxLines | quote }}
```

### 4. Use Helm Built-in Functions for Templating
```yaml
# RIGHT: Use Helm functions
{{- if eq .Values.logging.mode "loki" }}
# Loki-specific config
{{- end }}

# RIGHT: Quote numeric values passed as env vars
value: {{ .Values.logging.maxLines | quote }}

# RIGHT: Use proper indentation for multi-line YAML
- name: CONFIG
  value: |
    key1: value1
    key2: value2
```

### 5. Document Custom Values
```yaml
# values.yaml
# Logging mode: 'none' (default, safest), 'loki' (enterprise), 'podlogs' (testing)
logging:
  mode: none  # Valid values: none, loki, podlogs
  eventsEnabled: true
  maxLines: 500  # Log lines per pod

# RBAC: Whether to create ServiceAccounts and ClusterRoles
rbac:
  create: true  # Should be true (creates necessary RBAC)
```

---

## Values File Guidelines

### Defaults (MVP)

```yaml
# In values.yaml - the defaults should be the SAFEST options
logging:
  mode: none  # Default safe mode (no logs)
  eventsEnabled: true
  maxLines: 500
  maxBytes: 100000
  lookbackSeconds: 300

rbac:
  create: true  # Always create RBAC

notifier:
  telegra:
    enabled: false  # Disable by default (require explicit config)
```

### Environment-Specific Files

- **`values-minikube.yaml`** — Development (Minikube), loose resources
- **`values-openshift.yaml`** — Enterprise simulation (CRC), tight RBAC
- **`values-openshift-loki.yaml`** — Future: Loki integration (placeholder)

See `docs/VALUES_EXAMPLES.md` for complete examples.

---

## Don't Do (Anti-Patterns)

### ❌ Don't Grant pods/log Unconditionally
```yaml
# WRONG: Always grants pods/log (unsafe default)
rules:
  - apiGroups: [""]
    resources: ["pods/log"]
    verbs: ["get"]
```

### ❌ Don't Use default ServiceAccount
```yaml
# WRONG: Uses default SA
apiVersion: apps/v1
kind: Deployment
spec:
  template:
    spec:
      # serviceAccountName not specified → defaults to "default"
```

### ❌ Don't Add Notifier to Any RBAC Binding
```yaml
# WRONG: Gives notifier kube permissions
subjects:
  - kind: ServiceAccount
    name: phylaxor-notifier
    namespace: phylaxor
```

### ❌ Don't Use Wildcards in RBAC
```yaml
# WRONG: Too permissive
rules:
  - apiGroups: ["*"]
    resources: ["*"]
    verbs: ["*"]
```

### ❌ Don't Store Secrets in ConfigMaps
```yaml
# WRONG: Secret in ConfigMap (exposed)
apiVersion: v1
kind: ConfigMap
data:
  loki_password: "mysecret"
```

### ❌ Don't Implement CRDs or Operators Yet
- Stay with Deployments + env vars (MVP)
- CRDs can be added later when contract is stable

---

## Testing RBAC in Helm

Before committing RBAC changes:

### Test 1: Verify Template Renders
```bash
helm template phylaxor ./apps/phylaxor -f values-minikube.yaml | grep -A 5 "ClusterRoleBinding"
# Should show phylaxor-observer binding, NO pods/log binding (mode=none)
```

### Test 2: Verify Conditional Logic
```bash
# With mode=podlogs (should include pods/log binding)
helm template phylaxor ./apps/phylaxor -f values-minikube.yaml \
  --set logging.mode=podlogs | grep "phylaxor-log-reader"
# Should find phylaxor-log-reader binding

# With mode=none (should NOT include pods/log binding)
helm template phylaxor ./apps/phylaxor -f values-minikube.yaml \
  --set logging.mode=none | grep "phylaxor-log-reader"
# Should find nothing (binding not rendered)
```

### Test 3: Deploy and Verify
```bash
# On Minikube
helm install phylaxor ./apps/phylaxor -f values-minikube.yaml -n phylaxor --create-namespace

# Check bindings
kubectl get clusterrolebinding | grep phylaxor

# Verify notifier has NO bindings
kubectl get clusterrolebinding,rolebinding | grep notifier
# Should find nothing
```

---

## Checklist for RBAC Changes

Before merging any RBAC-related changes:

- [ ] No `secrets` permission added (only if explicitly approved)
- [ ] `pods/log` binding is **conditional** (only if mode=podlogs)
- [ ] Notifier has **zero** RBAC bindings
- [ ] No wildcard rules (`*` for resources or verbs)
- [ ] Each component has its own ServiceAccount (not default)
- [ ] Baseline observer role includes only approved resources
- [ ] Changes documented in `docs/RBAC_MODEL.md`
- [ ] Template renders correctly (helm template test)
- [ ] Tested on both Minikube and CRC
- [ ] Verified on CRC with strict RBAC enforcement

---

## When to Ask for Help

Before implementing Helm/RBAC changes, check with maintainers if:

1. **Adding a new permission to a role** → Explain why in PR
2. **Changing the RBAC model** → Update `docs/RBAC_MODEL.md` first
3. **Adding a new Helm value** → Document in `docs/VALUES_EXAMPLES.md`
4. **Creating a new component** → Verify it follows RBAC guidelines
5. **Changing logging mode behavior** → Ensure conditional Helm logic is correct

---

## Related Documents

- **`docs/PROJECT_CONTEXT.md`** — Project architecture and components
- **`docs/CONTRACT_ENV.md`** — Env var contract (logging modes)
- **`docs/RBAC_MODEL.md`** — RBAC implementation and templates
- **`docs/VALUES_EXAMPLES.md`** — Helm values for all scenarios
- **`docs/DEPLOYMENT_TOPOLOGY.md`** — Namespace layout and services
- **`phylaxor-project/docs/SECURITY_MODEL.md`** — Application-level security

---

## Quick Reference

| Issue | Check This | Action |
|-------|-----------|--------|
| "Can we add Secrets permission?" | `docs/RBAC_MODEL.md` | Don't add unless approved |
| "How do I conditionally grant pods/log?" | `docs/RBAC_MODEL.md` (examples) | Use `{{- if eq .Values.logging.mode "podlogs" }}` |
| "What permissions does enricher need?" | `docs/RBAC_MODEL.md` | Observer role + conditional pods/log |
| "What permissions for notifier?" | `docs/RBAC_MODEL.md` | **NONE** (critical!) |
| "What Helm values should I add?" | `docs/VALUES_EXAMPLES.md` | Follow Minikube/CRC examples |
| "How to test RBAC changes?" | Section above | Use helm template + kubectl verify |

