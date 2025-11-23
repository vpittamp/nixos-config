#!/usr/bin/env bash
# Create test projects with varying window counts for Feature 091 scaling tests
# User Story 2: Consistent Scaling Performance

set -euo pipefail

# Configuration
PROJECT_PREFIX="${1:-benchmark-project}"
CONFIG_DIR="${HOME}/.config/i3/projects"

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}=== Creating Test Projects for Feature 091 ===${NC}"
echo "Project prefix: $PROJECT_PREFIX"
echo "Config directory: $CONFIG_DIR"
echo ""

# Ensure config directory exists
mkdir -p "$CONFIG_DIR"

# Window count scenarios (from spec.md)
declare -A scenarios=(
    ["5w"]="5"
    ["10w"]="10"
    ["20w"]="20"
    ["40w"]="40"
)

for scenario in "${!scenarios[@]}"; do
    window_count="${scenarios[$scenario]}"
    project_name="${PROJECT_PREFIX}-${scenario}"
    project_file="${CONFIG_DIR}/${project_name}.json"

    echo -e "${YELLOW}Creating project: ${project_name} (${window_count} windows)${NC}"

    # Create project JSON file
    cat > "$project_file" << EOF
{
  "name": "${project_name}",
  "display_name": "Benchmark ${window_count}w",
  "icon": "📊",
  "working_directory": "/tmp/${project_name}",
  "enabled": true,
  "created_at": "$(date -Iseconds)",
  "updated_at": "$(date -Iseconds)",
  "metadata": {
    "description": "Test project with ${window_count} windows for Feature 091 scaling validation",
    "window_count": ${window_count},
    "test_scenario": "${scenario}",
    "performance_target_ms": $(case $scenario in
      "5w") echo "150" ;;
      "10w") echo "180" ;;
      "20w") echo "200" ;;
      "40w") echo "300" ;;
    esac)
  }
}
EOF

    # Create working directory
    mkdir -p "/tmp/${project_name}"

    echo -e "${GREEN}✓ Created ${project_file}${NC}"
done

echo ""
echo -e "${GREEN}=== Test Projects Created ===${NC}"
echo ""
echo "Projects created:"
i3pm project list | grep "^${PROJECT_PREFIX}-" || echo "No projects found (daemon may need restart)"

echo ""
echo -e "${BLUE}Next steps:${NC}"
echo "1. Restart daemon: systemctl --user restart i3-project-event-listener"
echo "2. Verify projects: i3pm project list"
echo "3. Run benchmark: tests/091-optimize-i3pm-project/benchmarks/benchmark_scaling.sh"
