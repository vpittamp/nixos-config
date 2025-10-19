#!/usr/bin/env bash
# Parameterized Workspace Creator
# Create workspaces on-the-fly with variable substitution
#
# Inspired by: tmuxp, tmuxinator, i3-resurrect
#
# Usage:
#   workspace-parameterized.sh <template-file> [VAR=value ...]
#
# Example:
#   workspace-parameterized.sh dev-project.yaml PROJECT_DIR=/home/user/myproject PROJECT_NAME=myproject
#
# Template format (YAML or JSON):
# ---
# name: ${PROJECT_NAME}
# workspaces:
#   - number: 2
#     apps:
#       - command: ghostty
#         args: ["--working-directory=${PROJECT_DIR}"]
#   - number: 4
#     apps:
#       - command: code
#         args: ["${PROJECT_DIR}"]

set -euo pipefail

TEMPLATE_FILE="${1:-}"
shift || true

# Parse key=value parameters
declare -A PARAMS
for arg in "$@"; do
    if [[ "$arg" =~ ^([A-Z_][A-Z0-9_]*)=(.*)$ ]]; then
        PARAMS["${BASH_REMATCH[1]}"]="${BASH_REMATCH[2]}"
    else
        echo "Warning: Ignoring invalid parameter: $arg" >&2
    fi
done

# Logging
log() { echo "[workspace-param] $*" >&2; }
error() { echo "[ERROR] $*" >&2; exit 1; }

# Validate inputs
[[ -z "$TEMPLATE_FILE" ]] && error "Usage: workspace-parameterized.sh <template-file> [VAR=value ...]"
[[ -f "$TEMPLATE_FILE" ]] || error "Template file not found: $TEMPLATE_FILE"

# Check dependencies
command -v jq &>/dev/null || error "jq is required"
command -v yq &>/dev/null || YQ_MISSING=1
command -v i3-msg &>/dev/null || error "i3-msg is required"

# Determine file format
if [[ "$TEMPLATE_FILE" =~ \.ya?ml$ ]]; then
    FORMAT="yaml"
    [[ -n "${YQ_MISSING:-}" ]] && error "yq is required for YAML templates (or convert to JSON)"
elif [[ "$TEMPLATE_FILE" =~ \.json$ ]]; then
    FORMAT="json"
else
    error "Unknown template format. Use .yaml, .yml, or .json"
fi

log "Loading template: $TEMPLATE_FILE (format: $FORMAT)"

# Function to substitute variables in a string
substitute_vars() {
    local input="$1"
    local output="$input"

    # Substitute each parameter
    for var in "${!PARAMS[@]}"; do
        local value="${PARAMS[$var]}"
        # Handle ${VAR} and $VAR syntax
        output="${output//\$\{$var\}/$value}"
        output="${output//\$$var/$value}"
    done

    echo "$output"
}

# Create temporary file for processed template
TEMP_FILE=$(mktemp /tmp/workspace-param.XXXXXX.json)
trap "rm -f $TEMP_FILE" EXIT

# Convert YAML to JSON if needed and substitute variables
if [[ "$FORMAT" == "yaml" ]]; then
    # Convert YAML to JSON
    yq eval -o=json '.' "$TEMPLATE_FILE" > "$TEMP_FILE.raw"

    # Read, substitute, and write
    TEMPLATE_CONTENT=$(cat "$TEMP_FILE.raw")
    TEMPLATE_CONTENT=$(substitute_vars "$TEMPLATE_CONTENT")
    echo "$TEMPLATE_CONTENT" > "$TEMP_FILE"
    rm "$TEMP_FILE.raw"
else
    # JSON: read, substitute, and write
    TEMPLATE_CONTENT=$(cat "$TEMPLATE_FILE")
    TEMPLATE_CONTENT=$(substitute_vars "$TEMPLATE_CONTENT")
    echo "$TEMPLATE_CONTENT" > "$TEMP_FILE"
fi

# Validate JSON
if ! jq empty "$TEMP_FILE" 2>/dev/null; then
    log "Processed template (for debugging):"
    cat "$TEMP_FILE" >&2
    error "Invalid JSON after variable substitution"
fi

# Show what we're about to do
PROJECT_NAME=$(jq -r '.name // "unknown"' "$TEMP_FILE")
log "Project: $PROJECT_NAME"

if [[ ${#PARAMS[@]} -gt 0 ]]; then
    log "Parameters:"
    for var in "${!PARAMS[@]}"; do
        log "  $var = ${PARAMS[$var]}"
    done
fi

# Launch using the existing workspace-project.sh script
log "Launching workspace configuration..."
exec /etc/nixos/scripts/workspace-project.sh "$TEMP_FILE"
