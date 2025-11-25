#!/usr/bin/env bash
# Benchmark script for i3pm project switching performance
# Feature 091: Optimize i3pm Project Switching Performance
# Target: < 200ms average (96% improvement from 5.3s baseline)

set -euo pipefail

# Configuration
ITERATIONS=${1:-10}
PROJECT_A="${2:-benchmark-project-a}"
PROJECT_B="${3:-benchmark-project-b}"
RESULTS_FILE="${4:-$(dirname "$0")/baseline_results.json}"

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

echo "=== i3pm Project Switch Benchmark ==="
echo "Iterations: $ITERATIONS"
echo "Projects: $PROJECT_A ↔ $PROJECT_B"
echo "Results: $RESULTS_FILE"
echo ""

# Check if projects exist
check_project() {
    local project=$1
    if ! i3pm project list | grep -q "^$project$"; then
        echo -e "${RED}✗ Project '$project' not found${NC}"
        echo "Available projects:"
        i3pm project list
        exit 1
    fi
}

check_project "$PROJECT_A"
check_project "$PROJECT_B"

# Ensure we're starting from project A
i3pm project switch "$PROJECT_A" &>/dev/null
sleep 1

# Storage for results
declare -a switch_times_ms=()
total_ms=0

echo "Running $ITERATIONS iterations..."
echo ""

for i in $(seq 1 "$ITERATIONS"); do
    # Determine target project (alternate between A and B)
    if (( i % 2 == 1 )); then
        target="$PROJECT_B"
    else
        target="$PROJECT_A"
    fi

    # Measure switch time with nanosecond precision
    start_ns=$(date +%s%N)
    i3pm project switch "$target" &>/dev/null
    end_ns=$(date +%s%N)

    # Calculate duration in milliseconds
    duration_ns=$((end_ns - start_ns))
    duration_ms=$((duration_ns / 1000000))

    switch_times_ms+=("$duration_ms")
    total_ms=$((total_ms + duration_ms))

    # Print iteration result
    if (( duration_ms < 200 )); then
        color=$GREEN
        status="✓"
    elif (( duration_ms < 300 )); then
        color=$YELLOW
        status="⚠"
    else
        color=$RED
        status="✗"
    fi

    echo -e "${color}${status} Iteration $i: ${duration_ms}ms${NC} (switch to $target)"
done

echo ""
echo "=== Results ==="

# Calculate statistics
avg_ms=$((total_ms / ITERATIONS))
min_ms=${switch_times_ms[0]}
max_ms=${switch_times_ms[0]}

for time in "${switch_times_ms[@]}"; do
    if (( time < min_ms )); then
        min_ms=$time
    fi
    if (( time > max_ms )); then
        max_ms=$time
    fi
done

# Calculate standard deviation (approximate)
sum_squared_diff=0
for time in "${switch_times_ms[@]}"; do
    diff=$((time - avg_ms))
    squared_diff=$((diff * diff))
    sum_squared_diff=$((sum_squared_diff + squared_diff))
done
variance=$((sum_squared_diff / ITERATIONS))
# Approximate sqrt using bc if available
if command -v bc &>/dev/null; then
    stddev=$(echo "scale=2; sqrt($variance)" | bc)
else
    stddev="N/A (bc not installed)"
fi

echo "Average: ${avg_ms}ms"
echo "Min: ${min_ms}ms"
echo "Max: ${max_ms}ms"
echo "Std Dev: ${stddev}ms"
echo ""

# Performance assessment
if (( avg_ms < 200 )); then
    echo -e "${GREEN}✓ PASS: Average < 200ms (target met)${NC}"
    status="pass"
elif (( avg_ms < 300 )); then
    echo -e "${YELLOW}⚠ PARTIAL: Average < 300ms (close to target)${NC}"
    status="partial"
else
    echo -e "${RED}✗ FAIL: Average >= 300ms (optimization needed)${NC}"
    status="fail"
fi

# Save results to JSON
cat > "$RESULTS_FILE" << EOF
{
  "timestamp": "$(date -Iseconds)",
  "iterations": $ITERATIONS,
  "project_a": "$PROJECT_A",
  "project_b": "$PROJECT_B",
  "results": {
    "average_ms": $avg_ms,
    "min_ms": $min_ms,
    "max_ms": $max_ms,
    "stddev_ms": "$stddev",
    "total_ms": $total_ms,
    "status": "$status"
  },
  "individual_runs": [
$(for i in "${!switch_times_ms[@]}"; do
    echo "    $((i + 1)): ${switch_times_ms[$i]}"
done | sed 's/^/    /' | sed 's/: /: /' | sed 's/$/ms/' | paste -sd, | sed 's/,/,\n/g')
  ]
}
EOF

echo ""
echo "Results saved to: $RESULTS_FILE"

# Exit with appropriate code
if [[ "$status" == "pass" ]]; then
    exit 0
elif [[ "$status" == "partial" ]]; then
    exit 1
else
    exit 2
fi
