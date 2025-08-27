#!/usr/bin/env bash
# Wrapper script that automatically uses nix-shell with azure-cli

if [ -z "$1" ]; then
    echo "Usage: $0 <key-vault-name>"
    echo "Example: $0 my-keyvault"
    exit 1
fi

KEY_VAULT_NAME="$1"

echo "🔐 Copying Azure Key Vault secrets using nix-shell..."
echo "Key Vault: $KEY_VAULT_NAME"
echo ""

# Run the copy script inside nix-shell with azure-cli
exec nix-shell -p azure-cli --run "
    # Check if logged in
    if ! az account show &>/dev/null; then
        echo '❌ Not logged in to Azure'
        echo 'Please run: nix-shell -p azure-cli --run \"az login\"'
        exit 1
    fi
    
    # Copy secrets
    for secret in 'BACKSTAGE-SSH-AUTHORIZED-KEYS' 'BACKSTAGE-SSH-HOST-RSA-KEY' 'BACKSTAGE-SSH-HOST-ED25519-KEY'; do
        echo \"Copying \${secret}-DEV to \${secret}-STAGING...\"
        if az keyvault secret show --vault-name '$KEY_VAULT_NAME' --name \"\${secret}-DEV\" --query value -o tsv | \
           az keyvault secret set --vault-name '$KEY_VAULT_NAME' --name \"\${secret}-STAGING\" --stdin --output none; then
            echo \"✓ \${secret} copied successfully\"
        else
            echo \"✗ Failed to copy \${secret}\"
        fi
    done
"