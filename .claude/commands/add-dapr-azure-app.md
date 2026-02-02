---
description: Add Azure Workload Identity enabled Dapr configuration for a new app
---

You are helping the user configure a new application with Azure Workload Identity enabled Dapr integration. This includes Azure App Configuration for dynamic config and Azure Key Vault for secrets.

# Dapr + Azure Workload Identity Integration Workflow

This command automates the complete workflow for adding Azure-integrated Dapr configuration to an application in the stacks repo.

## Prerequisites

Before starting, verify:
1. Azure infrastructure is bootstrapped (`scripts/00-bootstrap-azure-infra.sh`)
2. The stacks repo is available at `/home/vpittamp/repos/PittampalliOrg/stacks/main`
3. The app already has basic Kubernetes manifests (Namespace, Deployment, Service)

## Step 1: Gather Required Information

Ask the user for:

1. **App Name** (required)
   - Example: "planner-agent", "workflow-builder", "my-new-app"
   - Must be lowercase, alphanumeric with hyphens
   - Used for namespace, ServiceAccount, Dapr app-id, and App Config label

2. **Namespace** (default: same as app name)
   - Kubernetes namespace where the app will run

3. **ServiceAccount Name** (default: same as app name)
   - The Kubernetes ServiceAccount for Workload Identity

4. **Redis Host** (default: `redis.{namespace}.svc.cluster.local:6379`)
   - Redis endpoint for Dapr state stores and pub/sub

5. **Required Dapr Components** (multi-select)
   - `statestore` - Redis state store with actor support
   - `pubsub` - Redis pub/sub messaging
   - `azureappconfig` - Azure App Configuration
   - `secrets` - External Secrets from Key Vault

## Step 2: Add Federated Credential

Add the app's ServiceAccount to the bootstrap script for Azure Workload Identity:

**File:** `stacks/main/scripts/00-bootstrap-azure-infra.sh`

```bash
# Find the SA_CONFIGS array and add the new app
setup_federated_credentials() {
    print_header "Setting Up Federated Identity Credentials"

    local -a SA_CONFIGS=(
        "external-secrets:external-secrets"
        "mcp-tools:acr-sa"
        "kargo:acr-sa"
        "ai-chatbot:ai-chatbot"
        "planner-agent:planner-dapr-agent"
        "{NAMESPACE}:{SERVICE_ACCOUNT_NAME}"  # ADD THIS LINE
    )
```

**Search command:**
```bash
grep -n "SA_CONFIGS=(" /home/vpittamp/repos/PittampalliOrg/stacks/main/scripts/00-bootstrap-azure-infra.sh
```

After modifying, run the bootstrap script to create the federated credential:
```bash
cd /home/vpittamp/repos/PittampalliOrg/stacks/main/scripts
./00-bootstrap-azure-infra.sh --update-issuer
```

## Step 3: Create ServiceAccount with Workload Identity

**File:** `stacks/main/packages/components/active-development/manifests/{app-name}/ServiceAccount-{app-name}.yaml`

```yaml
apiVersion: v1
kind: ServiceAccount
metadata:
  name: {SERVICE_ACCOUNT_NAME}
  namespace: {NAMESPACE}
  labels:
    app.kubernetes.io/managed-by: kustomize
    app.kubernetes.io/name: {APP_NAME}
  annotations:
    # Azure Workload Identity - MUST match values from bootstrap script
    azure.workload.identity/client-id: "1140d9c2-62f6-4857-94c2-7e0e6c64e562"
    azure.workload.identity/tenant-id: "0c4da9c5-40ea-4e7d-9c7a-e7308d4f8e38"
```

**Get the correct values from:**
```bash
cat /home/vpittamp/repos/PittampalliOrg/stacks/main/scripts/.env | grep -E "AZURE_CLIENT_ID|AZURE_TENANT_ID"
```

## Step 4: Add Dapr + Azure Integration Component

Update the app's kustomization to use the reusable component:

**File:** `stacks/main/packages/components/active-development/manifests/{app-name}/kustomization.yaml`

```yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization

# Use the reusable Dapr + Azure integration component
components:
  - ../../../dapr-azure-integration
  - ../../../dapr-azure-integration/azure-app-config
  - ../../../dapr-azure-integration/statestore-redis
  - ../../../dapr-azure-integration/pubsub-redis
  # NOTE: Don't include service-account if app has its own ServiceAccount

resources:
  - Namespace-{app-name}.yaml
  - ServiceAccount-{app-name}.yaml
  - Deployment-{app-name}.yaml
  - Service-{app-name}.yaml

# App-specific customizations
patches:
  # Azure App Config label and scope
  - target:
      kind: Component
      name: azureappconfig
    patch: |
      - op: replace
        path: /spec/metadata/2/value
        value: "{APP_NAME}"
      - op: replace
        path: /scopes/0
        value: "{APP_NAME}"
      - op: add
        path: /metadata/namespace
        value: "{NAMESPACE}"

  # Redis statestore host
  - target:
      kind: Component
      name: statestore
    patch: |
      - op: replace
        path: /spec/metadata/0/value
        value: "{REDIS_HOST}"
      - op: add
        path: /metadata/namespace
        value: "{NAMESPACE}"

  # Redis pubsub host
  - target:
      kind: Component
      name: pubsub
    patch: |
      - op: replace
        path: /spec/metadata/0/value
        value: "{REDIS_HOST}"
      - op: add
        path: /metadata/namespace
        value: "{NAMESPACE}"

  # OTEL service name
  - target:
      kind: ConfigMap
      name: otel-config
    patch: |
      - op: replace
        path: /data/OTEL_SERVICE_NAME
        value: "{APP_NAME}"
      - op: replace
        path: /data/NEXT_PUBLIC_OTEL_SERVICE_NAME
        value: "{APP_NAME}-browser"
      - op: add
        path: /metadata/namespace
        value: "{NAMESPACE}"
      - op: add
        path: /metadata/name
        value: "{APP_NAME}-otel-config"

  # Dapr config ConfigMap
  - target:
      kind: ConfigMap
      name: dapr-config
    patch: |
      - op: add
        path: /metadata/namespace
        value: "{NAMESPACE}"
      - op: add
        path: /metadata/name
        value: "{APP_NAME}-dapr-config"

  # Flipt config
  - target:
      kind: ConfigMap
      name: flipt-config
    patch: |
      - op: add
        path: /metadata/namespace
        value: "{NAMESPACE}"
      - op: add
        path: /metadata/name
        value: "{APP_NAME}-flipt-config"

  # Dapr Configuration
  - target:
      kind: Configuration
      name: dapr-config
    patch: |
      - op: add
        path: /metadata/namespace
        value: "{NAMESPACE}"
      - op: add
        path: /metadata/name
        value: "{APP_NAME}-dapr-config"
```

## Step 5: Configure Deployment for Dapr + Workload Identity

Update the app's Deployment to enable Dapr sidecar and Workload Identity:

**File:** `stacks/main/packages/components/active-development/manifests/{app-name}/Deployment-{app-name}.yaml`

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: {APP_NAME}
  namespace: {NAMESPACE}
spec:
  template:
    metadata:
      annotations:
        # Dapr sidecar injection
        dapr.io/enabled: "true"
        dapr.io/app-id: "{APP_NAME}"
        dapr.io/app-port: "3000"  # Your app's port
        dapr.io/config: "{APP_NAME}-dapr-config"
        dapr.io/enable-app-health-check: "true"
        dapr.io/app-health-check-path: "/api/health"
      labels:
        # Enable Azure Workload Identity
        azure.workload.identity/use: "true"
    spec:
      serviceAccountName: {SERVICE_ACCOUNT_NAME}
      containers:
        - name: {APP_NAME}
          envFrom:
            # Reference the ConfigMaps from the component
            - configMapRef:
                name: {APP_NAME}-otel-config
            - configMapRef:
                name: {APP_NAME}-dapr-config
            - configMapRef:
                name: {APP_NAME}-flipt-config
            # Reference secrets from Key Vault (if using ExternalSecrets)
            - secretRef:
                name: {APP_NAME}-secrets
```

## Step 6: Add Azure App Configuration Values

Add configuration values for the app in Azure App Configuration:

```bash
# Set the App Configuration name
APPCONFIG_NAME="rg3-app-config"

# Add configuration values with the app's label
az appconfig kv set --name $APPCONFIG_NAME --key "OTEL_SERVICE_NAME" --value "{APP_NAME}" --label "{APP_NAME}" -y
az appconfig kv set --name $APPCONFIG_NAME --key "REDIS_HOST" --value "redis.{NAMESPACE}.svc.cluster.local" --label "{APP_NAME}" -y
az appconfig kv set --name $APPCONFIG_NAME --key "REDIS_PORT" --value "6379" --label "{APP_NAME}" -y
# Add more app-specific configuration as needed
```

**List existing configuration for reference:**
```bash
az appconfig kv list --name $APPCONFIG_NAME --label "ai-chatbot" -o table
```

## Step 7: Build and Deploy

Build the manifests and deploy:

```bash
# Build the manifests
cd /home/vpittamp/repos/PittampalliOrg/stacks/main/packages
nix-shell -p yq-go --run "./scripts/build-kustomize.sh kind"

# Apply directly (for testing)
kubectl kustomize dist/kind/{app-name}/manifests/ | kubectl apply -f -

# Or wait for ArgoCD to sync
kubectl get application {app-name} -n argocd -w
```

## Step 8: Verify Configuration

Verify the Dapr components are working:

```bash
# Check pod status
kubectl get pods -n {NAMESPACE}

# Verify Dapr components loaded
kubectl get components.dapr.io -n {NAMESPACE}

# Check Dapr sidecar logs for Azure App Config
kubectl logs -n {NAMESPACE} deployment/{APP_NAME} -c daprd | grep -i "appconfig\|configuration"

# Test Azure App Config access via Dapr
kubectl exec -n {NAMESPACE} deployment/{APP_NAME} -c {APP_NAME} -- \
  curl -s http://localhost:3500/v1.0/configuration/azureappconfig
```

## Component Reference

The `dapr-azure-integration` component provides these sub-components:

| Sub-Component | Resources | Use When |
|--------------|-----------|----------|
| Base (main) | Configuration, ConfigMaps (otel, dapr, flipt) | Always |
| `service-account` | ServiceAccount with Workload Identity | App doesn't have its own SA |
| `azure-app-config` | Dapr Component for Azure App Config | Need dynamic configuration |
| `statestore-redis` | Dapr Component for Redis state store | Need state storage/actors |
| `pubsub-redis` | Dapr Component for Redis pub/sub | Need messaging |
| `secrets` | ExternalSecret for AI provider keys | Need OpenAI/Anthropic/Google keys |

## Shared Values (from component)

| Resource | Value |
|----------|-------|
| Azure Workload Identity client-id | `1140d9c2-62f6-4857-94c2-7e0e6c64e562` |
| Azure Workload Identity tenant-id | `0c4da9c5-40ea-4e7d-9c7a-e7308d4f8e38` |
| Azure App Config host | `https://rg3-app-config.azconfig.io` |
| OTEL Collector endpoint | `otel-collector.observability.svc.cluster.local:4317` |
| Key Vault store ref | `ClusterSecretStore: azure-keyvault-store` |
| Flipt URL | `http://flipt.feature-flags.svc.cluster.local:8080` |

## Troubleshooting

### Federated Credential Issues

```bash
# Check if federated credential exists
az ad app federated-credential list --id "1140d9c2-62f6-4857-94c2-7e0e6c64e562" -o table

# Verify the issuer URL matches
kubectl get --raw /.well-known/openid-configuration | jq -r '.issuer'
```

### Dapr Sidecar Not Starting

```bash
# Check Dapr system pods
kubectl get pods -n dapr-system

# Check for injection issues
kubectl describe pod -n {NAMESPACE} -l app={APP_NAME}
```

### Azure App Config Access Denied

```bash
# Verify role assignment
az role assignment list --assignee "1140d9c2-62f6-4857-94c2-7e0e6c64e562" --scope "/subscriptions/.../resourceGroups/rg3/providers/Microsoft.AppConfiguration/configurationStores/rg3-app-config" -o table

# Re-run bootstrap to fix roles
cd /home/vpittamp/repos/PittampalliOrg/stacks/main/scripts
./00-bootstrap-azure-infra.sh --update-issuer
```

### Configuration Not Loading

```bash
# Check if label filter is correct
az appconfig kv list --name rg3-app-config --label "{APP_NAME}" -o table

# Verify Dapr component configuration
kubectl get component azureappconfig -n {NAMESPACE} -o yaml
```
