#!/bin/bash
# One-liner version for quick copying of Key Vault secrets from DEV to STAGING

KEY_VAULT="${1:-your-keyvault-name}"  # Pass vault name as first argument

# Copy all three secrets in one command
for secret in "BACKSTAGE-SSH-AUTHORIZED-KEYS" "BACKSTAGE-SSH-HOST-RSA-KEY" "BACKSTAGE-SSH-HOST-ED25519-KEY"; do
    echo "Copying ${secret}-DEV to ${secret}-STAGING..."
    az keyvault secret show --vault-name "$KEY_VAULT" --name "${secret}-DEV" --query value -o tsv | \
    az keyvault secret set --vault-name "$KEY_VAULT" --name "${secret}-STAGING" --stdin --output none && \
    echo "✓ ${secret} copied" || echo "✗ Failed: ${secret}"
done