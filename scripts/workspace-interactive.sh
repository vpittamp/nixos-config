#!/usr/bin/env bash
# Interactive Workspace Template Launcher
# FZF-based interface for selecting and parameterizing workspace templates
#
# Usage: workspace-interactive.sh [template-dir]

set -euo pipefail

TEMPLATE_DIR="${1:-/etc/nixos/templates}"
RECENT_FILE="$HOME/.cache/workspace-interactive-recent.txt"

# Logging
log() { echo "[workspace-interactive] $*" >&2; }
error() { echo "[ERROR] $*" >&2; exit 1; }

# Check dependencies
command -v fzf &>/dev/null || error "fzf is required"
command -v jq &>/dev/null || error "jq is required"
command -v i3-msg &>/dev/null || error "i3-msg is required"

# Ensure cache directory exists
mkdir -p "$(dirname "$RECENT_FILE")"

# Function to extract variables from a template
extract_template_vars() {
    local file="$1"
    # Find all ${VAR} and $VAR patterns, remove duplicates
    grep -oE '\$\{[A-Z_][A-Z0-9_]*[:\-]?[^}]*\}|\$[A-Z_][A-Z0-9_]*' "$file" | \
        sed -E 's/\$\{([A-Z_][A-Z0-9_]*)[:\-]?.*/\1/; s/\$([A-Z_][A-Z0-9_]*)/\1/' | \
        sort -u
}

# Function to get default value from template
get_default_value() {
    local file="$1"
    local var="$2"
    # Extract default value from ${VAR:-default} syntax
    grep -oE "\\\$\{${var}:-[^}]*\}" "$file" | head -1 | sed -E "s/\\\$\{${var}:-([^}]*)\}/\1/" || echo ""
}

# Function to prompt for variable value
prompt_for_var() {
    local var="$1"
    local default="$2"
    local prompt_text="$var"
    [[ -n "$default" ]] && prompt_text="$var (default: $default)"

    # Use FZF to get input (allows typing custom value)
    echo "$prompt_text" | fzf \
        --print-query \
        --header="Enter value for $var" \
        --prompt="$var> " \
        --bind "enter:accept" \
        --height=10 | tail -1 || echo "$default"
}

# Step 1: Find all templates
if [[ ! -d "$TEMPLATE_DIR" ]]; then
    error "Template directory not found: $TEMPLATE_DIR"
fi

TEMPLATES=$(find "$TEMPLATE_DIR" -type f \( -name "*.json" -o -name "*.yaml" -o -name "*.yml" \) 2>/dev/null)

if [[ -z "$TEMPLATES" ]]; then
    error "No templates found in $TEMPLATE_DIR"
fi

# Step 2: Select template with preview
log "Select a workspace template..."
SELECTED_TEMPLATE=$(echo "$TEMPLATES" | fzf \
    --preview 'cat {}' \
    --preview-window=right:60%:wrap \
    --header="Select workspace template" \
    --prompt="Template> ")

[[ -z "$SELECTED_TEMPLATE" ]] && exit 0

TEMPLATE_NAME=$(basename "$SELECTED_TEMPLATE")
log "Selected: $TEMPLATE_NAME"

# Step 3: Extract variables from template
VARS=$(extract_template_vars "$SELECTED_TEMPLATE")

if [[ -z "$VARS" ]]; then
    log "No variables to parameterize, launching directly..."
    exec /etc/nixos/scripts/workspace-project.sh "$SELECTED_TEMPLATE"
fi

# Step 4: Prompt for each variable
log "Template requires the following parameters:"
declare -a PARAM_ARGS

while IFS= read -r var; do
    [[ -z "$var" ]] && continue

    # Get default value from template
    DEFAULT=$(get_default_value "$SELECTED_TEMPLATE" "$var")

    # Check recent file for last used value
    RECENT_VALUE=""
    if [[ -f "$RECENT_FILE" ]]; then
        RECENT_VALUE=$(grep -E "^${var}=" "$RECENT_FILE" | tail -1 | cut -d= -f2-)
    fi

    # Use recent value as default if available
    [[ -n "$RECENT_VALUE" ]] && DEFAULT="$RECENT_VALUE"

    # Prompt user
    echo "" >&2
    echo "Parameter: $var" >&2
    [[ -n "$DEFAULT" ]] && echo "Default: $DEFAULT" >&2
    read -p "Value (Enter for default): " -r VALUE

    # Use default if empty
    [[ -z "$VALUE" ]] && VALUE="$DEFAULT"

    # Store for next time
    if [[ -n "$VALUE" ]]; then
        PARAM_ARGS+=("${var}=${VALUE}")
        # Save to recent file
        grep -v "^${var}=" "$RECENT_FILE" 2>/dev/null > "${RECENT_FILE}.tmp" || true
        echo "${var}=${VALUE}" >> "${RECENT_FILE}.tmp"
        mv "${RECENT_FILE}.tmp" "$RECENT_FILE"
    fi
done <<< "$VARS"

# Step 5: Show summary and confirm
echo "" >&2
log "Configuration summary:"
log "  Template: $TEMPLATE_NAME"
for param in "${PARAM_ARGS[@]}"; do
    log "  $param"
done
echo "" >&2

read -p "Proceed? [Y/n] " -n 1 -r
echo >&2
if [[ $REPLY =~ ^[Nn]$ ]]; then
    log "Cancelled"
    exit 0
fi

# Step 6: Launch with parameters
log "Launching workspace..."
exec /etc/nixos/scripts/workspace-parameterized.sh "$SELECTED_TEMPLATE" "${PARAM_ARGS[@]}"
