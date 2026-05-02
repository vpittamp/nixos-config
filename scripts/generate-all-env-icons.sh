#!/usr/bin/env bash
# Generate all environment-badged PWA icons for multi-cluster deployments
# Produces PNG icons with colored badges for dev/staging/prod/ryzen environments
#
# Usage: generate-all-env-icons.sh [--icons-dir /path/to/icons]

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ICONS_DIR="${1:-$(dirname "$SCRIPT_DIR")/assets/icons}"
GENERATE_SCRIPT="$SCRIPT_DIR/generate-env-icon.sh"

if [[ ! -x "$GENERATE_SCRIPT" ]]; then
  echo "Error: generate-env-icon.sh not found or not executable at $GENERATE_SCRIPT" >&2
  exit 1
fi

# Service → source icon mapping
declare -A ICON_MAP=(
  [dapr]="dapr.svg"
  [grafana]="grafana.svg"
  [keycloak]="keycloak.svg"
  [langfuse]="langfuse.svg"
  [loki]="loki.svg"
  [mcp-inspector-client]="mcp-inspector.svg"
  [mcp-inspector-proxy]="mcp-inspector.svg"
  [mimir]="mimir.svg"
  [mlflow]="mlflow.svg"
  [phoenix]="phoenix-azire.svg"
  [redisinsight]="redis-insights.svg"
  [tekton]="tekton.svg"
  [workflow-builder]="ai-workflow-builder.svg"
  [ai-chatbot]="ai-chatbot.svg"
)

# Services that exist on all 4 environments (including ryzen)
ALL_ENV_SERVICES=(ai-chatbot dapr grafana keycloak langfuse mcp-inspector-client mcp-inspector-proxy phoenix redisinsight workflow-builder)

# Services that only exist on dev/staging/prod (no ryzen deployment)
NO_RYZEN_SERVICES=(loki mimir)

# Services that only exist on the hub cluster
HUB_ONLY_SERVICES=(mlflow)

ENVS_ALL=(dev staging prod ryzen)
ENVS_NO_RYZEN=(dev staging prod)
ENVS_HUB_ONLY=(hub)

COUNT=0
ERRORS=0

echo "Generating environment-badged icons in: $ICONS_DIR"
echo "============================================="

# Generate icons for services on all environments
for service in "${ALL_ENV_SERVICES[@]}"; do
  source_svg="$ICONS_DIR/${ICON_MAP[$service]}"
  if [[ ! -f "$source_svg" ]]; then
    echo "WARNING: Source icon not found: $source_svg (skipping $service)" >&2
    ((ERRORS++)) || true
    continue
  fi
  for env in "${ENVS_ALL[@]}"; do
    output="$ICONS_DIR/${service}-${env}.png"
    if "$GENERATE_SCRIPT" "$source_svg" "$env" "$output"; then
      ((COUNT++)) || true
    else
      echo "ERROR: Failed to generate $output" >&2
      ((ERRORS++)) || true
    fi
  done
done

# Generate icons for services without ryzen
for service in "${NO_RYZEN_SERVICES[@]}"; do
  source_svg="$ICONS_DIR/${ICON_MAP[$service]}"
  if [[ ! -f "$source_svg" ]]; then
    echo "WARNING: Source icon not found: $source_svg (skipping $service)" >&2
    ((ERRORS++)) || true
    continue
  fi
  for env in "${ENVS_NO_RYZEN[@]}"; do
    output="$ICONS_DIR/${service}-${env}.png"
    if "$GENERATE_SCRIPT" "$source_svg" "$env" "$output"; then
      ((COUNT++)) || true
    else
      echo "ERROR: Failed to generate $output" >&2
      ((ERRORS++)) || true
    fi
  done
done

# Generate icons for hub-only services
for service in "${HUB_ONLY_SERVICES[@]}"; do
  source_svg="$ICONS_DIR/${ICON_MAP[$service]}"
  if [[ ! -f "$source_svg" ]]; then
    echo "WARNING: Source icon not found: $source_svg (skipping $service)" >&2
    ((ERRORS++)) || true
    continue
  fi
  for env in "${ENVS_HUB_ONLY[@]}"; do
    output="$ICONS_DIR/${service}-${env}.png"
    if "$GENERATE_SCRIPT" "$source_svg" "$env" "$output"; then
      ((COUNT++)) || true
    else
      echo "ERROR: Failed to generate $output" >&2
      ((ERRORS++)) || true
    fi
  done
done

echo "============================================="
echo "Generated: $COUNT icons"
if [[ $ERRORS -gt 0 ]]; then
  echo "Errors: $ERRORS"
  exit 1
fi
echo "Done!"
