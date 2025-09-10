#!/bin/bash
# Enhanced script to sync JWKS from Kind cluster to Azure storage for Workload Identity
# Made fully idempotent and robust for repeated runs

# Don't exit on error - handle errors gracefully
set +e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Configuration from environment or defaults
AZURE_STORAGE_ACCOUNT="${AZURE_STORAGE_ACCOUNT:-oidcissuer65846b7df97b}"
SERVICE_ACCOUNT_ISSUER="${SERVICE_ACCOUNT_ISSUER:-https://${AZURE_STORAGE_ACCOUNT}.z13.web.core.windows.net/}"
AZURE_SUBSCRIPTION_ID="${AZURE_SUBSCRIPTION_ID:-fa5b32b6-1d6d-4110-bea2-8ac0e3126a38}"

echo "======================================"
echo "Syncing JWKS to Azure Storage"
echo "======================================"
echo "Storage Account: ${AZURE_STORAGE_ACCOUNT}"
echo "Service Account Issuer: ${SERVICE_ACCOUNT_ISSUER}"
echo ""

# Check if kubectl is configured
if ! kubectl cluster-info > /dev/null 2>&1; then
    echo "Error: kubectl is not configured or cluster is not accessible"
    echo "Please ensure you have a running Kind cluster and kubectl is configured"
    exit 1
fi

# Check Azure CLI authentication
echo "Checking Azure CLI authentication..."
if ! az account show &>/dev/null; then
    echo "⚠️  Azure CLI not authenticated."
    echo "   Please run 'az login' to enable JWKS sync."
    echo "   Skipping JWKS sync for now..."
    exit 0  # Exit gracefully - this is not a fatal error
fi

# Set the subscription if needed
CURRENT_SUB=$(az account show --query id -o tsv 2>/dev/null || echo "")
if [ -n "$AZURE_SUBSCRIPTION_ID" ] && [ "$CURRENT_SUB" != "$AZURE_SUBSCRIPTION_ID" ]; then
    echo "Setting Azure subscription to ${AZURE_SUBSCRIPTION_ID}..."
    if ! az account set --subscription "${AZURE_SUBSCRIPTION_ID}" 2>/dev/null; then
        echo "⚠️  Could not set subscription. Using current subscription."
    fi
fi

# Extract JWKS from the cluster
echo "Extracting JWKS from cluster..."
if ! kubectl get --raw /openid/v1/jwks 2>/dev/null | jq > "${SCRIPT_DIR}/jwks.json"; then
    echo "Error: Failed to extract JWKS from cluster"
    echo "Please ensure the cluster is running and accessible"
    exit 1
fi

# Verify JWKS file is valid
if [ ! -s "${SCRIPT_DIR}/jwks.json" ] || ! jq empty "${SCRIPT_DIR}/jwks.json" 2>/dev/null; then
    echo "Error: Invalid or empty JWKS file"
    rm -f "${SCRIPT_DIR}/jwks.json" 2>/dev/null
    exit 1
fi

# Display the key ID for verification
KID=$(jq -r '.keys[0].kid' "${SCRIPT_DIR}/jwks.json" 2>/dev/null || echo "")
if [ -z "$KID" ]; then
    echo "Warning: Could not extract key ID from JWKS"
else
    echo "Extracted JWKS with key ID: ${KID}"
fi

# Upload JWKS to Azure storage using auth-mode login (uses Azure AD authentication)
echo "Uploading JWKS to Azure storage..."
UPLOAD_SUCCESS=false

# First try with auth-mode login
if az storage blob upload \
    --auth-mode login \
    --container-name '$web' \
    --file "${SCRIPT_DIR}/jwks.json" \
    --name "openid/v1/jwks" \
    --account-name "${AZURE_STORAGE_ACCOUNT}" \
    --overwrite \
    --output table 2>/dev/null; then
    echo "✅ JWKS uploaded successfully"
    UPLOAD_SUCCESS=true
else
    echo "⚠️  First attempt failed, trying with key authentication..."
    # Fallback: Try to get storage account key (requires Owner/Contributor role)
    STORAGE_KEY=$(az storage account keys list \
        --account-name "${AZURE_STORAGE_ACCOUNT}" \
        --query "[0].value" -o tsv 2>/dev/null || echo "")
    
    if [ -n "$STORAGE_KEY" ]; then
        if az storage blob upload \
            --account-key "${STORAGE_KEY}" \
            --container-name '$web' \
            --file "${SCRIPT_DIR}/jwks.json" \
            --name "openid/v1/jwks" \
            --account-name "${AZURE_STORAGE_ACCOUNT}" \
            --overwrite \
            --output table 2>/dev/null; then
            echo "✅ JWKS uploaded using storage account key"
            UPLOAD_SUCCESS=true
        fi
    fi
fi

if [ "$UPLOAD_SUCCESS" = false ]; then
    echo "⚠️  Failed to upload JWKS. Please ensure you have proper permissions."
    echo "   You need either:"
    echo "   - Storage Blob Data Contributor role on the storage account"
    echo "   - Or Owner/Contributor role to access storage keys"
    echo "   Continuing without JWKS sync..."
fi

# Verify the upload (only if upload was successful)
if [ "$UPLOAD_SUCCESS" = true ]; then
    echo ""
    echo "Verifying JWKS upload..."
    REMOTE_KID=$(curl -s "${SERVICE_ACCOUNT_ISSUER}openid/v1/jwks" 2>/dev/null | jq -r '.keys[0].kid' 2>/dev/null || echo "")
    
    if [ "${KID}" == "${REMOTE_KID}" ]; then
        echo "✅ Success! JWKS synced to Azure storage"
        echo "   Key ID in cluster: ${KID}"
        echo "   Key ID in Azure:  ${REMOTE_KID}"
    else
        echo "⚠️  Warning: Could not verify JWKS upload"
        echo "   Key ID in cluster: ${KID}"
        echo "   Key ID in Azure:  ${REMOTE_KID:-<unable to fetch>}"
        echo "   This might be a caching issue. The upload may still be successful."
    fi
fi

# Check if OpenID configuration exists
echo ""
echo "Checking OpenID configuration..."
if curl -sf "${SERVICE_ACCOUNT_ISSUER}.well-known/openid-configuration" > /dev/null 2>&1; then
    echo "✅ OpenID configuration is accessible"
else
    echo "⚠️  OpenID configuration not found at ${SERVICE_ACCOUNT_ISSUER}.well-known/openid-configuration"
    
    if [ "$UPLOAD_SUCCESS" = true ]; then
        echo "   Creating and uploading openid-configuration..."
        
        # Create the OpenID configuration file
        cat > "${SCRIPT_DIR}/openid-configuration.json" <<EOCONFIG
{
  "issuer": "${SERVICE_ACCOUNT_ISSUER}",
  "jwks_uri": "${SERVICE_ACCOUNT_ISSUER}openid/v1/jwks",
  "response_types_supported": [
    "id_token"
  ],
  "subject_types_supported": [
    "public"
  ],
  "id_token_signing_alg_values_supported": [
    "RS256"
  ]
}
EOCONFIG

        # Upload the OpenID configuration
        if az storage blob upload \
            --auth-mode login \
            --container-name '$web' \
            --file "${SCRIPT_DIR}/openid-configuration.json" \
            --name ".well-known/openid-configuration" \
            --account-name "${AZURE_STORAGE_ACCOUNT}" \
            --overwrite \
            --output table 2>/dev/null; then
            echo "   ✅ OpenID configuration uploaded successfully"
        else
            # Try with storage key
            if [ -n "$STORAGE_KEY" ]; then
                if az storage blob upload \
                    --account-key "${STORAGE_KEY}" \
                    --container-name '$web' \
                    --file "${SCRIPT_DIR}/openid-configuration.json" \
                    --name ".well-known/openid-configuration" \
                    --account-name "${AZURE_STORAGE_ACCOUNT}" \
                    --overwrite \
                    --output table 2>/dev/null; then
                    echo "   ✅ OpenID configuration uploaded using storage key"
                else
                    echo "   ⚠️  Failed to upload OpenID configuration"
                fi
            else
                echo "   ⚠️  Failed to upload OpenID configuration"
            fi
        fi
    fi
fi

# Clean up temporary files
rm -f "${SCRIPT_DIR}/jwks.json" "${SCRIPT_DIR}/openid-configuration.json" 2>/dev/null || true

echo ""
echo "======================================"
if [ "$UPLOAD_SUCCESS" = true ]; then
    echo "JWKS sync completed successfully"
else
    echo "JWKS sync skipped (Azure auth required)"
fi
echo "======================================"

# Always exit successfully - JWKS sync is optional
exit 0
