#!/bin/bash
# Copy Azure Key Vault secrets from dev to staging environment
# This script copies SSH-related secrets to avoid errors during development

set -e

# Configuration
KEY_VAULT_NAME="${KEY_VAULT_NAME:-your-keyvault-name}"  # Replace with your Key Vault name
SOURCE_ENV="DEV"
TARGET_ENV="STAGING"

# Color output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Secrets to copy
SECRETS=(
    "BACKSTAGE-SSH-AUTHORIZED-KEYS"
    "BACKSTAGE-SSH-HOST-RSA-KEY"
    "BACKSTAGE-SSH-HOST-ED25519-KEY"
)

echo -e "${GREEN}🔐 Azure Key Vault Secret Copy Tool${NC}"
echo -e "Copying secrets from ${YELLOW}${SOURCE_ENV}${NC} to ${YELLOW}${TARGET_ENV}${NC}"
echo ""

# Check if logged in to Azure
echo "Checking Azure login status..."
if ! az account show &>/dev/null; then
    echo -e "${RED}❌ Not logged in to Azure${NC}"
    echo "Please run: az login"
    exit 1
fi

# Display current subscription
SUBSCRIPTION=$(az account show --query name -o tsv)
echo -e "Current subscription: ${GREEN}${SUBSCRIPTION}${NC}"
echo ""

# Function to copy a secret
copy_secret() {
    local secret_base="$1"
    local source_name="${secret_base}-${SOURCE_ENV}"
    local target_name="${secret_base}-${TARGET_ENV}"
    
    echo -e "📋 Copying ${YELLOW}${source_name}${NC} -> ${YELLOW}${target_name}${NC}"
    
    # Get the secret value from dev
    if SECRET_VALUE=$(az keyvault secret show \
        --vault-name "$KEY_VAULT_NAME" \
        --name "$source_name" \
        --query value -o tsv 2>/dev/null); then
        
        # Set the secret in staging
        if az keyvault secret set \
            --vault-name "$KEY_VAULT_NAME" \
            --name "$target_name" \
            --value "$SECRET_VALUE" \
            --output none 2>/dev/null; then
            
            echo -e "  ${GREEN}✓ Successfully copied${NC}"
        else
            echo -e "  ${RED}✗ Failed to set secret${NC}"
            return 1
        fi
    else
        echo -e "  ${YELLOW}⚠ Source secret not found or no access${NC}"
        return 1
    fi
}

# Confirm before proceeding
echo -e "${YELLOW}⚠️  Warning: This will overwrite existing staging secrets${NC}"
read -p "Continue? (y/N): " -n 1 -r
echo ""
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "Aborted."
    exit 0
fi
echo ""

# Copy each secret
SUCCESS_COUNT=0
FAIL_COUNT=0

for SECRET in "${SECRETS[@]}"; do
    if copy_secret "$SECRET"; then
        ((SUCCESS_COUNT++))
    else
        ((FAIL_COUNT++))
    fi
    echo ""
done

# Summary
echo "======================================="
echo -e "${GREEN}Summary:${NC}"
echo -e "  Successful: ${GREEN}${SUCCESS_COUNT}${NC}"
echo -e "  Failed: ${RED}${FAIL_COUNT}${NC}"

if [ $FAIL_COUNT -eq 0 ]; then
    echo -e "${GREEN}✅ All secrets copied successfully!${NC}"
else
    echo -e "${YELLOW}⚠️  Some secrets failed to copy${NC}"
    exit 1
fi

# Optional: Verify the copied secrets
echo ""
echo "Verifying staging secrets exist:"
for SECRET in "${SECRETS[@]}"; do
    TARGET_NAME="${SECRET}-${TARGET_ENV}"
    if az keyvault secret show \
        --vault-name "$KEY_VAULT_NAME" \
        --name "$TARGET_NAME" \
        --query name -o tsv &>/dev/null; then
        echo -e "  ${GREEN}✓${NC} ${TARGET_NAME}"
    else
        echo -e "  ${RED}✗${NC} ${TARGET_NAME}"
    fi
done