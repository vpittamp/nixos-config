#!/usr/bin/env bash
# langfuse-auth.sh - Generate Langfuse OTEL authentication header
#
# Feature 132: Langfuse-Compatible AI CLI Tracing
#
# This script generates the base64-encoded authorization header required
# for Langfuse's OTEL HTTP endpoint. The header format is:
#   Authorization: Basic <base64(public_key:secret_key)>
#
# Usage:
#   langfuse-auth.sh                    # Interactive (prompts for keys)
#   langfuse-auth.sh --from-env         # Use LANGFUSE_PUBLIC_KEY and LANGFUSE_SECRET_KEY
#   langfuse-auth.sh --from-1password   # Use 1Password CLI to fetch keys
#   langfuse-auth.sh --from-azure       # Use Azure Key Vault to fetch keys
#   langfuse-auth.sh <public_key> <secret_key>  # Direct arguments
#
# Output:
#   Prints the Authorization header value to stdout
#   (e.g., "Basic cGstbGYteHh4OnNrLWxmLXl5eQ==")
#
# Environment Variables (when using --from-env):
#   LANGFUSE_PUBLIC_KEY  - Langfuse public key (pk-lf-...)
#   LANGFUSE_SECRET_KEY  - Langfuse secret key (sk-lf-...)
#
# 1Password Configuration (when using --from-1password):
#   Uses 1Password CLI (op) to fetch keys from the vault.
#   Default references:
#     - LANGFUSE_1P_PUBLIC_KEY_REF: "op://Development/Langfuse/public_key"
#     - LANGFUSE_1P_SECRET_KEY_REF: "op://Development/Langfuse/secret_key"
#
# Azure Key Vault Configuration (when using --from-azure):
#   Uses Azure CLI (az) to fetch keys from Key Vault.
#   Requires:
#     - AZURE_KEYVAULT_NAME: Name of the Azure Key Vault
#   Optional (defaults to standard secret names):
#     - LANGFUSE_AZ_PUBLIC_KEY_NAME: Secret name for public key (default: "LANGFUSE-PUBLIC-KEY")
#     - LANGFUSE_AZ_SECRET_KEY_NAME: Secret name for secret key (default: "LANGFUSE-SECRET-KEY")

set -euo pipefail

# Default 1Password references (can be overridden via environment)
LANGFUSE_1P_PUBLIC_KEY_REF="${LANGFUSE_1P_PUBLIC_KEY_REF:-op://Development/Langfuse/public_key}"
LANGFUSE_1P_SECRET_KEY_REF="${LANGFUSE_1P_SECRET_KEY_REF:-op://Development/Langfuse/secret_key}"

# Default Azure Key Vault secret names (matching user's existing secrets)
LANGFUSE_AZ_PUBLIC_KEY_NAME="${LANGFUSE_AZ_PUBLIC_KEY_NAME:-LANGFUSE-PUBLIC-KEY}"
LANGFUSE_AZ_SECRET_KEY_NAME="${LANGFUSE_AZ_SECRET_KEY_NAME:-LANGFUSE-SECRET-KEY}"

usage() {
    cat <<EOF
Usage: $(basename "$0") [OPTIONS] [public_key] [secret_key]

Generate Langfuse OTEL authentication header.

Options:
  --from-env         Use LANGFUSE_PUBLIC_KEY and LANGFUSE_SECRET_KEY environment variables
  --from-1password   Fetch keys from 1Password vault
  --from-azure       Fetch keys from Azure Key Vault (requires AZURE_KEYVAULT_NAME)
  --export           Output as 'export LANGFUSE_AUTH_HEADER=...' for sourcing
  --validate         Validate the generated header by making a test request
  -h, --help         Show this help message

Arguments:
  public_key         Langfuse public key (pk-lf-...)
  secret_key         Langfuse secret key (sk-lf-...)

Environment Variables:
  LANGFUSE_PUBLIC_KEY        Public key (for --from-env)
  LANGFUSE_SECRET_KEY        Secret key (for --from-env)
  AZURE_KEYVAULT_NAME        Azure Key Vault name (for --from-azure)
  LANGFUSE_AZ_PUBLIC_KEY_NAME  Azure secret name for public key (default: LANGFUSE-PUBLIC-KEY)
  LANGFUSE_AZ_SECRET_KEY_NAME  Azure secret name for secret key (default: LANGFUSE-SECRET-KEY)

Examples:
  $(basename "$0") pk-lf-xxx sk-lf-yyy
  $(basename "$0") --from-env
  $(basename "$0") --from-1password --export
  $(basename "$0") --from-azure --validate
  AZURE_KEYVAULT_NAME=my-vault $(basename "$0") --from-azure --export
  eval "\$($(basename "$0") --from-1password --export)"
EOF
    exit 0
}

generate_auth_header() {
    local public_key="$1"
    local secret_key="$2"

    # Validate key formats
    if [[ ! "$public_key" =~ ^pk-lf- ]]; then
        echo "Error: Invalid public key format. Expected pk-lf-..." >&2
        exit 1
    fi

    if [[ ! "$secret_key" =~ ^sk-lf- ]]; then
        echo "Error: Invalid secret key format. Expected sk-lf-..." >&2
        exit 1
    fi

    # Generate base64-encoded credentials
    local credentials="${public_key}:${secret_key}"
    local encoded
    encoded=$(echo -n "$credentials" | base64 -w0)

    echo "Basic ${encoded}"
}

validate_header() {
    local header="$1"
    local endpoint="${LANGFUSE_ENDPOINT:-https://cloud.langfuse.com/api/public/otel}"

    echo "Validating header against ${endpoint}..." >&2

    # Make a test request (should return 200 or 400 for invalid payload, not 401)
    local status
    status=$(curl -s -o /dev/null -w "%{http_code}" \
        -X POST "${endpoint}/v1/traces" \
        -H "Authorization: ${header}" \
        -H "Content-Type: application/x-protobuf" \
        --data-binary "" \
        --max-time 10) || {
        echo "Warning: Could not reach Langfuse endpoint" >&2
        return 1
    }

    case "$status" in
        200|400)
            echo "Validation successful (status: ${status})" >&2
            return 0
            ;;
        401|403)
            echo "Error: Authentication failed (status: ${status})" >&2
            return 1
            ;;
        *)
            echo "Warning: Unexpected status code: ${status}" >&2
            return 1
            ;;
    esac
}

# Parse options
FROM_ENV=false
FROM_1PASSWORD=false
FROM_AZURE=false
EXPORT_FORMAT=false
VALIDATE=false

while [[ $# -gt 0 ]]; do
    case "$1" in
        --from-env)
            FROM_ENV=true
            shift
            ;;
        --from-1password)
            FROM_1PASSWORD=true
            shift
            ;;
        --from-azure)
            FROM_AZURE=true
            shift
            ;;
        --export)
            EXPORT_FORMAT=true
            shift
            ;;
        --validate)
            VALIDATE=true
            shift
            ;;
        -h|--help)
            usage
            ;;
        -*)
            echo "Unknown option: $1" >&2
            usage
            ;;
        *)
            break
            ;;
    esac
done

# Get credentials based on source
if [[ "$FROM_1PASSWORD" == true ]]; then
    # Fetch from 1Password
    if ! command -v op &> /dev/null; then
        echo "Error: 1Password CLI (op) not found. Install it or use --from-env" >&2
        exit 1
    fi

    echo "Fetching keys from 1Password..." >&2
    PUBLIC_KEY=$(op read "$LANGFUSE_1P_PUBLIC_KEY_REF")
    SECRET_KEY=$(op read "$LANGFUSE_1P_SECRET_KEY_REF")

elif [[ "$FROM_AZURE" == true ]]; then
    # Fetch from Azure Key Vault
    if ! command -v az &> /dev/null; then
        echo "Error: Azure CLI (az) not found. Install it or use --from-env" >&2
        exit 1
    fi

    if [[ -z "${AZURE_KEYVAULT_NAME:-}" ]]; then
        echo "Error: AZURE_KEYVAULT_NAME environment variable must be set" >&2
        exit 1
    fi

    echo "Fetching keys from Azure Key Vault '${AZURE_KEYVAULT_NAME}'..." >&2

    # Check if logged in to Azure
    if ! az account show &> /dev/null; then
        echo "Error: Not logged in to Azure. Run 'az login' first." >&2
        exit 1
    fi

    PUBLIC_KEY=$(az keyvault secret show \
        --vault-name "$AZURE_KEYVAULT_NAME" \
        --name "$LANGFUSE_AZ_PUBLIC_KEY_NAME" \
        --query "value" -o tsv)

    SECRET_KEY=$(az keyvault secret show \
        --vault-name "$AZURE_KEYVAULT_NAME" \
        --name "$LANGFUSE_AZ_SECRET_KEY_NAME" \
        --query "value" -o tsv)

    if [[ -z "$PUBLIC_KEY" ]] || [[ -z "$SECRET_KEY" ]]; then
        echo "Error: Failed to fetch keys from Azure Key Vault" >&2
        exit 1
    fi

elif [[ "$FROM_ENV" == true ]]; then
    # Use environment variables
    if [[ -z "${LANGFUSE_PUBLIC_KEY:-}" ]] || [[ -z "${LANGFUSE_SECRET_KEY:-}" ]]; then
        echo "Error: LANGFUSE_PUBLIC_KEY and LANGFUSE_SECRET_KEY must be set" >&2
        exit 1
    fi
    PUBLIC_KEY="$LANGFUSE_PUBLIC_KEY"
    SECRET_KEY="$LANGFUSE_SECRET_KEY"

elif [[ $# -ge 2 ]]; then
    # Use command line arguments
    PUBLIC_KEY="$1"
    SECRET_KEY="$2"

else
    # Interactive mode
    echo "Enter Langfuse public key (pk-lf-...):" >&2
    read -r PUBLIC_KEY
    echo "Enter Langfuse secret key (sk-lf-...):" >&2
    read -rs SECRET_KEY
    echo >&2
fi

# Generate the header
AUTH_HEADER=$(generate_auth_header "$PUBLIC_KEY" "$SECRET_KEY")

# Validate if requested
if [[ "$VALIDATE" == true ]]; then
    if ! validate_header "$AUTH_HEADER"; then
        exit 1
    fi
fi

# Output in requested format
if [[ "$EXPORT_FORMAT" == true ]]; then
    echo "export LANGFUSE_AUTH_HEADER=\"${AUTH_HEADER}\""
else
    echo "$AUTH_HEADER"
fi
