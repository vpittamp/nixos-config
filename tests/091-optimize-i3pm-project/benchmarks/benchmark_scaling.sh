#!/usr/bin/env bash
# Enhanced benchmark script for Feature 091 User Story 2
# Tests project switching performance across multiple window count scenarios

set -euo pipefail

# Configuration
ITERATIONS="${1:-10}"
RESULTS_DIR="${2:-$(dirname "$0")/results}"
TIMESTAMP="$(date +%Y%m%d_%H%M%S)"
RESULTS_FILE="${RESULTS_DIR}/scaling_${TIMESTAMP}.json"

# Performance targets (from spec.md)
declare -A targets=(
    ["5"]="150"
    ["10"]="180"
    ["20"]="200"
    ["40"]="300"
)

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}=== Feature 091 Scaling Benchmark ===${NC}"
echo "Iterations per scenario: $ITERATIONS"
echo "Results: $RESULTS_FILE"
echo ""

# Ensure results directory exists
mkdir -p "$RESULTS_DIR"

# Initialize results JSON
cat > "$RESULTS_FILE" << 'EOF'
{
  "timestamp": "",
  "iterations": 0,
  "scenarios": {}
}
EOF

# Helper: Update JSON file
update_json() {
    local key=$1
    local value=$2
    local temp_file="${RESULTS_FILE}.tmp"
    jq "$key = $value" "$RESULTS_FILE" > "$temp_file" && mv "$temp_file" "$RESULTS_FILE"
}

# Helper: Add scenario result
add_scenario_result() {
    local scenario=$1
    local avg_ms=$2
    local min_ms=$3
    local max_ms=$4
    local stddev=$5
    local target=$6
    local status=$7

    local temp_file="${RESULTS_FILE}.tmp"
    jq ".scenarios[\"${scenario}\"] = {
        \"window_count\": ${scenario},
        \"avg_ms\": ${avg_ms},
        \"min_ms\": ${min_ms},
        \"max_ms\": ${max_ms},
        \"stddev_ms\": ${stddev},
        \"target_ms\": ${target},
        \"status\": \"${status}\",
        \"compliance\": $(if (( avg_ms <= target )); then echo "true"; else echo "false"; fi)
    }" "$RESULTS_FILE" > "$temp_file" && mv "$temp_file" "$RESULTS_FILE"
}

# Set metadata
update_json '.timestamp' "\"$(date -Iseconds)\""
update_json '.iterations' "$ITERATIONS"

# Test each scenario
for window_count in 5 10 20 40; do
    target_ms="${targets[$window_count]}"
    project_name="benchmark-project-${window_count}w"

    echo -e "${BLUE}Testing ${window_count}-window scenario (target: ${target_ms}ms)${NC}"

    # Check if project exists
    if ! i3pm project list | grep -q "^${project_name}$"; then
        echo -e "${YELLOW}⚠ Project ${project_name} not found, skipping${NC}"
        echo "  Run: tests/091-optimize-i3pm-project/fixtures/create_test_projects.sh"
        continue
    fi

    # Storage for timing results
    declare -a times_ms=()
    total_ms=0

    # Run iterations
    for i in $(seq 1 "$ITERATIONS"); do
        # Measure switch time
        start_ns=$(date +%s%N)
        i3pm project switch "$project_name" &>/dev/null
        end_ns=$(date +%s%N)

        duration_ns=$((end_ns - start_ns))
        duration_ms=$((duration_ns / 1000000))

        times_ms+=("$duration_ms")
        total_ms=$((total_ms + duration_ms))

        # Visual feedback
        if (( duration_ms <= target_ms )); then
            echo -e "  ${GREEN}✓${NC} Iteration $i: ${duration_ms}ms"
        else
            echo -e "  ${RED}✗${NC} Iteration $i: ${duration_ms}ms (exceeded target)"
        fi

        # Small delay between iterations
        sleep 0.5
    done

    # Calculate statistics
    avg_ms=$((total_ms / ITERATIONS))

    # Find min/max
    min_ms=${times_ms[0]}
    max_ms=${times_ms[0]}
    for time in "${times_ms[@]}"; do
        if (( time < min_ms )); then min_ms=$time; fi
        if (( time > max_ms )); then max_ms=$time; fi
    done

    # Calculate standard deviation
    sum_squared_diff=0
    for time in "${times_ms[@]}"; do
        diff=$((time - avg_ms))
        squared_diff=$((diff * diff))
        sum_squared_diff=$((sum_squared_diff + squared_diff))
    done
    variance=$((sum_squared_diff / ITERATIONS))
    stddev=$(echo "scale=2; sqrt($variance)" | bc 2>/dev/null || echo "N/A")

    # Determine status
    if (( avg_ms <= target_ms )); then
        status="pass"
        echo -e "${GREEN}✓ PASS: ${avg_ms}ms avg (target: ${target_ms}ms)${NC}"
    else
        status="fail"
        echo -e "${RED}✗ FAIL: ${avg_ms}ms avg (target: ${target_ms}ms)${NC}"
    fi

    # Add to results
    add_scenario_result "$window_count" "$avg_ms" "$min_ms" "$max_ms" "$stddev" "$target_ms" "$status"

    echo ""
    unset times_ms
done

# Generate summary
echo -e "${BLUE}=== Summary ===${NC}"
echo ""

# Calculate pass rate
total_scenarios=$(jq '.scenarios | length' "$RESULTS_FILE")
passed_scenarios=$(jq '[.scenarios[] | select(.compliance == true)] | length' "$RESULTS_FILE")
pass_rate=$((passed_scenarios * 100 / total_scenarios))

echo "Results saved to: $RESULTS_FILE"
echo ""
echo "Performance Summary:"
jq -r '.scenarios | to_entries[] |
    "  " + .key + "w: " +
    (.value.avg_ms | tostring) + "ms avg" +
    " (target: " + (.value.target_ms | tostring) + "ms) - " +
    (if .value.compliance then "✓ PASS" else "✗ FAIL" end)
' "$RESULTS_FILE"

echo ""
echo "Overall: ${passed_scenarios}/${total_scenarios} scenarios passed (${pass_rate}%)"

# Calculate p95 for 20-window scenario (US2 T031)
if jq -e '.scenarios["20"]' "$RESULTS_FILE" >/dev/null 2>&1; then
    echo ""
    echo -e "${BLUE}20-window p95 latency:${NC}"
    # Note: Actual p95 calculation would require storing individual times
    # For now, use max as approximation
    p95_approx=$(jq -r '.scenarios["20"].max_ms' "$RESULTS_FILE")
    target_p95=250
    if (( p95_approx <= target_p95 )); then
        echo -e "  ${GREEN}✓ ${p95_approx}ms (target: <${target_p95}ms)${NC}"
    else
        echo -e "  ${RED}✗ ${p95_approx}ms (target: <${target_p95}ms)${NC}"
    fi
fi

# Exit with appropriate code
if (( pass_rate == 100 )); then
    echo ""
    echo -e "${GREEN}✓ All scenarios passed!${NC}"
    exit 0
else
    echo ""
    echo -e "${RED}✗ Some scenarios failed${NC}"
    exit 1
fi
